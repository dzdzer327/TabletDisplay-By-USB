#pragma once
#include <cstdint>
#include <string>

struct SessionSettings
{
    unsigned Width = 1920;
    unsigned Height = 1200;
    unsigned RefreshRate = 60;
    unsigned FrameRate = 60;
    unsigned BitRate = 8'000'000;
    bool TouchEnabled = true;
    std::uint64_t Revision = 0;
    bool Valid = true;
    std::wstring Error;
};

struct TabletDisplayMode
{
    unsigned Width = 0;
    unsigned Height = 0;
    unsigned RefreshRate = 0;
};

SessionSettings LoadSessionSettings(const std::wstring& path);
bool IsTabletDisplayName(const wchar_t* gdiName);
long ApplyTabletDisplaySettings(const SessionSettings& settings);
TabletDisplayMode GetTabletDisplayMode();
