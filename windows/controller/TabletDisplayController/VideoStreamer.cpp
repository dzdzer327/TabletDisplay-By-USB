#include "VideoStreamer.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <functional>
#include <iomanip>
#include <iostream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <sstream>
#include <thread>
#include <unordered_map>
#include <vector>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <codecapi.h>
#include <icodecapi.h>
#include <d3d10_1.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace
{
    constexpr std::uint16_t StreamPort = 27183;
    constexpr std::uint16_t TouchPort = 27184;
    constexpr std::uint32_t PacketMagic = 0x54445350;
    constexpr std::uint32_t ProtocolVersion = 1;
    constexpr std::uint32_t FlagCodecConfig = 1;
    constexpr std::uint32_t FlagKeyFrame = 1u << 1;
    constexpr std::size_t MaxAccessUnitSize = 8u * 1024u * 1024u;
    constexpr std::uint32_t TouchPacketMagic = 0x54444950;
    constexpr std::uint32_t TouchProtocolVersion = 1;
    constexpr std::uint32_t TouchNormalizedMaximum = 1'000'000;
    constexpr std::uint32_t TouchActionDown = 1;
    constexpr std::uint32_t TouchActionMove = 2;
    constexpr std::uint32_t TouchActionUp = 3;
    constexpr std::uint32_t TouchActionCancel = 4;
    constexpr std::uint32_t MaximumTouchContacts = 10;

    class HResultError final : public std::runtime_error
    {
    public:
        HResultError(const char* operation, HRESULT result)
            : std::runtime_error(operation), Result(result)
        {
        }

        HRESULT Result;
    };

    void CheckHr(HRESULT result, const char* operation)
    {
        if (FAILED(result))
        {
            throw HResultError(operation, result);
        }
    }

    class HighResolutionFramePacer
    {
    public:
        explicit HighResolutionFramePacer(std::uint32_t framesPerSecond)
            : m_Period(std::chrono::nanoseconds(1'000'000'000 / framesPerSecond))
        {
            m_Timer = CreateWaitableTimerExW(
                nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
            if (m_Timer == nullptr)
            {
                m_Timer = CreateWaitableTimerW(nullptr, FALSE, nullptr);
            }
        }

        ~HighResolutionFramePacer()
        {
            if (m_Timer != nullptr)
            {
                CloseHandle(m_Timer);
            }
        }

        void Reset()
        {
            m_Started = false;
        }

        void Wait()
        {
            const auto now = std::chrono::steady_clock::now();
            if (!m_Started)
            {
                m_NextFrame = now;
                m_Started = true;
                return;
            }

            m_NextFrame += m_Period;
            if (m_NextFrame + m_Period < now)
            {
                m_NextFrame = now;
                return;
            }
            if (m_NextFrame <= now || m_Timer == nullptr)
            {
                return;
            }

            const auto remaining = std::chrono::duration_cast<std::chrono::nanoseconds>(
                m_NextFrame - now).count();
            LARGE_INTEGER dueTime = {};
            dueTime.QuadPart = -std::max<LONGLONG>(1, remaining / 100);
            if (SetWaitableTimer(m_Timer, &dueTime, 0, nullptr, nullptr, FALSE))
            {
                WaitForSingleObject(m_Timer, INFINITE);
            }
        }

    private:
        HANDLE m_Timer = nullptr;
        std::chrono::nanoseconds m_Period;
        std::chrono::steady_clock::time_point m_NextFrame = {};
        bool m_Started = false;
    };

    std::uint64_t HostToNetwork64(std::uint64_t value)
    {
        const auto high = htonl(static_cast<std::uint32_t>(value >> 32));
        const auto low = htonl(static_cast<std::uint32_t>(value & 0xffffffffu));
        return (static_cast<std::uint64_t>(low) << 32) | high;
    }

    bool HasAnnexBStartCode(const std::vector<std::uint8_t>& bytes)
    {
        return bytes.size() >= 4 && bytes[0] == 0 && bytes[1] == 0 &&
               ((bytes[2] == 1) || (bytes[2] == 0 && bytes[3] == 1));
    }

    std::vector<std::uint8_t> AvccAccessUnitToAnnexB(const std::vector<std::uint8_t>& input)
    {
        if (input.empty() || HasAnnexBStartCode(input))
        {
            return input;
        }

        std::vector<std::uint8_t> output;
        output.reserve(input.size() + 32);
        std::size_t offset = 0;
        while (offset + 4 <= input.size())
        {
            const std::uint32_t size =
                (static_cast<std::uint32_t>(input[offset]) << 24) |
                (static_cast<std::uint32_t>(input[offset + 1]) << 16) |
                (static_cast<std::uint32_t>(input[offset + 2]) << 8) |
                static_cast<std::uint32_t>(input[offset + 3]);
            offset += 4;
            if (size == 0 || size > input.size() - offset)
            {
                // Some encoders already emit a byte stream whose first NAL does not
                // start at byte zero. Preserve it rather than corrupting the frame.
                return input;
            }

            output.insert(output.end(), {0, 0, 0, 1});
            output.insert(output.end(), input.begin() + static_cast<std::ptrdiff_t>(offset),
                          input.begin() + static_cast<std::ptrdiff_t>(offset + size));
            offset += size;
        }

        return offset == input.size() ? output : input;
    }

    std::vector<std::uint8_t> AvccConfigToAnnexB(const std::uint8_t* bytes, std::size_t size)
    {
        if (bytes == nullptr || size == 0)
        {
            return {};
        }

        std::vector<std::uint8_t> input(bytes, bytes + size);
        if (HasAnnexBStartCode(input))
        {
            return input;
        }
        if (size < 7 || bytes[0] != 1)
        {
            return input;
        }

        std::vector<std::uint8_t> output;
        std::size_t offset = 5;
        const unsigned spsCount = bytes[offset++] & 0x1f;
        auto appendUnits = [&](unsigned count) -> bool
        {
            for (unsigned index = 0; index < count; ++index)
            {
                if (offset + 2 > size)
                {
                    return false;
                }
                const std::size_t unitSize =
                    (static_cast<std::size_t>(bytes[offset]) << 8) | bytes[offset + 1];
                offset += 2;
                if (unitSize == 0 || offset + unitSize > size)
                {
                    return false;
                }
                output.insert(output.end(), {0, 0, 0, 1});
                output.insert(output.end(), bytes + offset, bytes + offset + unitSize);
                offset += unitSize;
            }
            return true;
        };

        if (!appendUnits(spsCount) || offset >= size)
        {
            return {};
        }
        const unsigned ppsCount = bytes[offset++];
        return appendUnits(ppsCount) ? output : std::vector<std::uint8_t>{};
    }

    class TcpTransport
    {
    public:
        ~TcpTransport()
        {
            Close();
        }

        bool Connect()
        {
            Close();
            m_Socket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
            if (m_Socket == INVALID_SOCKET)
            {
                return false;
            }

            BOOL noDelay = TRUE;
            setsockopt(m_Socket, IPPROTO_TCP, TCP_NODELAY,
                       reinterpret_cast<const char*>(&noDelay), sizeof(noDelay));
            DWORD timeoutMs = 1000;
            setsockopt(m_Socket, SOL_SOCKET, SO_SNDTIMEO,
                       reinterpret_cast<const char*>(&timeoutMs), sizeof(timeoutMs));

            sockaddr_in address = {};
            address.sin_family = AF_INET;
            address.sin_port = htons(StreamPort);
            address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            if (connect(m_Socket, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == SOCKET_ERROR)
            {
                Close();
                return false;
            }
            return true;
        }

        void Close()
        {
            if (m_Socket != INVALID_SOCKET)
            {
                closesocket(m_Socket);
                m_Socket = INVALID_SOCKET;
            }
        }

        bool IsConnected() const
        {
            return m_Socket != INVALID_SOCKET;
        }

        bool SendPacket(
            std::uint32_t width,
            std::uint32_t height,
            std::uint32_t flags,
            std::uint64_t presentationTimeUs,
            const std::vector<std::uint8_t>& payload)
        {
            if (!IsConnected() || payload.size() > MaxAccessUnitSize)
            {
                return false;
            }

            std::array<std::uint8_t, 32> header = {};
            const auto put32 = [&](std::size_t offset, std::uint32_t value)
            {
                value = htonl(value);
                std::memcpy(header.data() + offset, &value, sizeof(value));
            };
            put32(0, PacketMagic);
            put32(4, ProtocolVersion);
            put32(8, width);
            put32(12, height);
            put32(16, flags);
            put32(20, static_cast<std::uint32_t>(payload.size()));
            const auto networkTimestamp = HostToNetwork64(presentationTimeUs);
            std::memcpy(header.data() + 24, &networkTimestamp, sizeof(networkTimestamp));

            if (!SendAll(header.data(), header.size()) ||
                (!payload.empty() && !SendAll(payload.data(), payload.size())))
            {
                Close();
                return false;
            }
            return true;
        }

    private:
        bool SendAll(const std::uint8_t* bytes, std::size_t size)
        {
            while (size != 0)
            {
                const int chunkSize = static_cast<int>(std::min<std::size_t>(size, 64 * 1024));
                const int sent = send(m_Socket, reinterpret_cast<const char*>(bytes), chunkSize, 0);
                if (sent <= 0)
                {
                    return false;
                }
                bytes += sent;
                size -= static_cast<std::size_t>(sent);
            }
            return true;
        }

        SOCKET m_Socket = INVALID_SOCKET;
    };

    class TouchInputServer
    {
    public:
        using StatusCallback = std::function<void(bool, std::uint64_t, LONG)>;

        TouchInputServer(
            const RECT& displayRectangle,
            const std::atomic_bool& applicationStop,
            StatusCallback callback,
            bool touchEnabled)
            : m_DisplayRectangle(displayRectangle),
              m_ApplicationStop(applicationStop),
              m_Callback(std::move(callback)),
              m_TouchEnabled(touchEnabled),
              m_Thread([this]() { Run(); })
        {
        }

        ~TouchInputServer()
        {
            m_LocalStop = true;
            if (m_Thread.joinable())
            {
                m_Thread.join();
            }
        }

        TouchInputServer(const TouchInputServer&) = delete;
        TouchInputServer& operator=(const TouchInputServer&) = delete;

    private:
        struct LastContact
        {
            POINT Point = {};
            UINT32 Pressure = 512;
        };

        bool ShouldStop() const
        {
            return m_LocalStop || m_ApplicationStop;
        }

        static std::uint32_t ReadNetworkUInt32(const std::uint8_t* bytes)
        {
            std::uint32_t value = 0;
            std::memcpy(&value, bytes, sizeof(value));
            return ntohl(value);
        }

        bool ReadExact(SOCKET client, std::uint8_t* destination, std::size_t size)
        {
            while (size != 0 && !ShouldStop())
            {
                const int requested = static_cast<int>(std::min<std::size_t>(size, 64 * 1024));
                const int received = recv(client, reinterpret_cast<char*>(destination), requested, 0);
                if (received > 0)
                {
                    destination += received;
                    size -= static_cast<std::size_t>(received);
                    continue;
                }
                if (received == 0)
                {
                    return false;
                }
                const int error = WSAGetLastError();
                if (error == WSAETIMEDOUT || error == WSAEWOULDBLOCK)
                {
                    continue;
                }
                return false;
            }
            return size == 0;
        }

        POINT ToDesktopPoint(std::uint32_t normalizedX, std::uint32_t normalizedY) const
        {
            const LONG width = std::max<LONG>(1, m_DisplayRectangle.right - m_DisplayRectangle.left);
            const LONG height = std::max<LONG>(1, m_DisplayRectangle.bottom - m_DisplayRectangle.top);
            POINT point = {};
            point.x = m_DisplayRectangle.left + static_cast<LONG>(
                (static_cast<std::uint64_t>((std::min)(normalizedX, TouchNormalizedMaximum)) *
                 static_cast<std::uint64_t>(width - 1)) /
                TouchNormalizedMaximum);
            point.y = m_DisplayRectangle.top + static_cast<LONG>(
                (static_cast<std::uint64_t>((std::min)(normalizedY, TouchNormalizedMaximum)) *
                 static_cast<std::uint64_t>(height - 1)) /
                TouchNormalizedMaximum);
            return point;
        }

        POINTER_TOUCH_INFO MakeTouchInfo(
            UINT32 pointerId,
            UINT32 action,
            const POINT& point,
            UINT32 pressure) const
        {
            POINTER_TOUCH_INFO touch = {};
            touch.pointerInfo.pointerType = PT_TOUCH;
            touch.pointerInfo.pointerId = pointerId;
            touch.pointerInfo.ptPixelLocation = point;
            switch (action)
            {
            case TouchActionDown:
                touch.pointerInfo.pointerFlags =
                    POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT;
                break;
            case TouchActionUp:
                touch.pointerInfo.pointerFlags = POINTER_FLAG_UP;
                break;
            case TouchActionCancel:
                touch.pointerInfo.pointerFlags = POINTER_FLAG_UP | POINTER_FLAG_CANCELED;
                break;
            default:
                touch.pointerInfo.pointerFlags =
                    POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT;
                break;
            }
            touch.touchFlags = TOUCH_FLAG_NONE;
            touch.touchMask = TOUCH_MASK_CONTACTAREA | TOUCH_MASK_ORIENTATION | TOUCH_MASK_PRESSURE;
            touch.rcContact = {point.x - 3, point.y - 3, point.x + 3, point.y + 3};
            touch.orientation = 90;
            touch.pressure = std::clamp<UINT32>(pressure, 1, 1024);
            return touch;
        }

        bool ProcessFrame(SOCKET client)
        {
            std::array<std::uint8_t, 16> header = {};
            if (!ReadExact(client, header.data(), header.size()))
            {
                return false;
            }
            const std::uint32_t magic = ReadNetworkUInt32(header.data());
            const std::uint32_t version = ReadNetworkUInt32(header.data() + 4);
            const std::uint32_t contactCount = ReadNetworkUInt32(header.data() + 8);
            if (magic != TouchPacketMagic || version != TouchProtocolVersion ||
                contactCount == 0 || contactCount > MaximumTouchContacts)
            {
                m_Callback(true, m_InjectedFrames, ERROR_INVALID_DATA);
                return false;
            }

            std::vector<std::uint8_t> contactBytes(static_cast<std::size_t>(contactCount) * 20);
            if (!ReadExact(client, contactBytes.data(), contactBytes.size()))
            {
                return false;
            }

            if (!m_TouchEnabled) return true;
            std::vector<POINTER_TOUCH_INFO> touches;
            struct ContactUpdate
            {
                UINT32 PointerId;
                UINT32 Action;
                POINT Point;
                UINT32 Pressure;
            };
            std::vector<ContactUpdate> updates;
            touches.reserve(contactCount);
            updates.reserve(contactCount);
            for (std::uint32_t index = 0; index < contactCount; ++index)
            {
                const auto* contact = contactBytes.data() + static_cast<std::size_t>(index) * 20;
                const UINT32 pointerId = ReadNetworkUInt32(contact);
                const UINT32 action = ReadNetworkUInt32(contact + 4);
                const UINT32 normalizedX = ReadNetworkUInt32(contact + 8);
                const UINT32 normalizedY = ReadNetworkUInt32(contact + 12);
                const UINT32 pressure = ReadNetworkUInt32(contact + 16);
                if (pointerId == 0 || pointerId > 256 ||
                    action < TouchActionDown || action > TouchActionCancel)
                {
                    m_Callback(true, m_InjectedFrames, ERROR_INVALID_DATA);
                    return false;
                }

                const POINT point = ToDesktopPoint(normalizedX, normalizedY);
                const bool contactIsActive = m_ActiveContacts.find(pointerId) != m_ActiveContacts.end();
                if (action != TouchActionDown && !contactIsActive)
                {
                    // Reconnection can begin in the middle of a gesture. Ignore
                    // it until the next complete DOWN sequence arrives.
                    continue;
                }
                touches.push_back(MakeTouchInfo(pointerId, action, point, pressure));
                updates.push_back({pointerId, action, point, pressure});
            }

            if (touches.empty())
            {
                return true;
            }

            if (!InjectTouchInput(static_cast<UINT32>(touches.size()), touches.data()))
            {
                const LONG error = static_cast<LONG>(GetLastError());
                ReleaseActiveContacts();
                m_Callback(true, m_InjectedFrames, error);
                return true;
            }

            for (const auto& update : updates)
            {
                if (update.Action == TouchActionUp || update.Action == TouchActionCancel)
                {
                    m_ActiveContacts.erase(update.PointerId);
                }
                else
                {
                    m_ActiveContacts[update.PointerId] = {update.Point, update.Pressure};
                }
            }
            ++m_InjectedFrames;
            m_Callback(true, m_InjectedFrames, ERROR_SUCCESS);
            return true;
        }

        void ReleaseActiveContacts()
        {
            if (m_ActiveContacts.empty())
            {
                return;
            }
            std::vector<POINTER_TOUCH_INFO> touches;
            touches.reserve(m_ActiveContacts.size());
            for (const auto& [pointerId, contact] : m_ActiveContacts)
            {
                touches.push_back(MakeTouchInfo(
                    pointerId, TouchActionCancel, contact.Point, contact.Pressure));
            }
            InjectTouchInput(static_cast<UINT32>(touches.size()), touches.data());
            m_ActiveContacts.clear();
        }

        void Run()
        {
            if (!InitializeTouchInjection(MaximumTouchContacts, TOUCH_FEEDBACK_DEFAULT))
            {
                m_Callback(false, 0, static_cast<LONG>(GetLastError()));
                return;
            }

            SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
            if (listener == INVALID_SOCKET)
            {
                m_Callback(false, 0, static_cast<LONG>(WSAGetLastError()));
                return;
            }

            sockaddr_in address = {};
            address.sin_family = AF_INET;
            address.sin_port = htons(TouchPort);
            address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            BOOL reuseAddress = TRUE;
            setsockopt(listener, SOL_SOCKET, SO_REUSEADDR,
                       reinterpret_cast<const char*>(&reuseAddress), sizeof(reuseAddress));
            if (bind(listener, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == SOCKET_ERROR ||
                listen(listener, 1) == SOCKET_ERROR)
            {
                const LONG error = static_cast<LONG>(WSAGetLastError());
                closesocket(listener);
                m_Callback(false, 0, error);
                return;
            }

            while (!ShouldStop())
            {
                fd_set readSet;
                FD_ZERO(&readSet);
                FD_SET(listener, &readSet);
                timeval timeout = {0, 200'000};
                const int ready = select(0, &readSet, nullptr, nullptr, &timeout);
                if (ready <= 0)
                {
                    continue;
                }

                SOCKET client = accept(listener, nullptr, nullptr);
                if (client == INVALID_SOCKET)
                {
                    continue;
                }
                DWORD receiveTimeout = 200;
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO,
                           reinterpret_cast<const char*>(&receiveTimeout), sizeof(receiveTimeout));
                m_Callback(true, m_InjectedFrames, ERROR_SUCCESS);
                while (!ShouldStop() && ProcessFrame(client))
                {
                }
                ReleaseActiveContacts();
                closesocket(client);
                m_Callback(false, m_InjectedFrames, ERROR_SUCCESS);
            }

            closesocket(listener);
        }

        RECT m_DisplayRectangle = {};
        const std::atomic_bool& m_ApplicationStop;
        StatusCallback m_Callback;
        bool m_TouchEnabled = true;
        std::atomic_bool m_LocalStop = false;
        std::uint64_t m_InjectedFrames = 0;
        std::unordered_map<UINT32, LastContact> m_ActiveContacts;
        std::thread m_Thread;
    };

    struct SelectedOutput
    {
        ComPtr<IDXGIAdapter1> Adapter;
        ComPtr<IDXGIOutput1> Output;
        DXGI_OUTPUT_DESC Description = {};
    };

    bool IsPrimaryOutput(const DXGI_OUTPUT_DESC& description)
    {
        MONITORINFO info = {};
        info.cbSize = sizeof(info);
        return description.Monitor != nullptr && GetMonitorInfoW(description.Monitor, &info) &&
               (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
    }

    bool UsesIndirectTechnology(const wchar_t* gdiName)
    {
        UINT32 pathCount = 0;
        UINT32 modeCount = 0;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS)
        {
            return false;
        }

        std::vector<DISPLAYCONFIG_PATH_INFO> paths(pathCount);
        std::vector<DISPLAYCONFIG_MODE_INFO> modes(modeCount);
        if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(), &modeCount,
                               modes.data(), nullptr) != ERROR_SUCCESS)
        {
            return false;
        }

        for (UINT32 index = 0; index < pathCount; ++index)
        {
            DISPLAYCONFIG_SOURCE_DEVICE_NAME source = {};
            source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            source.header.size = sizeof(source);
            source.header.adapterId = paths[index].sourceInfo.adapterId;
            source.header.id = paths[index].sourceInfo.id;
            if (DisplayConfigGetDeviceInfo(&source.header) == ERROR_SUCCESS &&
                _wcsicmp(source.viewGdiDeviceName, gdiName) == 0)
            {
                return paths[index].targetInfo.outputTechnology == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_OTHER;
            }
        }
        return false;
    }

    bool FindTabletOutput(SelectedOutput& selected, std::wstring& candidates)
    {
        ComPtr<IDXGIFactory1> factory;
        CheckHr(CreateDXGIFactory1(IID_PPV_ARGS(&factory)), "CreateDXGIFactory1");

        SelectedOutput fallback;
        for (UINT adapterIndex = 0;; ++adapterIndex)
        {
            ComPtr<IDXGIAdapter1> adapter;
            if (factory->EnumAdapters1(adapterIndex, &adapter) == DXGI_ERROR_NOT_FOUND)
            {
                break;
            }

            DXGI_ADAPTER_DESC1 adapterDescription = {};
            adapter->GetDesc1(&adapterDescription);
            for (UINT outputIndex = 0;; ++outputIndex)
            {
                ComPtr<IDXGIOutput> baseOutput;
                if (adapter->EnumOutputs(outputIndex, &baseOutput) == DXGI_ERROR_NOT_FOUND)
                {
                    break;
                }
                DXGI_OUTPUT_DESC description = {};
                if (FAILED(baseOutput->GetDesc(&description)) || !description.AttachedToDesktop)
                {
                    continue;
                }

                candidates += description.DeviceName;
                candidates += L" on ";
                candidates += adapterDescription.Description;
                candidates += L"; ";

                if (!IsTabletDisplayName(description.DeviceName))
                {
                    continue;
                }

                ComPtr<IDXGIOutput1> output;
                if (FAILED(baseOutput.As(&output)))
                {
                    continue;
                }

                SelectedOutput current = {adapter, output, description};
                if (UsesIndirectTechnology(description.DeviceName))
                {
                    selected = std::move(current);
                    return true;
                }
                if (!fallback.Output)
                {
                    fallback = std::move(current);
                }
            }
        }

        if (fallback.Output)
        {
            selected = std::move(fallback);
            return true;
        }
        return false;
    }

    class DesktopCapture
    {
    public:
        void Initialize(const SelectedOutput& selected, const SessionSettings& settings)
        {
            m_FrameRate = settings.FrameRate;
            m_InputRefreshRate = settings.RefreshRate;
            UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
#if defined(_DEBUG)
            flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
            D3D_FEATURE_LEVEL featureLevel = {};
            HRESULT result = D3D11CreateDevice(
                selected.Adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr, flags, nullptr, 0,
                D3D11_SDK_VERSION, &m_Device, &featureLevel, &m_Context);
            if (result == DXGI_ERROR_SDK_COMPONENT_MISSING)
            {
                flags &= ~D3D11_CREATE_DEVICE_DEBUG;
                result = D3D11CreateDevice(
                    selected.Adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr, flags, nullptr, 0,
                    D3D11_SDK_VERSION, &m_Device, &featureLevel, &m_Context);
            }
            CheckHr(result, "D3D11CreateDevice");

            ComPtr<ID3D10Multithread> multithread;
            if (SUCCEEDED(m_Device.As(&multithread)))
            {
                multithread->SetMultithreadProtected(TRUE);
            }
            CheckHr(selected.Output->DuplicateOutput(m_Device.Get(), &m_Duplication), "DuplicateOutput");

            DXGI_OUTDUPL_DESC duplicationDescription = {};
            m_Duplication->GetDesc(&duplicationDescription);
            m_Width = duplicationDescription.ModeDesc.Width;
            m_Height = duplicationDescription.ModeDesc.Height;
            InitializeVideoProcessor();
        }

        HRESULT AcquireNv12(ComPtr<ID3D11Texture2D>& result)
        {
            result.Reset();
            DXGI_OUTDUPL_FRAME_INFO frameInfo = {};
            ComPtr<IDXGIResource> resource;
            HRESULT status = m_Duplication->AcquireNextFrame(100, &frameInfo, &resource);
            if (status == DXGI_ERROR_WAIT_TIMEOUT)
            {
                return status;
            }
            if (FAILED(status))
            {
                return status;
            }

            struct FrameReleaser
            {
                IDXGIOutputDuplication* Duplication;
                ~FrameReleaser() { Duplication->ReleaseFrame(); }
            } release{m_Duplication.Get()};

            ComPtr<ID3D11Texture2D> texture;
            CheckHr(resource.As(&texture), "Query desktop texture");

            D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC inputDescription = {};
            inputDescription.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
            inputDescription.Texture2D.MipSlice = 0;
            inputDescription.Texture2D.ArraySlice = 0;
            ComPtr<ID3D11VideoProcessorInputView> inputView;
            CheckHr(m_VideoDevice->CreateVideoProcessorInputView(
                        texture.Get(), m_ProcessorEnumerator.Get(), &inputDescription, &inputView),
                    "CreateVideoProcessorInputView");

            RECT rectangle = {0, 0, static_cast<LONG>(m_Width), static_cast<LONG>(m_Height)};
            m_VideoContext->VideoProcessorSetStreamFrameFormat(
                m_Processor.Get(), 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
            m_VideoContext->VideoProcessorSetStreamSourceRect(m_Processor.Get(), 0, TRUE, &rectangle);
            m_VideoContext->VideoProcessorSetStreamDestRect(m_Processor.Get(), 0, TRUE, &rectangle);
            m_VideoContext->VideoProcessorSetOutputTargetRect(m_Processor.Get(), TRUE, &rectangle);

            D3D11_VIDEO_PROCESSOR_STREAM stream = {};
            stream.Enable = TRUE;
            stream.pInputSurface = inputView.Get();
            ComPtr<ID3D11Texture2D> nv12Texture;
            CheckHr(m_Device->CreateTexture2D(&m_Nv12Description, nullptr, &nv12Texture),
                    "Create zero-copy NV12 texture");
            D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC outputDescription = {};
            outputDescription.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
            outputDescription.Texture2D.MipSlice = 0;
            ComPtr<ID3D11VideoProcessorOutputView> outputView;
            CheckHr(m_VideoDevice->CreateVideoProcessorOutputView(
                        nv12Texture.Get(), m_ProcessorEnumerator.Get(), &outputDescription,
                        &outputView),
                    "Create zero-copy NV12 output view");
            CheckHr(m_VideoContext->VideoProcessorBlt(
                        m_Processor.Get(), outputView.Get(), 0, 1, &stream),
                    "VideoProcessorBlt BGRA to zero-copy NV12");

            result = std::move(nv12Texture);
            return S_OK;
        }

        UINT Width() const { return m_Width; }
        UINT Height() const { return m_Height; }
        ID3D11Device* Device() const { return m_Device.Get(); }

        HRESULT RecreateDuplication(const SelectedOutput& selected)
        {
            m_Duplication.Reset();
            const HRESULT result = selected.Output->DuplicateOutput(m_Device.Get(), &m_Duplication);
            if (FAILED(result))
            {
                return result;
            }

            DXGI_OUTDUPL_DESC duplicationDescription = {};
            m_Duplication->GetDesc(&duplicationDescription);
            if (duplicationDescription.ModeDesc.Width != m_Width ||
                duplicationDescription.ModeDesc.Height != m_Height)
            {
                return DXGI_ERROR_MODE_CHANGE_IN_PROGRESS;
            }
            return S_OK;
        }

    private:
        void InitializeVideoProcessor()
        {
            CheckHr(m_Device.As(&m_VideoDevice), "Get ID3D11VideoDevice");
            CheckHr(m_Context.As(&m_VideoContext), "Get ID3D11VideoContext");

            D3D11_VIDEO_PROCESSOR_CONTENT_DESC content = {};
            content.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
            content.InputFrameRate = {m_InputRefreshRate, 1};
            content.InputWidth = m_Width;
            content.InputHeight = m_Height;
            content.OutputFrameRate = {m_FrameRate, 1};
            content.OutputWidth = m_Width;
            content.OutputHeight = m_Height;
            content.Usage = D3D11_VIDEO_USAGE_OPTIMAL_SPEED;
            CheckHr(m_VideoDevice->CreateVideoProcessorEnumerator(&content, &m_ProcessorEnumerator),
                    "CreateVideoProcessorEnumerator");
            CheckHr(m_VideoDevice->CreateVideoProcessor(m_ProcessorEnumerator.Get(), 0, &m_Processor),
                    "CreateVideoProcessor");

            m_Nv12Description = {};
            m_Nv12Description.Width = m_Width;
            m_Nv12Description.Height = m_Height;
            m_Nv12Description.MipLevels = 1;
            m_Nv12Description.ArraySize = 1;
            m_Nv12Description.Format = DXGI_FORMAT_NV12;
            m_Nv12Description.SampleDesc.Count = 1;
            m_Nv12Description.Usage = D3D11_USAGE_DEFAULT;
            m_Nv12Description.BindFlags =
                D3D11_BIND_RENDER_TARGET | D3D11_BIND_VIDEO_ENCODER;
        }

        UINT m_Width = 0;
        UINT m_Height = 0;
        UINT m_FrameRate = 60;
        UINT m_InputRefreshRate = 60;
        ComPtr<ID3D11Device> m_Device;
        ComPtr<ID3D11DeviceContext> m_Context;
        ComPtr<IDXGIOutputDuplication> m_Duplication;
        ComPtr<ID3D11VideoDevice> m_VideoDevice;
        ComPtr<ID3D11VideoContext> m_VideoContext;
        ComPtr<ID3D11VideoProcessorEnumerator> m_ProcessorEnumerator;
        ComPtr<ID3D11VideoProcessor> m_Processor;
        D3D11_TEXTURE2D_DESC m_Nv12Description = {};
    };

    struct EncodedAccessUnit
    {
        std::vector<std::uint8_t> Bytes;
        std::uint64_t PresentationTimeUs = 0;
        bool KeyFrame = false;
    };

    void TrySetCodecUInt32(ICodecAPI* codec, const GUID& property, ULONG value)
    {
        if (codec == nullptr)
        {
            return;
        }
        VARIANT setting;
        VariantInit(&setting);
        setting.vt = VT_UI4;
        setting.ulVal = value;
        codec->SetValue(&property, &setting);
        VariantClear(&setting);
    }

    void TrySetCodecBool(ICodecAPI* codec, const GUID& property, bool value)
    {
        if (codec == nullptr)
        {
            return;
        }
        VARIANT setting;
        VariantInit(&setting);
        setting.vt = VT_BOOL;
        setting.boolVal = value ? VARIANT_TRUE : VARIANT_FALSE;
        codec->SetValue(&property, &setting);
        VariantClear(&setting);
    }

    class H264Encoder
    {
    public:
        void Initialize(UINT width, UINT height, ID3D11Device* d3dDevice, const SessionSettings& settings)
        {
            m_Settings = settings;
            m_Width = width;
            m_Height = height;
            if (!ActivateEncoder(true))
            {
                CheckHr(ActivateEncoder(false) ? S_OK : MF_E_TOPO_CODEC_NOT_FOUND,
                        "No Media Foundation H.264 encoder was found");
            }
            Configure(d3dDevice);
        }

        std::vector<EncodedAccessUnit> Encode(
            ID3D11Texture2D* nv12,
            std::uint64_t presentationTimeUs)
        {
            ComPtr<IMFSample> sample;
            ComPtr<IMFMediaBuffer> buffer;
            CheckHr(MFCreateSample(&sample), "MFCreateSample input");
            CheckHr(MFCreateDXGISurfaceBuffer(
                        __uuidof(ID3D11Texture2D), nv12, 0, FALSE, &buffer),
                    "MFCreateDXGISurfaceBuffer input");
            CheckHr(sample->AddBuffer(buffer.Get()), "Add input buffer");
            CheckHr(sample->SetSampleTime(static_cast<LONGLONG>(presentationTimeUs * 10)),
                    "Set input sample time");
            CheckHr(sample->SetSampleDuration(10'000'000 / m_Settings.FrameRate),
                    "Set input sample duration");

            std::vector<EncodedAccessUnit> output;
            if (m_IsAsync)
            {
                while (m_NeedInputCount == 0)
                {
                    ProcessOneEvent(false, output);
                }
                CheckHr(m_Transform->ProcessInput(m_InputStreamId, sample.Get(), 0),
                        "Async encoder ProcessInput");
                --m_NeedInputCount;
                while (ProcessOneEvent(true, output))
                {
                }
            }
            else
            {
                HRESULT inputResult = m_Transform->ProcessInput(m_InputStreamId, sample.Get(), 0);
                if (inputResult == MF_E_NOTACCEPTING)
                {
                    DrainSynchronous(output);
                    inputResult = m_Transform->ProcessInput(m_InputStreamId, sample.Get(), 0);
                }
                CheckHr(inputResult, "Encoder ProcessInput");
                DrainSynchronous(output);
            }
            return output;
        }

        const std::vector<std::uint8_t>& CodecConfig() const { return m_CodecConfig; }
        const std::wstring& Name() const { return m_Name; }
        bool IsHardware() const { return m_IsHardware; }
        bool UsesD3D11Input() const { return m_UsesD3D11Input; }

    private:
        bool ActivateEncoder(bool hardware)
        {
            MFT_REGISTER_TYPE_INFO inputInfo = {MFMediaType_Video, MFVideoFormat_NV12};
            MFT_REGISTER_TYPE_INFO outputInfo = {MFMediaType_Video, MFVideoFormat_H264};
            IMFActivate** activations = nullptr;
            UINT32 count = 0;
            const UINT32 flags = hardware
                ? MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER
                : MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_LOCALMFT | MFT_ENUM_FLAG_SORTANDFILTER;
            const HRESULT result = MFTEnumEx(
                MFT_CATEGORY_VIDEO_ENCODER, flags, &inputInfo, &outputInfo, &activations, &count);
            if (FAILED(result) || count == 0)
            {
                if (activations != nullptr)
                {
                    CoTaskMemFree(activations);
                }
                return false;
            }

            WCHAR* name = nullptr;
            UINT32 nameLength = 0;
            if (SUCCEEDED(activations[0]->GetAllocatedString(
                    MFT_FRIENDLY_NAME_Attribute, &name, &nameLength)))
            {
                m_Name.assign(name, nameLength);
                CoTaskMemFree(name);
            }
            const HRESULT activationResult = activations[0]->ActivateObject(IID_PPV_ARGS(&m_Transform));
            for (UINT32 index = 0; index < count; ++index)
            {
                activations[index]->Release();
            }
            CoTaskMemFree(activations);
            if (FAILED(activationResult))
            {
                m_Transform.Reset();
                return false;
            }
            m_IsHardware = hardware;
            return true;
        }

        void Configure(ID3D11Device* d3dDevice)
        {
            ComPtr<IMFAttributes> attributes;
            CheckHr(m_Transform->GetAttributes(&attributes), "Get encoder attributes");
            UINT32 asynchronous = FALSE;
            attributes->GetUINT32(MF_TRANSFORM_ASYNC, &asynchronous);
            m_IsAsync = asynchronous != FALSE;
            if (m_IsAsync)
            {
                CheckHr(attributes->SetUINT32(MF_TRANSFORM_ASYNC_UNLOCK, TRUE),
                        "Unlock asynchronous encoder");
                CheckHr(m_Transform.As(&m_EventGenerator), "Get encoder event generator");
            }

            UINT32 d3d11Aware = FALSE;
            if (FAILED(attributes->GetUINT32(MF_SA_D3D11_AWARE, &d3d11Aware)) ||
                d3d11Aware == FALSE)
            {
                throw HResultError("H.264 encoder does not support D3D11 surface input",
                                   MF_E_UNSUPPORTED_D3D_TYPE);
            }
            CheckHr(MFCreateDXGIDeviceManager(&m_DeviceResetToken, &m_DeviceManager),
                    "MFCreateDXGIDeviceManager");
            CheckHr(m_DeviceManager->ResetDevice(d3dDevice, m_DeviceResetToken),
                    "Reset encoder D3D11 device");
            CheckHr(m_Transform->ProcessMessage(
                        MFT_MESSAGE_SET_D3D_MANAGER,
                        reinterpret_cast<ULONG_PTR>(m_DeviceManager.Get())),
                    "Set encoder D3D11 device manager");
            m_UsesD3D11Input = true;

            DWORD inputCount = 0;
            DWORD outputCount = 0;
            CheckHr(m_Transform->GetStreamCount(&inputCount, &outputCount), "Get encoder stream count");
            DWORD inputId = 0;
            DWORD outputId = 0;
            if (m_Transform->GetStreamIDs(1, &inputId, 1, &outputId) != E_NOTIMPL)
            {
                m_InputStreamId = inputId;
                m_OutputStreamId = outputId;
            }

            ComPtr<ICodecAPI> codec;
            m_Transform.As(&codec);
            TrySetCodecUInt32(codec.Get(), CODECAPI_AVEncMPVDefaultBPictureCount, 0);
            TrySetCodecUInt32(codec.Get(), CODECAPI_AVEncMPVGOPSize, m_Settings.FrameRate);
            TrySetCodecUInt32(codec.Get(), CODECAPI_AVEncCommonRateControlMode,
                              eAVEncCommonRateControlMode_CBR);
            TrySetCodecUInt32(codec.Get(), CODECAPI_AVEncCommonMeanBitRate, m_Settings.BitRate);
            TrySetCodecUInt32(codec.Get(), CODECAPI_AVEncCommonQualityVsSpeed, 33);
            TrySetCodecBool(codec.Get(), CODECAPI_AVLowLatencyMode, true);

            ComPtr<IMFMediaType> outputType;
            CheckHr(MFCreateMediaType(&outputType), "Create H.264 output type");
            CheckHr(outputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video), "Set output major type");
            CheckHr(outputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264), "Set output subtype");
            CheckHr(outputType->SetUINT32(MF_MT_AVG_BITRATE, m_Settings.BitRate), "Set output bit rate");
            CheckHr(MFSetAttributeSize(outputType.Get(), MF_MT_FRAME_SIZE, m_Width, m_Height),
                    "Set output frame size");
            CheckHr(MFSetAttributeRatio(outputType.Get(), MF_MT_FRAME_RATE, m_Settings.FrameRate, 1),
                    "Set output frame rate");
            CheckHr(MFSetAttributeRatio(outputType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1),
                    "Set output pixel aspect ratio");
            CheckHr(outputType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive),
                    "Set output interlace mode");
            outputType->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Main);
            CheckHr(m_Transform->SetOutputType(m_OutputStreamId, outputType.Get(), 0),
                    "Set H.264 output type");

            ComPtr<IMFMediaType> inputType;
            CheckHr(MFCreateMediaType(&inputType), "Create NV12 input type");
            CheckHr(inputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video), "Set input major type");
            CheckHr(inputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12), "Set input subtype");
            CheckHr(MFSetAttributeSize(inputType.Get(), MF_MT_FRAME_SIZE, m_Width, m_Height),
                    "Set input frame size");
            CheckHr(MFSetAttributeRatio(inputType.Get(), MF_MT_FRAME_RATE, m_Settings.FrameRate, 1),
                    "Set input frame rate");
            CheckHr(MFSetAttributeRatio(inputType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1),
                    "Set input pixel aspect ratio");
            CheckHr(inputType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive),
                    "Set input interlace mode");
            CheckHr(m_Transform->SetInputType(m_InputStreamId, inputType.Get(), 0),
                    "Set NV12 input type");

            ComPtr<IMFMediaType> currentOutput;
            if (SUCCEEDED(m_Transform->GetOutputCurrentType(m_OutputStreamId, &currentOutput)))
            {
                UINT32 headerSize = 0;
                if (SUCCEEDED(currentOutput->GetBlobSize(MF_MT_MPEG_SEQUENCE_HEADER, &headerSize)) &&
                    headerSize != 0)
                {
                    std::vector<std::uint8_t> header(headerSize);
                    UINT32 written = 0;
                    if (SUCCEEDED(currentOutput->GetBlob(
                            MF_MT_MPEG_SEQUENCE_HEADER, header.data(), headerSize, &written)))
                    {
                        m_CodecConfig = AvccConfigToAnnexB(header.data(), written);
                    }
                }
            }

            CheckHr(m_Transform->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0),
                    "Begin encoder streaming");
            CheckHr(m_Transform->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0),
                    "Start encoder stream");
            if (m_IsAsync)
            {
                std::vector<EncodedAccessUnit> ignored;
                while (m_NeedInputCount == 0)
                {
                    ProcessOneEvent(false, ignored);
                }
            }
        }

        EncodedAccessUnit ReadOutput()
        {
            MFT_OUTPUT_STREAM_INFO streamInfo = {};
            CheckHr(m_Transform->GetOutputStreamInfo(m_OutputStreamId, &streamInfo),
                    "Get encoder output stream info");

            ComPtr<IMFSample> allocatedSample;
            if ((streamInfo.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES) == 0)
            {
                ComPtr<IMFMediaBuffer> outputBuffer;
                CheckHr(MFCreateSample(&allocatedSample), "Create encoder output sample");
                const DWORD bufferSize = std::max<DWORD>(streamInfo.cbSize, 2u * 1024u * 1024u);
                CheckHr(MFCreateMemoryBuffer(bufferSize, &outputBuffer), "Create encoder output buffer");
                CheckHr(allocatedSample->AddBuffer(outputBuffer.Get()), "Add encoder output buffer");
            }

            MFT_OUTPUT_DATA_BUFFER output = {};
            output.dwStreamID = m_OutputStreamId;
            output.pSample = allocatedSample.Get();
            DWORD status = 0;
            const HRESULT result = m_Transform->ProcessOutput(0, 1, &output, &status);
            if (output.pEvents != nullptr)
            {
                output.pEvents->Release();
            }
            CheckHr(result, "Encoder ProcessOutput");

            IMFSample* sample = output.pSample;
            if (sample == nullptr)
            {
                throw HResultError("Encoder returned an empty output sample", E_UNEXPECTED);
            }

            ComPtr<IMFMediaBuffer> contiguous;
            CheckHr(sample->ConvertToContiguousBuffer(&contiguous), "Flatten encoded access unit");
            BYTE* bytes = nullptr;
            DWORD length = 0;
            CheckHr(contiguous->Lock(&bytes, nullptr, &length), "Lock encoded access unit");
            std::vector<std::uint8_t> encoded(bytes, bytes + length);
            contiguous->Unlock();

            LONGLONG sampleTime = 0;
            sample->GetSampleTime(&sampleTime);
            UINT32 cleanPoint = FALSE;
            sample->GetUINT32(MFSampleExtension_CleanPoint, &cleanPoint);

            if (output.pSample != nullptr && output.pSample != allocatedSample.Get())
            {
                output.pSample->Release();
            }
            return {AvccAccessUnitToAnnexB(encoded),
                    static_cast<std::uint64_t>(std::max<LONGLONG>(0, sampleTime) / 10),
                    cleanPoint != FALSE};
        }

        bool ProcessOneEvent(bool noWait, std::vector<EncodedAccessUnit>& output)
        {
            ComPtr<IMFMediaEvent> event;
            const HRESULT result = m_EventGenerator->GetEvent(
                noWait ? MF_EVENT_FLAG_NO_WAIT : 0, &event);
            if (noWait && result == MF_E_NO_EVENTS_AVAILABLE)
            {
                return false;
            }
            CheckHr(result, "Get encoder event");

            MediaEventType type = MEUnknown;
            CheckHr(event->GetType(&type), "Get encoder event type");
            HRESULT eventStatus = S_OK;
            CheckHr(event->GetStatus(&eventStatus), "Get encoder event status");
            CheckHr(eventStatus, "Encoder event failure");
            if (type == METransformNeedInput)
            {
                ++m_NeedInputCount;
            }
            else if (type == METransformHaveOutput)
            {
                output.push_back(ReadOutput());
            }
            else if (type == MEError)
            {
                throw HResultError("Encoder MEError", eventStatus);
            }
            return true;
        }

        void DrainSynchronous(std::vector<EncodedAccessUnit>& output)
        {
            while (true)
            {
                try
                {
                    output.push_back(ReadOutput());
                }
                catch (const HResultError& error)
                {
                    if (error.Result == MF_E_TRANSFORM_NEED_MORE_INPUT)
                    {
                        return;
                    }
                    throw;
                }
            }
        }

        UINT m_Width = 0;
        UINT m_Height = 0;
        DWORD m_InputStreamId = 0;
        SessionSettings m_Settings;
        DWORD m_OutputStreamId = 0;
        bool m_IsAsync = false;
        bool m_IsHardware = false;
        bool m_UsesD3D11Input = false;
        long m_NeedInputCount = 0;
        UINT m_DeviceResetToken = 0;
        std::wstring m_Name;
        std::vector<std::uint8_t> m_CodecConfig;
        ComPtr<IMFTransform> m_Transform;
        ComPtr<IMFMediaEventGenerator> m_EventGenerator;
        ComPtr<IMFDXGIDeviceManager> m_DeviceManager;
    };
}

