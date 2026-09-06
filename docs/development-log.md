# 开发日志

## 2026-08-07：阶段一构建基线

- 完成 Windows SDK `10.0.26100.6901` 与 WDK `10.0.26100.6584` 的专用目录安装：`D:\DevTools\WindowsKits`。
- 完成 Visual Studio Community 2022 的 C++ 工具链安装：`D:\Visual Studio\Community`。
- 从 Microsoft `Windows-driver-samples` 仓库稀疏检出 `video/IndirectDisplay`，作为不可直接修改的上游验证样例。
- Visual Studio 当前通道未提供可用的 WDK VSIX 项目模板，标准样例直接构建会找不到 `WindowsUserModeDriver10.0` 工具集。
- 新增 `windows/driver/LocalWdkToolset.props`：在项目级加载 SDK/WDK 的 UMDF 2.25、IddCx 1.6 头文件和库，不改动全局安装路径。
- 新增 `windows/driver/Build-IddSample.ps1`：生成 WPP 追踪头文件后，以 MSBuild、`v143` 工具集和本地 WDK 适配层构建上游样例。
- 已验证 `Debug|x64` 构建成功，输出：
  - `IddSampleDriver.dll`
  - `IddSampleApp.exe`

已知构建警告：上游样例的静态分析告警与 `ntstatus.h` 宏重定义警告仍存在；样例并未报错。后续 Tablet Display 自有驱动将逐项消除可控告警。

## 2026-08-07：Tablet Display 驱动骨架

- 从上游样例复制最小 UMDF/IddCx 驱动工程至 `windows/driver/TabletDisplayDriver/`，独立于上游对照样例。
- 使用产品标识 `Tablet Display`、`Tablet Display Project` 与硬件 ID `Root\TabletDisplayDriver`。
- 改为只声明一台 EDID-less 虚拟显示器；Windows 由驱动提供模式，而不是引用示例显示器的 EDID。
- 已报告并限制为 1280×720、1920×1080、1920×1200、2560×1600 的 60Hz 模式；默认首选为 1920×1200。
- 新增 `windows/driver/Build-TabletDisplayDriver.ps1`，可在当前未提供 WDK VSIX 的 Visual Studio 2022 环境中生成追踪文件并构建驱动。
- 已验证 `Debug|x64` 构建成功，输出：
  - `windows/driver/TabletDisplayDriver/x64/Debug/TabletDisplayDriver.dll`
  - `windows/driver/TabletDisplayDriver/x64/Debug/TabletDisplayDriver.pdb`

已知构建警告：Windows Kit 的 `ntstatus.h` 宏重定义，以及源自 Microsoft 示例的三项静态分析警告；没有编译或链接错误。

## 2026-08-17 至 2026-08-20：手写代码与驱动打包

