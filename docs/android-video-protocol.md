# Android 视频流协议（开发期 v1）

Android 客户端只在设备回环地址 `127.0.0.1:27183` 监听 TCP。开发期由 ADB 建立电脑到平板的端口转发：

```powershell
adb forward tcp:27183 tcp:27183
```

Windows 发送端连接电脑本机 `127.0.0.1:27183`，连接会由 ADB 转发至平板。该设计不会让 Android 应用监听 Wi-Fi 或公共网络接口。

TCP 流由一系列“大端序固定头部 + H.264 访问单元”组成。每个头部 32 字节：

| 偏移 | 类型 | 含义 |
|---:|---|---|
| 0 | `uint32` | Magic：`0x54445350`（`TDSP`） |
| 4 | `uint32` | 协议版本：`1` |
| 8 | `uint32` | 编码宽度 |
| 12 | `uint32` | 编码高度 |
| 16 | `uint32` | 标志位 |
| 20 | `uint32` | 紧随其后的负载字节数，最大 8 MiB |
| 24 | `uint64` | 显示时间戳，微秒 |

标志位：

- `0x1`：负载为 H.264 SPS/PPS 等解码配置，对应 `BUFFER_FLAG_CODEC_CONFIG`。
- `0x2`：负载包含 IDR/关键帧。
- `0x4`：流结束。

H.264 负载按一个完整访问单元一包发送，使用 Annex B 起始码。连接建立或编码参数变化后，Windows 必须先发送 SPS/PPS 配置，再发送 IDR 帧。Android 根据包内宽高创建或重建 `MediaCodec`，解码结果直接输出到全屏 `SurfaceView`。