struct VideoStreamer::Impl
{
    mutable std::mutex StatsMutex;
    VideoStreamerStats Stats;

    template <typename Callback>
    void ChangeStats(Callback&& callback)
    {
        std::scoped_lock lock(StatsMutex);
        callback(Stats);
    }
};

VideoStreamer::VideoStreamer()
    : m_Impl(new Impl)
{
}

VideoStreamer::~VideoStreamer()
{
    delete m_Impl;
}

VideoStreamerStats VideoStreamer::GetStats() const
{
    std::scoped_lock lock(m_Impl->StatsMutex);
    return m_Impl->Stats;
}

void VideoStreamer::Run(const std::atomic_bool& stopRequested, const SessionSettings& settings)
{
    m_Impl->ChangeStats([](auto& stats) { stats = VideoStreamerStats{}; });
    const HRESULT comResult = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool uninitializeCom = SUCCEEDED(comResult);
    WSADATA winsock = {};
    const int winsockResult = WSAStartup(MAKEWORD(2, 2), &winsock);
    bool mediaFoundationStarted = false;

    try
    {
        CheckHr(comResult == RPC_E_CHANGED_MODE ? S_OK : comResult, "CoInitializeEx");
        if (winsockResult != 0)
        {
            throw HResultError("WSAStartup", HRESULT_FROM_WIN32(winsockResult));
        }
        CheckHr(MFStartup(MF_VERSION, MFSTARTUP_FULL), "MFStartup");
        mediaFoundationStarted = true;

        m_Impl->ChangeStats([](auto& stats) { stats.StatusText = L"Waiting for USB Tablet Display output"; });
        SelectedOutput selected;
        std::wstring candidates;
        for (int attempt = 0; attempt < 100 && !stopRequested; ++attempt)
        {
            candidates.clear();
            if (FindTabletOutput(selected, candidates))
            {
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        if (!selected.Output)
        {
            throw HResultError("No USB Tablet Display output was found", DXGI_ERROR_NOT_FOUND);
        }

        m_Impl->ChangeStats([&](auto& stats)
        {
            stats.DisplayFound = true;
            stats.StatusText = L"Opening " + std::wstring(selected.Description.DeviceName);
        });

        TouchInputServer touchInput(
            selected.Description.DesktopCoordinates,
            stopRequested,
            [this](bool connected, std::uint64_t injectedFrames, LONG error)
            {
                m_Impl->ChangeStats([&](auto& stats)
                {
                    stats.InputConnected = connected;
                    stats.InjectedTouchFrames = injectedFrames;
                    stats.LastError = error;
                });
            }, settings.TouchEnabled);

        DesktopCapture capture;
        capture.Initialize(selected, settings);
        m_Impl->ChangeStats([&](auto& stats)
        {
            stats.Width = capture.Width();
            stats.Height = capture.Height();
            stats.StatusText = L"Starting H.264 encoder";
        });

        H264Encoder encoder;
        encoder.Initialize(capture.Width(), capture.Height(), capture.Device(), settings);
        m_Impl->ChangeStats([&](auto& stats)
        {
            stats.HardwareEncoder = encoder.IsHardware();
            stats.ZeroCopyInput = encoder.UsesD3D11Input();
            stats.EncoderName = encoder.Name();
            stats.TargetFrameRate = settings.FrameRate;
            stats.TargetBitRate = settings.BitRate;
            stats.SettingsRevision = settings.Revision;
            stats.StatusText = L"Waiting for Android receiver";
        });

        TcpTransport transport;
        ComPtr<ID3D11Texture2D> nv12;
        bool configSent = false;
        const auto startTime = std::chrono::steady_clock::now();
        auto nextConnectAttempt = startTime;
        HighResolutionFramePacer framePacer(settings.FrameRate);

        while (!stopRequested)
        {
            const auto now = std::chrono::steady_clock::now();
            if (!transport.IsConnected() && now >= nextConnectAttempt)
            {
                const bool connected = transport.Connect();
                configSent = false;
                nextConnectAttempt = now + std::chrono::seconds(1);
                m_Impl->ChangeStats([&](auto& stats)
                {
                    stats.Connected = connected;
                    stats.StatusText = connected ? L"Streaming to Android" : L"Waiting for Android receiver";
                });
            }

            const auto captureStart = std::chrono::steady_clock::now();
            const HRESULT captureResult = capture.AcquireNv12(nv12);
            const auto captureEnd = std::chrono::steady_clock::now();
            m_Impl->ChangeStats([&](auto& stats)
            {
                stats.LastCaptureTimeUs = static_cast<std::uint64_t>(
                    std::chrono::duration_cast<std::chrono::microseconds>(
                        captureEnd - captureStart).count());
            });

            if (captureResult == DXGI_ERROR_WAIT_TIMEOUT)
            {
                continue;
            }
            if (captureResult == DXGI_ERROR_ACCESS_LOST)
            {
                m_Impl->ChangeStats([](auto& stats)
                {
                    stats.StatusText = L"Display changed; rebuilding capture session";
                    stats.LastError = DXGI_ERROR_ACCESS_LOST;
                });

                HRESULT recreateResult = DXGI_ERROR_ACCESS_LOST;
                for (int attempt = 0; attempt < 40 && !stopRequested; ++attempt)
                {
                    std::this_thread::sleep_for(std::chrono::milliseconds(250));
                    SelectedOutput refreshed;
                    std::wstring refreshedCandidates;
                    if (!FindTabletOutput(refreshed, refreshedCandidates))
                    {
                        continue;
                    }
                    recreateResult = capture.RecreateDuplication(refreshed);
                    if (SUCCEEDED(recreateResult))
                    {
                        selected = std::move(refreshed);
                        configSent = false;
                        framePacer.Reset();
                        m_Impl->ChangeStats([](auto& stats)
                        {
                            stats.StatusText = L"Capture session recovered";
                            stats.LastError = ERROR_SUCCESS;
                        });
                        break;
                    }
                }
                if (FAILED(recreateResult))
                {
                    CheckHr(recreateResult, "Recreate desktop duplication");
                }
                continue;
            }
            CheckHr(captureResult, "Acquire desktop frame");
            m_Impl->ChangeStats([](auto& stats) { ++stats.CapturedFrames; });

            // Desktop Duplication usually follows the output refresh rate, but
            // it can briefly return queued updates faster than 60 Hz. Use a
            // high-resolution waitable timer to cap those bursts without the
            // ~31 ms oversleep caused by std::sleep_until on this machine.
            framePacer.Wait();
            const auto encodeTime = std::chrono::steady_clock::now();
            const auto presentationTimeUs = static_cast<std::uint64_t>(
                std::chrono::duration_cast<std::chrono::microseconds>(encodeTime - startTime).count());
            const auto encodeStart = std::chrono::steady_clock::now();
            auto accessUnits = encoder.Encode(nv12.Get(), presentationTimeUs);
            const auto encodeEnd = std::chrono::steady_clock::now();
            m_Impl->ChangeStats([&](auto& stats)
            {
                stats.LastEncodeTimeUs = static_cast<std::uint64_t>(
                    std::chrono::duration_cast<std::chrono::microseconds>(
                        encodeEnd - encodeStart).count());
            });
            for (auto& accessUnit : accessUnits)
            {
                m_Impl->ChangeStats([](auto& stats) { ++stats.EncodedFrames; });
                if (!transport.IsConnected())
                {
                    continue;
                }
                if (!configSent && !encoder.CodecConfig().empty())
                {
                    if (!transport.SendPacket(capture.Width(), capture.Height(), FlagCodecConfig,
                                              accessUnit.PresentationTimeUs, encoder.CodecConfig()))
                    {
                        m_Impl->ChangeStats([](auto& stats)
                        {
                            stats.Connected = false;
                            stats.StatusText = L"Android disconnected; reconnecting";
                        });
                        continue;
                    }
                    configSent = true;
                }

                const std::uint32_t flags = accessUnit.KeyFrame ? FlagKeyFrame : 0;
                if (!transport.SendPacket(capture.Width(), capture.Height(), flags,
                                          accessUnit.PresentationTimeUs, accessUnit.Bytes))
                {
                    m_Impl->ChangeStats([](auto& stats)
                    {
                        stats.Connected = false;
                        stats.StatusText = L"Android disconnected; reconnecting";
                    });
                    continue;
                }
                m_Impl->ChangeStats([&](auto& stats)
                {
                    stats.SentBytes += accessUnit.Bytes.size();
                });
            }
        }
    }
    catch (const HResultError& error)
    {
        m_Impl->ChangeStats([&](auto& stats)
        {
            stats.LastError = error.Result;
            std::wstringstream text;
            text << L"Video pipeline failed at " << error.what() << L" (0x"
                 << std::hex << static_cast<unsigned long>(error.Result) << L")";
            stats.StatusText = text.str();
        });
    }
    catch (const std::exception& error)
    {
        m_Impl->ChangeStats([&](auto& stats)
        {
            stats.LastError = E_FAIL;
            stats.StatusText = L"Video pipeline failed: " +
                               std::wstring(error.what(), error.what() + std::strlen(error.what()));
        });
    }

    if (mediaFoundationStarted)
    {
        MFShutdown();
    }
    if (winsockResult == 0)
    {
        WSACleanup();
    }
    if (uninitializeCom)
    {
        CoUninitialize();
    }
}
