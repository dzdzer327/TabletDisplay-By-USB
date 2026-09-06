#include <conio.h>
#include <algorithm>
#include <atomic>
#include <fstream>
#include <iostream>
#include <thread>

#include <windows.h>
#include <sddl.h>
#include <swdevice.h>

#include "../../shared/TabletDisplayFrameStats.h"
#include "VideoStreamer.h"

#pragma comment(lib, "Advapi32.lib")

namespace
{
    constexpr wchar_t DeviceId[] = L"TabletDisplayDriver";
    constexpr int HotkeyMoveWindowToTablet = 1;
    constexpr int HotkeyMoveWindowToPrimary = 2;
    constexpr int HotkeyReturnCursorToPrimary = 3;

    struct DeviceCreationContext
    {
        HANDLE CompletionEvent = nullptr;
        HRESULT Result = E_PENDING;
    };

    void WINAPI DeviceCreationCallback(
        _In_ HSWDEVICE device,
        _In_ HRESULT creationResult,
        _In_opt_ void* context,
        _In_opt_ const wchar_t* deviceInstanceId)
    {
        UNREFERENCED_PARAMETER(device);
        UNREFERENCED_PARAMETER(deviceInstanceId);

        auto* creationContext = static_cast<DeviceCreationContext*>(context);
        creationContext->Result = creationResult;
        SetEvent(creationContext->CompletionEvent);
    }

    struct MonitorLookup
    {
        bool WantPrimary = false;
        bool Found = false;
        RECT WorkArea = {};
        RECT MonitorArea = {};
    };

    BOOL CALLBACK FindMonitorCallback(HMONITOR monitor, HDC, LPRECT, LPARAM context)
    {
        auto* lookup = reinterpret_cast<MonitorLookup*>(context);
        MONITORINFO info = {};
        info.cbSize = sizeof(info);
        if (!GetMonitorInfoW(monitor, &info))
        {
            return TRUE;
        }

        const bool isPrimary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
        if (isPrimary != lookup->WantPrimary)
        {
            return TRUE;
        }

        lookup->Found = true;
        lookup->WorkArea = info.rcWork;
        lookup->MonitorArea = info.rcMonitor;
        return FALSE;
    }

    bool FindMonitor(bool primary, MonitorLookup& result)
    {
        result = {};
        result.WantPrimary = primary;
        EnumDisplayMonitors(nullptr, nullptr, FindMonitorCallback, reinterpret_cast<LPARAM>(&result));
        return result.Found;
    }

    void ReturnCursorToPrimaryMonitor()
    {
        MonitorLookup monitor;
        if (!FindMonitor(true, monitor))
        {
            return;
        }

        const int x = monitor.MonitorArea.left +
                      (monitor.MonitorArea.right - monitor.MonitorArea.left) / 2;
        const int y = monitor.MonitorArea.top +
                      (monitor.MonitorArea.bottom - monitor.MonitorArea.top) / 2;
        SetCursorPos(x, y);
    }

