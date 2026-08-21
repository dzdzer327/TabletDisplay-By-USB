#include <conio.h>
#include <iostream>

#include <windows.h>
#include <sddl.h>
#include <swdevice.h>

#include "../../shared/TabletDisplayFrameStats.h"

#pragma comment(lib, "Advapi32.lib")

namespace
{
    constexpr wchar_t DeviceId[] = L"TabletDisplayDriver";

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
}

int wmain()
{
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
               << L"Press X to disconnect it and exit.\n";

    LONG64 previousFrameCount = 0;
    ULONGLONG previousTick = GetTickCount64();

    while (true)
    {
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

            std::wcout << L'\r'
                       << (state == 1 ? L"Receiving frames" : L"Waiting for frames")
                       << L" | " << width << L'x' << height
                       << L" | " << static_cast<int>(fps + 0.5) << L" fps"
                       << L" | total " << frameCount
                       << L" | error 0x" << std::hex << error << std::dec
                       << L"          " << std::flush;

            previousFrameCount = frameCount;
            previousTick = nowTick;
        }

        Sleep(50);
    }

    std::wcout << L'\n';
    SwDeviceClose(softwareDevice);
    UnmapViewOfFile(stats);
    CloseHandle(statsMapping);
    return 0;
}
