#pragma once

#include <Windows.h>

namespace TabletDisplay
{
    constexpr wchar_t FrameStatsMappingName[] = L"Global\\TabletDisplayFrameStats";
    constexpr ULONG FrameStatsVersion = 1;

    struct alignas(8) FrameStats
    {
        ULONG Version;
        volatile LONG State;
        volatile LONG Width;
        volatile LONG Height;
        volatile LONG64 FrameCount;
        volatile LONG64 FirstFrameQpc;
        volatile LONG64 LastFrameQpc;
        volatile LONG LastError;
    };
}