    void MoveForegroundWindowToMonitor(bool primary)
    {
        const HWND window = GetForegroundWindow();
        MonitorLookup target;
        if (window == nullptr || !FindMonitor(primary, target))
        {
            MessageBeep(MB_ICONWARNING);
            return;
        }

        WINDOWPLACEMENT placement = {};
        placement.length = sizeof(placement);
        const bool wasMaximized = GetWindowPlacement(window, &placement) &&
                                  placement.showCmd == SW_SHOWMAXIMIZED;
        if (wasMaximized || IsIconic(window))
        {
            ShowWindow(window, SW_RESTORE);
        }

        RECT current = {};
        if (!GetWindowRect(window, &current))
        {
            return;
        }

        const int targetWidth = target.WorkArea.right - target.WorkArea.left;
        const int targetHeight = target.WorkArea.bottom - target.WorkArea.top;
        const int currentWidth = static_cast<int>(current.right - current.left);
        const int currentHeight = static_cast<int>(current.bottom - current.top);
        const int width = (std::min)(currentWidth, targetWidth);
        const int height = (std::min)(currentHeight, targetHeight);
        const int x = target.WorkArea.left + (targetWidth - width) / 2;
        const int y = target.WorkArea.top + (targetHeight - height) / 2;
        SetWindowPos(window, nullptr, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
        if (wasMaximized)
        {
            ShowWindow(window, SW_MAXIMIZE);
        }
        SetForegroundWindow(window);
    }
}

int wmain()
{
    wchar_t executablePath[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, executablePath, ARRAYSIZE(executablePath));
    std::wstring runtimeLogPath = executablePath;
    const auto lastSeparator = runtimeLogPath.find_last_of(L"\\/");
    runtimeLogPath.resize(lastSeparator == std::wstring::npos ? 0 : lastSeparator + 1);
    runtimeLogPath += L"TabletDisplayController.runtime.log";
    {
        std::wofstream log(runtimeLogPath, std::ios::trunc);
        log << L"Tablet Display controller starting\n";
    }

    PSECURITY_DESCRIPTOR securityDescriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;AU)",
            SDDL_REVISION_1,
            &securityDescriptor,
            nullptr))
    {
        std::wcerr << L"Could not create frame-statistics security descriptor. Win32 error: "
                   << GetLastError() << L'\n';
        return 1;
    }

    SECURITY_ATTRIBUTES securityAttributes = {};
    securityAttributes.nLength = sizeof(securityAttributes);
    securityAttributes.lpSecurityDescriptor = securityDescriptor;

    HANDLE statsMapping = CreateFileMappingW(
        INVALID_HANDLE_VALUE,
        &securityAttributes,
        PAGE_READWRITE,
        0,
        sizeof(TabletDisplay::FrameStats),
        TabletDisplay::FrameStatsMappingName);
    LocalFree(securityDescriptor);

    bool driverStatsAvailable = true;
    if (statsMapping == nullptr && GetLastError() == ERROR_ACCESS_DENIED)
    {
        // Creating a named object in the Global namespace requires an elevated
        // process. Video streaming itself does not, so keep a private mapping
        // and let the controller continue when launched normally.
        statsMapping = CreateFileMappingW(
            INVALID_HANDLE_VALUE,
            nullptr,
            PAGE_READWRITE,
            0,
            sizeof(TabletDisplay::FrameStats),
            nullptr);
        driverStatsAvailable = false;
    }

    if (statsMapping == nullptr)
    {
        std::wcerr << L"Could not create frame-statistics mapping. Win32 error: "
                   << GetLastError() << L'\n';
        return 1;
    }

    auto* stats = static_cast<TabletDisplay::FrameStats*>(MapViewOfFile(
        statsMapping,
        FILE_MAP_READ | FILE_MAP_WRITE,
        0,
        0,
        sizeof(TabletDisplay::FrameStats)));
    if (stats == nullptr)
    {
        std::wcerr << L"Could not open frame-statistics memory. Win32 error: "
                   << GetLastError() << L'\n';
        CloseHandle(statsMapping);
        return 1;
    }

    ZeroMemory(stats, sizeof(*stats));
    stats->Version = TabletDisplay::FrameStatsVersion;

    DeviceCreationContext creationContext;
    creationContext.CompletionEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (creationContext.CompletionEvent == nullptr)
    {
        std::wcerr << L"Could not create the device completion event. Win32 error: "
                   << GetLastError() << L'\n';
        UnmapViewOfFile(stats);
        CloseHandle(statsMapping);
        return 1;
    }

    const wchar_t hardwareIds[] = L"TabletDisplayDriver\0\0";
    const wchar_t compatibleIds[] = L"TabletDisplayDriver\0\0";

    SW_DEVICE_CREATE_INFO createInfo = {};
    createInfo.cbSize = sizeof(createInfo);
    createInfo.pszzHardwareIds = hardwareIds;
    createInfo.pszzCompatibleIds = compatibleIds;
    createInfo.pszInstanceId = DeviceId;
    createInfo.pszDeviceDescription = L"Tablet Display";
    createInfo.CapabilityFlags = SWDeviceCapabilitiesRemovable |
                                 SWDeviceCapabilitiesSilentInstall |
                                 SWDeviceCapabilitiesDriverRequired;

    HSWDEVICE softwareDevice = nullptr;
    const HRESULT startResult = SwDeviceCreate(
        DeviceId,
        L"HTREE\\ROOT\\0",
        &createInfo,
        0,
        nullptr,
        DeviceCreationCallback,
        &creationContext,
        &softwareDevice);

    if (FAILED(startResult))
    {
        std::wcerr << L"SwDeviceCreate could not start. HRESULT: 0x"
                   << std::hex << startResult << L'\n';
        CloseHandle(creationContext.CompletionEvent);
        UnmapViewOfFile(stats);
        CloseHandle(statsMapping);
        return 1;
    }

    const DWORD waitResult = WaitForSingleObject(creationContext.CompletionEvent, 10'000);
    CloseHandle(creationContext.CompletionEvent);

    if (waitResult != WAIT_OBJECT_0 || FAILED(creationContext.Result))
    {
        std::wcerr << L"Windows could not create Tablet Display. HRESULT: 0x"
                   << std::hex << creationContext.Result << L'\n';
        SwDeviceClose(softwareDevice);
        UnmapViewOfFile(stats);
        CloseHandle(statsMapping);
        return 1;
    }

    std::wcout << L"Tablet Display software device is active.\n"
               << L"Press X to disconnect it and exit.\n"
               << L"Ctrl+Alt+Right: move the active window to Tablet Display.\n"
               << L"Ctrl+Alt+Left: move the active window to the primary display.\n"
               << L"Ctrl+Alt+Home: return the mouse cursor to the primary display.\n";
    if (!driverStatsAvailable)
    {
        std::wcout << L"Driver frame counters require an elevated controller; video streaming remains enabled.\n";
    }

    std::atomic_bool stopStreamer = false;
    VideoStreamer streamer;
    std::thread streamerThread([&]() { streamer.Run(stopStreamer); });

    const UINT hotkeyModifiers = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
    const bool moveToTabletHotkey =
        RegisterHotKey(nullptr, HotkeyMoveWindowToTablet, hotkeyModifiers, VK_RIGHT) != FALSE;
    const bool moveToPrimaryHotkey =
        RegisterHotKey(nullptr, HotkeyMoveWindowToPrimary, hotkeyModifiers, VK_LEFT) != FALSE;
    const bool returnCursorHotkey =
        RegisterHotKey(nullptr, HotkeyReturnCursorToPrimary, hotkeyModifiers, VK_HOME) != FALSE;
    if (!moveToTabletHotkey || !moveToPrimaryHotkey || !returnCursorHotkey)
    {
        std::wcerr << L"One or more Tablet Display hotkeys could not be registered.\n";
    }

    LONG64 previousFrameCount = 0;
    std::uint64_t previousEncodedFrameCount = 0;
    ULONGLONG previousTick = GetTickCount64();

    while (true)
    {
        MSG message = {};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE))
        {
            if (message.message != WM_HOTKEY)
            {
                TranslateMessage(&message);
                DispatchMessageW(&message);
                continue;
            }

            switch (message.wParam)
            {
            case HotkeyMoveWindowToTablet:
                MoveForegroundWindowToMonitor(false);
                break;
            case HotkeyMoveWindowToPrimary:
                MoveForegroundWindowToMonitor(true);
                break;
            case HotkeyReturnCursorToPrimary:
                ReturnCursorToPrimaryMonitor();
                break;
            default:
                break;
            }
        }

        if (_kbhit())
        {
            const int key = _getch();
            if (key == 'x' || key == 'X')
            {
                break;
            }
        }

        const ULONGLONG nowTick = GetTickCount64();
        if (nowTick - previousTick >= 1000)
        {
            const LONG64 frameCount = InterlockedCompareExchange64(&stats->FrameCount, 0, 0);
            const double seconds = static_cast<double>(nowTick - previousTick) / 1000.0;
            const double fps = static_cast<double>(frameCount - previousFrameCount) / seconds;
            const LONG state = InterlockedCompareExchange(&stats->State, 0, 0);
            const LONG width = InterlockedCompareExchange(&stats->Width, 0, 0);
            const LONG height = InterlockedCompareExchange(&stats->Height, 0, 0);
            const LONG error = InterlockedCompareExchange(&stats->LastError, 0, 0);
            const auto streamStats = streamer.GetStats();
            const double streamFps =
                static_cast<double>(streamStats.EncodedFrames - previousEncodedFrameCount) / seconds;

            {
                std::wofstream log(runtimeLogPath, std::ios::app);
                log << L"driverFrames=" << frameCount
                    << L" driverSize=" << width << L'x' << height
                    << L" status=\"" << streamStats.StatusText << L"\""
                    << L" videoSize=" << streamStats.Width << L'x' << streamStats.Height
                    << L" captured=" << streamStats.CapturedFrames
                    << L" captureUs=" << streamStats.LastCaptureTimeUs
                    << L" videoFps=" << static_cast<int>(streamFps + 0.5)
                    << L" encoded=" << streamStats.EncodedFrames
                    << L" encodeUs=" << streamStats.LastEncodeTimeUs
                    << L" sentBytes=" << streamStats.SentBytes
                    << L" inputConnected=" << (streamStats.InputConnected ? 1 : 0)
                    << L" touchFrames=" << streamStats.InjectedTouchFrames
                    << L" hardware=" << (streamStats.HardwareEncoder ? 1 : 0)
                    << L" zeroCopy=" << (streamStats.ZeroCopyInput ? 1 : 0)
                    << L" encoder=\"" << streamStats.EncoderName << L"\""
                    << L" error=0x" << std::hex << streamStats.LastError << std::dec << L'\n';
            }

            std::wcout << L'\r'
                       << (state == 1 ? L"Receiving frames" : L"Waiting for frames")
                       << L" | " << width << L'x' << height
                       << L" | " << static_cast<int>(fps + 0.5) << L" fps"
                       << L" | total " << frameCount
                       << L" | error 0x" << std::hex << error << std::dec
                       << L"\nVideo: " << streamStats.StatusText
                       << L" | " << streamStats.Width << L'x' << streamStats.Height
                       << L" | captured " << streamStats.CapturedFrames
                       << L" (" << static_cast<int>(streamFps + 0.5) << L" fps)"
                       << L" | encoded " << streamStats.EncodedFrames
                       << L" | sent " << (streamStats.SentBytes / 1024) << L" KiB"
                       << L" | touch " << (streamStats.InputConnected ? L"connected" : L"waiting")
                       << L"/" << streamStats.InjectedTouchFrames
                       << L" | " << (streamStats.HardwareEncoder ? L"hardware" : L"software")
                       << L"/" << (streamStats.ZeroCopyInput ? L"D3D11" : L"memory")
                       << L" " << streamStats.EncoderName
                       << L"          \n" << std::flush;

            previousFrameCount = frameCount;
            previousEncodedFrameCount = streamStats.EncodedFrames;
            previousTick = nowTick;
        }

        Sleep(50);
    }

    std::wcout << L'\n';
    if (moveToTabletHotkey)
    {
        UnregisterHotKey(nullptr, HotkeyMoveWindowToTablet);
    }
    if (moveToPrimaryHotkey)
    {
        UnregisterHotKey(nullptr, HotkeyMoveWindowToPrimary);
    }
    if (returnCursorHotkey)
    {
        UnregisterHotKey(nullptr, HotkeyReturnCursorToPrimary);
    }
    stopStreamer = true;
    if (streamerThread.joinable())
    {
        streamerThread.join();
    }
    SwDeviceClose(softwareDevice);
    UnmapViewOfFile(stats);
    CloseHandle(statsMapping);
    return 0;
}