- 将示例常量 `IDD_SAMPLE_MONITOR_COUNT` 重命名为项目语义明确的 `TABLET_DISPLAY_MAX_MONITOR_COUNT`，并保持最多一台虚拟显示器。
- 将显示器输出类型从示例的 HDMI 改为 `DISPLAYCONFIG_OUTPUT_TECHNOLOGY_OTHER`，表达“画面经 USB 数据通道传输，不是实体 HDMI 接口”。
- 为 `CoCreateGuid`、`AvSetMmThreadCharacteristicsW` 返回的句柄和 `IddCxMonitorArrival` 增加结果检查，消除三项来自自有代码路径的静态分析警告。
- 多次验证 `Debug|x64` 编译成功，生成 `TabletDisplayDriver.dll`；目前剩余输出主要为 Windows Kit 头文件的 `ntstatus.h` 宏重定义提示。
- 在 INF 中设置开发版本 `DriverVer=08/17/2026,0.1.0.0`。
- 建立 `windows/driver/package/Debug-x64/`，将驱动安装需要的 INF 与 DLL 从源码/构建目录中分离。
- 首次运行 `Inf2Cat` 时发现官方示例遗留的 `NT$ARCH$` 只会由完整 WDK 项目打包流程展开；当前手动流程不会替换该占位符，因此目录生成失败。
- 将 INF 模型节改为 `NTamd64.10.0`，明确面向 Windows 10/11 x64，而不是将最低系统限制为 Windows 11 build 22000。
- 新增 `windows/driver/Build-DriverPackage.ps1`，统一完成驱动编译、INF/DLL 同步和 CAT 生成，避免手动复制旧文件。
- 已执行完整打包流程，`Inf2Cat` 报告零错误、零警告，并生成 `TabletDisplayDriver.cat`。
- 创建当前用户范围的 `Tablet Display Test Certificate` 开发代码签名证书；私钥不可导出，公钥证书保存在 `windows/driver/certificates/`。
- 新增并执行 `Sign-DriverPackage.ps1`，SignTool 报告 CAT 签名成功，零错误、零警告。
- 新增 `TabletDisplayController` 软件设备控制程序，硬件 ID 与 INF 中的 `TabletDisplayDriver` 匹配；已验证 `Debug|x64` 编译成功并生成 `TabletDisplayController.exe`。
- 新增 `Enable-TestSigning.ps1` 和 `Install-TestDriver.ps1`，分别用于显式开启测试签名和将测试证书/驱动包加入系统。两者均要求管理员权限，当前尚未执行。
- 新增 `Uninstall-TestDriver.ps1` 和 `Disable-TestSigning.ps1`，确保后续系统测试有明确、可重复的驱动/证书/启动配置回滚路径。
- 已静态解析检查 11 个 PowerShell 脚本，未发现语法错误；驱动三件套和控制程序产物均存在。
- CAT 的签名者已核对为 `CN=Tablet Display Test Certificate`。在证书尚未导入系统信任区时，PowerShell 显示 `UnknownError` 属于预期状态；安装脚本会先加入本机 Root 与 TrustedPublisher 后再预置驱动。
- 当前 Codex/PowerShell 会话不是管理员会话，且无法读取 Secure Boot 状态；因此尚未改变启动配置、系统信任区或驱动仓库。
- 首次执行本机证书信任脚本时，脚本误把 PowerShell `EnhancedKeyUsageList.ObjectId` 当作 .NET `Oid` 对象读取，导致对有效代码签名 EKU 的误判；证书原始 `2.5.29.37` 扩展已确认包含代码签名 OID `1.3.6.1.5.5.7.3.3`，脚本已改为直接解析 X.509 EKU 扩展。
- 已将 `Tablet Display Test Certificate` 导入本机 `LocalMachine\Root` 与 `LocalMachine\TrustedPublisher`；证书 SHA-1 指纹为 `F3835FDA74526B100140C53AA84C123DAB2F9E5E`，有效期至 2029-08-20。
- 已执行 `Verify-DriverPackage.ps1`：CAT Authenticode 签名为 `Valid`，INF 与 DLL 均通过指定 CAT 的成员哈希校验。三次 SignTool 验证均为 1 个文件成功、0 警告、0 错误。
- 当前开发签名未使用时间戳，因此仅适合本机开发；证书到期后需要重新生成证书、CAT 和签名。
- 本次安全与完整性验证没有安装驱动，也没有修改 Secure Boot、测试签名或其他启动配置。
- 首次本机可信安装将包成功加入驱动仓库为 `oem38.inf`，Windows 接受本地 Authenticode 签名并将 DLL 复制到 UMDF 目录；创建软件设备时在 `WUDFCoinstaller` 阶段失败，SetupAPI 返回错误 87（参数不正确）。
- 根因是自定义 WDK 构建桥没有执行标准 StampInf 替换，导致 INF 中保留了 `$UMDFVERSION$` 占位符。已按项目目标将其明确设为 `UmdfLibraryVersion=2.25.0`，并将驱动版本升至 `0.1.0.1`。
- `Install-LocalTrustedDriver.ps1` 改为只预置驱动包，不再对尚未创建的软件设备使用 PnPUtil `/install`；设备匹配和加载由控制程序创建 SWD 设备时完成。
- 将修复后的 `0.1.0.1` 包加入驱动仓库为 `oem39.inf`；旧设备最初仍绑定 `oem38.inf / 0.1.0.0`，因此仅重新启动控制程序不足以切换驱动。
- 对现有 `SWD\\TabletDisplayDriver\\TabletDisplayDriver` 设备应用新版包并重启设备后，驱动状态变为 `Started`，当前安装驱动为 `oem39.inf / 0.1.0.1`。
- Windows 已枚举出 `DISPLAY\\DEFAULT_MONITOR` 虚拟 Monitor；桌面拓扑出现第二块活动屏幕 `\\\\.\\DISPLAY26`，当前分辨率为 `1920×1200`，位于主屏右侧。
- 本次成功加载全程保持 Secure Boot 和 Windows 测试签名启动选项不变。该 UMDF 间接显示驱动在本机依靠已加入 Root 与 TrustedPublisher 的开发证书完成信任与完整性校验。
- `Install-LocalTrustedDriver.ps1` 重新加入 PnPUtil `/install`：没有匹配设备时仍只预置包；已有 Tablet Display 设备时会自动应用更高版本，避免再次停留在旧 INF。
- 新增 `windows/shared/TabletDisplayFrameStats.h`，定义驱动与控制器共用的本机帧统计结构；它只承载诊断数据，不承载画面像素。
- 驱动交换链处理线程现在记录运行状态、帧尺寸、累计帧数、首末帧时间及错误码；控制器创建受限的全局共享内存并每秒显示分辨率、FPS 和累计帧数。
- 驱动版本升至 `0.1.0.2`，重新生成 CAT、签名并验证通过，安装为 `oem40.inf`；设备状态为 `Started`，第二屏重新出现为 `\\\\.\\DISPLAY27`。
- 取帧探针首先在静态桌面累计收到 49 帧；静止时系统不重复提交未变化画面，符合间接显示交换链的按需更新行为。
- 在第二屏运行 5 秒颜色动画后，连续 6 个采样窗口分别收到 39、37、39、40、39、40 帧，始终报告 `1920×1200`、运行状态 1、错误码 0。由此确认 `Windows 扩展桌面 → IddCx 交换链 → 驱动取帧线程` 数据路径已经打通。该约 40fps 数值受测试动画的 PowerShell UI 定时器影响，不代表驱动刷新率上限。

