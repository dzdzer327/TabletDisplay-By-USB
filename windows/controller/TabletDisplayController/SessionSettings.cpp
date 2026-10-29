#include "SessionSettings.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <charconv>
#include <sstream>
#include <string>

namespace
{
    bool FindTablet(DISPLAY_DEVICEW& result)
    {
        for (DWORD index = 0;; ++index)
        {
            DISPLAY_DEVICEW device = {};
            device.cb = sizeof(device);
            if (!EnumDisplayDevicesW(nullptr, index, &device, 0)) return false;
            if (_wcsicmp(device.DeviceString, L"USB Tablet Display") == 0 ||
                _wcsicmp(device.DeviceString, L"Tablet Display") == 0)
            {
                result = device;
                return true;
            }
        }
    }
}

SessionSettings LoadSessionSettings(const std::wstring& path)
{
    SessionSettings settings;
    if (path.empty()) return settings;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        if (GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND)
        {
            settings.Valid = false;
            settings.Error = L"Cannot read session settings";
        }
        return settings;
    }
    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 || size.QuadPart > 8192)
    {
        CloseHandle(file);
        settings.Valid = false;
        settings.Error = L"Session settings file is too large";
        return settings;
    }
    std::string text(static_cast<std::size_t>(size.QuadPart), '\0');
    DWORD read = 0;
    const bool complete = ReadFile(file, text.data(), static_cast<DWORD>(text.size()), &read, nullptr) && read == text.size();
    CloseHandle(file);
    if (!complete)
    {
        settings.Valid = false;
        settings.Error = L"Could not read complete session settings";
        return settings;
    }
    std::istringstream lines(text);
    std::string line;
    while (std::getline(lines, line))
    {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        const auto separator = line.find('=');
        if (separator == std::string::npos) continue;
        const auto key = line.substr(0, separator);
        if (key != "Width" && key != "Height" && key != "RefreshRate" && key != "FrameRate" &&
            key != "BitRate" && key != "TouchEnabled" && key != "Revision") continue;
        const auto value = line.substr(separator + 1);
        std::uint64_t number = 0;
        const auto conversion = std::from_chars(value.data(), value.data() + value.size(), number);
        if (conversion.ec != std::errc() || conversion.ptr != value.data() + value.size() ||
            (key != "Revision" && number > 50'000'000))
        {
            settings.Valid = false;
            settings.Error = L"Invalid numeric session setting";
            return settings;
        }
        if (key == "Width") settings.Width = static_cast<unsigned>(number);
        if (key == "Height") settings.Height = static_cast<unsigned>(number);
        if (key == "RefreshRate") settings.RefreshRate = static_cast<unsigned>(number);
        if (key == "FrameRate") settings.FrameRate = static_cast<unsigned>(number);
        if (key == "BitRate") settings.BitRate = static_cast<unsigned>(number);
        if (key == "TouchEnabled")
        {
            if (number > 1) { settings.Valid = false; settings.Error = L"Invalid touch setting"; return settings; }
            settings.TouchEnabled = number != 0;
        }
        if (key == "Revision") settings.Revision = number;
    }
    const bool mode = (settings.Width == 1280 && settings.Height == 720) ||
        (settings.Width == 1920 && settings.Height == 1080) ||
        (settings.Width == 1920 && settings.Height == 1200) ||
        (settings.Width == 2560 && settings.Height == 1600);
    if (!mode || (settings.RefreshRate != 60 && settings.RefreshRate != 120) ||
        (settings.FrameRate != 30 && settings.FrameRate != 60 && settings.FrameRate != 120) ||
        settings.FrameRate > settings.RefreshRate || settings.BitRate < 2'000'000 || settings.BitRate > 50'000'000)
    {
        settings.Valid = false;
        settings.Error = L"Unsupported resolution, refresh rate, frame rate or bitrate";
    }
    return settings;
}

bool IsTabletDisplayName(const wchar_t* gdiName)
{
    DISPLAY_DEVICEW device = {};
    return FindTablet(device) && _wcsicmp(device.DeviceName, gdiName) == 0;
}

TabletDisplayMode GetTabletDisplayMode()
{
    DISPLAY_DEVICEW device = {};
    DEVMODEW current = {};
    current.dmSize = sizeof(current);
    if (FindTablet(device) && EnumDisplaySettingsW(device.DeviceName, ENUM_CURRENT_SETTINGS, &current))
        return {current.dmPelsWidth, current.dmPelsHeight, current.dmDisplayFrequency};
    return {};
}

long ApplyTabletDisplaySettings(const SessionSettings& settings)
{
    if (!settings.Valid) return DISP_CHANGE_BADPARAM;
    DISPLAY_DEVICEW device = {};
    if (!FindTablet(device)) return DISP_CHANGE_FAILED;
    DEVMODEW mode = {};
    mode.dmSize = sizeof(mode);
    if (!EnumDisplaySettingsW(device.DeviceName, ENUM_CURRENT_SETTINGS, &mode) &&
        !EnumDisplaySettingsW(device.DeviceName, ENUM_REGISTRY_SETTINGS, &mode)) return DISP_CHANGE_FAILED;
    const bool rotated = mode.dmDisplayOrientation == DMDO_90 || mode.dmDisplayOrientation == DMDO_270;
    mode.dmPelsWidth = rotated ? settings.Height : settings.Width;
    mode.dmPelsHeight = rotated ? settings.Width : settings.Height;
    mode.dmDisplayFrequency = settings.RefreshRate;
    mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
    const auto before = GetTabletDisplayMode();
    if ((device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) != 0 &&
        before.Width == mode.dmPelsWidth && before.Height == mode.dmPelsHeight &&
        before.RefreshRate == settings.RefreshRate) return DISP_CHANGE_SUCCESSFUL;
    if ((device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) == 0)
    {
        mode.dmPosition.x = GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN);
        mode.dmPosition.y = GetSystemMetrics(SM_YVIRTUALSCREEN);
        mode.dmFields |= DM_POSITION;
    }
    const LONG test = ChangeDisplaySettingsExW(device.DeviceName, &mode, nullptr, CDS_TEST, nullptr);
    if (test != DISP_CHANGE_SUCCESSFUL) return test;
    const LONG applied = ChangeDisplaySettingsExW(device.DeviceName, &mode, nullptr, CDS_UPDATEREGISTRY, nullptr);
    if (applied != DISP_CHANGE_SUCCESSFUL) return applied;
    const auto actual = GetTabletDisplayMode();
    return actual.Width == mode.dmPelsWidth && actual.Height == mode.dmPelsHeight &&
        actual.RefreshRate == settings.RefreshRate ? DISP_CHANGE_SUCCESSFUL : DISP_CHANGE_FAILED;
}
