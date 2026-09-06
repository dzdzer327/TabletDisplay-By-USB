#pragma once

#include <atomic>
#include <cstdint>
#include <string>

struct VideoStreamerStats
{
    bool DisplayFound = false;
    bool Connected = false;
    bool HardwareEncoder = false;
    unsigned Width = 0;
    unsigned Height = 0;
    std::uint64_t CapturedFrames = 0;
    std::uint64_t EncodedFrames = 0;
    std::uint64_t SentBytes = 0;
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

    void Run(const std::atomic_bool& stopRequested);
    VideoStreamerStats GetStats() const;

private:
    struct Impl;
    Impl* m_Impl;
};