## 2026-08-21：Android SDK、ADB 与构建环境

- 以解压方式安装 Microsoft OpenJDK `17.0.20.1` 至 `D:\DevTools\Java`，不与 Windows SDK/WDK 目录混放。
- 安装 Google Android Command-line Tools 至 `D:\DevTools\Android\Sdk`；初始 ZIP 的 SHA-256 与 Android 官网公布的 `90ae805d...01fb04a` 一致。
- 安装并验证 Platform Tools/ADB `37.0.1`、Android Platform 35/36、Build Tools 35.0.1/36.0.0。
- 在当前用户环境中设置 `JAVA_HOME`、`ANDROID_HOME`、`ANDROID_SDK_ROOT`，并将 Java、ADB 和 Android CLI 加入用户 `Path`。
- 通过官方 Android CLI 模板创建 `android/TabletDisplayApp`，应用 ID 为 `com.example.tabletdisplay`，最低 API 29（Android 10），编译/目标 API 36，使用 AGP 9.0.1、Gradle 9.1 和 Kotlin 2.3.20。
- 因本机网络无法访问 Gradle 官方地址跳转的 GitHub，首次 Gradle 分发包从华为镜像下载，并使用 Wrapper 内置的官方 SHA-256 `a17ddd85...86c806` 严格验证；项目中的 Wrapper 地址仍保留 Gradle 官方地址。
- 首次执行 `assembleDebug` 成功，36 个任务全部完成；生成约 30 MB 的 `app-debug.apk`，AAPT 验证应用名为 `Tablet Display`、`minSdkVersion=29`、`targetSdkVersion=36`。
- Android CLI 原地从 Command-line Tools 22 更新到 23 时一度受 Windows 自身文件占用影响；更新包已由 SDK 管理器完成下载和校验，随后通过备份切换方式安装为 23.0，并再次构建 APK 成功。构建仍会输出一条 SDK XML 版本兼容提示，但不影响 36 个任务完成或 APK 生成。
- 新增 `android/Check-AndroidEnvironment.ps1` 和 `android/Build-TabletDisplayApp.ps1`，用于一键检查环境和构建 APK。
- 华为 DBR-W10 平板已通过 ADB 授权，系统为 Android 12 / API 31；Debug APK 已成功覆盖安装并由 ADB 启动。
- 将模板 `Hello Android` 首页替换为全屏黑色 `SurfaceView`，保持屏幕常亮并隐藏系统栏；未收到视频时显示“等待电脑画面”和开发端口。
- 新增 `H264StreamReceiver`：只在 Android 回环地址 `127.0.0.1:27183` 监听，解析带宽高、时间戳和标志位的定长包头，将 H.264 配置/访问单元送入硬件 `MediaCodec` 并直接渲染至 Surface。
- 新增 `docs/android-video-protocol.md`，固定开发期 v1 的 32 字节大端序包头、8 MiB 负载限制以及配置、关键帧、流结束标志。
- 已建立并核对 ADB `tcp:27183 → tcp:27183` 转发；Android 应用进程正常、无崩溃日志，设备截图确认显示“等待电脑画面”。
- 用户已在平板实机确认当前界面显示“等待电脑画面 / ADB 视频端口：27183”，Android 客户端部署与等待连接状态通过验收。
- 新增 `android/Deploy-TabletDisplayApp.ps1`，统一完成 Debug 构建、ADB 覆盖安装、端口转发和应用启动。

