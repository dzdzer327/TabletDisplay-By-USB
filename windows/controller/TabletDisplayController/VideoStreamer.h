#pragma once

#include <atomic>
#include <cstdint>
#include <string>
#include "SessionSettings.h"

struct VideoStreamerStats
{
    bool DisplayFound = false;
    bool Connected = false;
    bool InputConnected = false;
    bool HardwareEncoder = false;
    bool ZeroCopyInput = false;
    unsigned Width = 0;
    unsigned Height = 0;
    unsigned TargetFrameRate = 0;
    unsigned TargetBitRate = 0;
    std::uint64_t SettingsRevision = 0;
    std::uint64_t CapturedFrames = 0;
    std::uint64_t EncodedFrames = 0;
    std::uint64_t SentBytes = 0;
    std::uint64_t InjectedTouchFrames = 0;
    std::uint64_t LastCaptureTimeUs = 0;
    std::uint64_t LastEncodeTimeUs = 0;
    long LastError = 0;
    std::wstring EncoderName;
    std::wstring StatusText = L"Waiting to start";
};

class VideoStreamer
{
public:
    VideoStreamer();
    ~VideoStreamer();

    VideoStreamer(const VideoStreamer&) = delete;
    VideoStreamer& operator=(const VideoStreamer&) = delete;

    void Run(const std::atomic_bool& stopRequested, const SessionSettings& settings);
    VideoStreamerStats GetStats() const;

private:
    struct Impl;
    Impl* m_Impl;
};