## 2026-09-06：Windows 到 Android 的视频闭环

- 在 `TabletDisplayController` 中新增 `VideoStreamer`，把视频处理放在 Windows 用户态控制器中，驱动仍专注于创建和维护间接显示器。
- 控制器使用 DXGI Desktop Duplication 自动选择非主屏的间接显示输出并取得 `B8G8R8A8` 桌面纹理。
- 使用 D3D11 Video Processor 将桌面纹理转换为 NV12，再交给 Media Foundation H.264 编码器；优先枚举硬件异步 MFT，找不到硬件编码器时回退到系统同步编码器。
- 实现 Media Foundation 异步 MFT 的 `METransformNeedInput` / `METransformHaveOutput` 事件处理，配置 8 Mbps、60 fps、无 B 帧、60 帧 GOP 和低延迟模式。
- 将编码结果规范化为 H.264 Annex B 访问单元，并按 `TDSP v1` 32 字节大端序包头经 `127.0.0.1:27183` TCP 发送；断线后每秒自动尝试重连。
- 新增 `Start-TabletDisplayPrototype.ps1`，统一完成设备选择、ADB 端口转发、Android 应用启动和管理员控制器启动。
- 控制器新增持久运行日志 `TabletDisplayController.runtime.log`，记录驱动帧数、抓帧/编码/发送计数、帧率、编码器名称与错误码。
- Android 端新增解码器组件与累计渲染帧日志，便于通过 Logcat 诊断真机硬解码状态。
- 在华为 DBR-W10（Android 12）真机完成闭环：Windows 枚举第二屏 `DISPLAY25`，分辨率 `1920×1200`；Windows 选择 `NVIDIA H.264 Encoder MFT` 硬件编码器；TCP/ADB 已连续发送数十 MiB，Windows 端错误码为 0。
- 真机截图确认 Android 已显示 Windows 第二屏桌面；Android Logcat 确认使用 `OMX.qcom.video.decoder.avc`，SurfaceView 收到并渲染首帧。
- 动态窗口测试期间，抓帧与编码计数持续增长，证明 `虚拟扩展桌面 → DXGI 抓帧 → D3D11 NV12 → NVIDIA H.264 → TCP/ADB → Android MediaCodec → SurfaceView` 数据链路已打通。
- 当前原型在 D3D11 NV12 转换后仍经过一次 GPU 到系统内存的读回，再送入硬件编码器；功能闭环已完成，但零拷贝和 1080p60 性能优化仍属于下一阶段。

## 下一步

1. 在 Windows 显示设置中验证四种分辨率、横竖屏和扩展桌面排列。
2. 增加触控、鼠标和键盘输入回传。
3. 增加显示旋转处理、断连/模式变更后的全链路自动恢复。
4. 测量端到端延迟、CPU/GPU 占用与长时间稳定性，并把 NV12 纹理到编码器的系统内存中转改为 D3D11 零拷贝。
