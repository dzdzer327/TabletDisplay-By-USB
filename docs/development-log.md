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
- 新增独立触控回传端口 `27184`：Android 将最多 10 个触点的按下、移动、抬起与取消事件发送至 `adb reverse` 通道，Windows 根据第二屏桌面矩形映射坐标并通过 `InjectTouchInput` 注入原生触控。
- 输入监听器只绑定电脑回环地址；断连时会取消尚未抬起的活动触点。控制器日志新增输入连接状态和累计注入触控帧数。
- 修复触控注入失败后的状态一致性：只有 `InjectTouchInput` 成功时才提交活动触点集合，并忽略连接恢复后缺失“按下”事件的孤立移动/抬起事件。
- 增加独立鼠标光标通道：Windows 从 Desktop Duplication 帧元数据读取副屏光标可见性和位置，经 TDSP `0x8` 状态包发送；Android 在视频 Surface 上方绘制高对比度鼠标箭头，解决硬件光标未包含在桌面纹理中而导致“鼠标进入副屏后看不见”的问题。
- Windows 控制器注册三个全局应急快捷键：`Ctrl+Alt+Right` 将当前窗口移动到 Tablet Display，`Ctrl+Alt+Left` 将当前窗口移回主屏，`Ctrl+Alt+Home` 把鼠标送回主屏中央。
- 真机重启测试发现虚拟显示拓扑刚建立时 Desktop Duplication 可能返回 `DXGI_ERROR_ACCESS_LOST (0x887A0026)`；控制器现会重新枚举 Tablet Display 并重建 Duplication 会话，不再让视频线程永久退出。
- 后续真机观察确认该 IDD/DXGI 路径已经能在视频中显示 Windows 系统鼠标；Android 独立叠加会造成双光标，因此已移除叠加箭头并保留原生鼠标。
- 参考用户提供的电子屏幕意象重新设计 Android 启动器图标：两块青色叠放屏幕表示扩展显示，USB-C 线表示有线连接；生成透明自适应前景及 mdpi～xxxhdpi 兼容图标。
- 动态基线测试以约 58～62 次/秒移动副屏窗口：IDD 驱动约 54fps，但旧视频链路的抓取与编码均只有约 32.3fps。
- 将 D3D11 Video Processor 生成的 NV12 纹理通过 `MFCreateDXGISurfaceBuffer` 直接包装为 Media Foundation 输入样本，并用 `IMFDXGIDeviceManager` 向 NVIDIA H.264 MFT 提供同一 D3D11 设备；删除 staging texture、`Map`、逐行 CPU 复制和内存输入缓冲。
- 控制器运行日志新增 `zeroCopy`、`captureUs` 与 `encodeUs`。真机确认 `hardware=1 zeroCopy=1`，活跃帧 GPU 捕获/转换通常低于 1ms，NVIDIA 编码提交通常约 0.1～0.3ms。
- 进一步定位原 32fps 上限来自 Windows 默认计时粒度下的 `std::sleep_until(16.67ms)` 实际睡眠约 31ms。改用高精度 Waitable Timer，仅用于抑制超过 60fps 的短时积压，不再重复限制 Desktop Duplication 的刷新节奏。
- 最终同条件 6 秒动态测试：桌面源更新 59.2 次/秒，Windows 抓取和编码平均 57.4fps，逐秒达到 60fps；Android 硬解码约 53～57fps。相对旧链路 32.3fps 提升约 78%，全程错误码为 0，触控连接正常。
- Windows 控制器 Debug/Release 均重新编译成功；Android `testDebugUnitTest` 与 `assembleDebug` 通过。

## 下一步

1. 在 Windows 显示设置中验证四种分辨率、横竖屏和扩展桌面排列。
2. 增加软键盘与物理键盘输入回传，并完善触控模式切换与系统鼠标光标形状同步。
3. 增加显示旋转处理、断连/模式变更后的全链路自动恢复。
4. 测量端到端延迟、CPU/GPU 占用与长时间稳定性，并进一步验证纹理池和实验性 120fps 路径。

## 2026-09-06：产品化双端应用需求基线

- 新增 `docs/product-requirements-and-ui-spec.md`，将当前“控制台 + ADB 脚本 + Android 全屏页”原型与产品化目标明确区分。
- 定义 Windows 桌面应用、后台服务、托盘、驱动以及 Android 连接、显示、输入模块的职责边界。
- 给出 Windows 首页、显示、画质与性能、输入、设备、诊断、设置页面，以及 Android 连接首页和全屏快捷控制层的布局草图。
- 建立带编号的 Windows、连接、视频、输入和诊断需求清单，以及配置同步、异常状态、安装升级、安全隐私和首版验收标准。
- 将首个 UI 迭代限定为：保留 ADB 传输后端，但让普通开发测试不再依赖 PowerShell 手动启动；后续再独立替换产品化 USB 通道。

## 2026-09-09：Windows 与 Android 双端 UI 第一版

- 新增基于 WPF/.NET Framework 4.8.1 的 `TabletDisplayDesktop.exe`，无需额外安装 .NET SDK；提供 Debug/Release 构建脚本和双击可运行产物。
- Windows 主窗口完成首页、显示、画质与性能、输入、设备、诊断、设置、关于八个导航页面，并统一青蓝色品牌视觉、状态卡片、指标卡片和屏幕布局示意。
- Windows 首页接入现有开发原型：可检测真实 USB 平板、启动 ADB 连接脚本、打开系统显示设置、将鼠标送回主屏，并读取控制器日志展示分辨率、FPS、码率、编码器、GPU 耗时和零拷贝状态。
- Windows 诊断页实际检查控制器、虚拟显示设备、USB/ADB、视频和触控通道，支持复制诊断摘要和打开日志目录。
- C++ 控制器新增带普通用户写权限的 `Global\\TabletDisplayControllerStop` 事件，使非管理员桌面 UI 能请求控制器安全停止视频线程、移除软件显示设备并退出。
- 修复多 ADB 设备选择：桌面端排除 `emulator-*` 和 `IP:端口` 形式的模拟器/网络设备，仅自动选择真实 USB 序列号；当前确认正确设备为 `<device-serial> / HUAWEI DBR-W10`。
- Android 改为完整应用外壳：连接首页、全屏显示页、右侧快捷控制层、设置页和连接诊断页，保留原有 `SurfaceView + MediaCodec` 解码和原生触控链路。
- Android 快捷控制层包含触控、旋转锁定、性能浮层、画质偏好、软键盘入口、全部设置、连接诊断与断开；面板支持小高度横屏滚动，并向内避开系统边缘手势区。
- Android 设置中的保持屏幕常亮和旋转锁定已接入真实系统行为；触控开关立即控制事件发送。触控板鼠标语义、软键盘文本回传和 Windows 参数动态应用仍等待下一阶段的控制协议。
- Windows Desktop Debug/Release 均以 0 警告、0 错误编译成功；Android Debug APK 构建成功，等待页和快捷控制层已完成模拟器截图检查。

## 2026-09-09：实验性 120 Hz 与静默控制器

- 间接显示驱动版本升至 `0.2.0.0`，四组分辨率均增加 120 Hz 模式并保留 60 Hz 回退；新包完成 Inf2Cat、测试签名和 CAT/INF/DLL 完整性验证，安装后当前软件设备确认绑定 `oem39.inf / 0.2.0.0`。
- Windows 视频链路目标由 60 fps / 8 Mbps 提升为实验性 120 fps / 16 Mbps，继续使用 D3D11 NV12 纹理、NVIDIA H.264 MFT 与零拷贝输入。
- 桌面应用启动连接后会等待 Tablet Display 枚举完成，并通过 Windows 显示 API 将当前虚拟屏自动切换到 120 Hz；Windows 实测当前模式为 `1920×1200@120 Hz`。
- Android 显示页默认请求最接近 120 Hz 的物理屏幕模式，并在 Android 11+ 的视频 Surface 上声明固定 120 fps 内容；设置页新增“优先使用 120 Hz”开关。
- 开发启动脚本使用隐藏窗口运行管理员控制器，不再保留展开的命令行窗口；UAC 在当前软件设备架构下仍需确认一次，后续产品化 Windows 服务可消除每次连接的 UAC。
- 修复普通权限桌面端无法停止高权限控制器：命名事件使用中完整性标签，桌面端仅申请实际需要的 `Modify` 权限。普通进程已成功发出停止信号，控制器和虚拟显示器正常退出。
- 在副屏运行持续高速动画验证实际吞吐：`1920×1200@120 Hz` 下多次记录 119–120 fps，最高采样 122 fps（统计窗口误差）；`hardware=1`、`zeroCopy=1`、错误码 `0x0`，NVIDIA 编码提交通常约 0.17–0.29 ms。
- Windows 控制器、Windows Desktop Debug/Release 及 Android `assembleDebug + testDebugUnitTest` 全部构建通过；最新版 APK 已覆盖安装到真实设备 `<device-serial> / HUAWEI DBR-W10`。

## 2026-09-14：避免日常连接重复安装 Android 应用

- 修复 `Start-TabletDisplayPrototype.ps1` 每次连接都无条件执行 `adb install -r` 的问题。
- 启动脚本现在先通过 Android 包管理器检查 `com.example.tabletdisplay`：已安装时只建立 ADB 端口并启动应用；未安装时才自动部署 APK。
- 新增 `-ForceAndroidInstall` 参数用于开发期显式覆盖安装；也可继续使用独立的 `android\Deploy-TabletDisplayApp.ps1` 更新应用。
- 日常连接不再要求本地必须保留 APK 构建产物；只有首次安装或强制更新时才检查 APK 文件。

## 2026-10-08：产品更名为 USB Tablet Display

- 产品对外名称由 `Tablet Display` 调整为 `USB Tablet Display`，中文说明统一为“USB 平板扩展屏”，直接强调有线 USB 使用方式。
- Windows 桌面应用、Android 应用、虚拟显示器友好名称、诊断文本、驱动资源描述和产品文档均使用新名称。
- 对外发布版本保持为 `0.2.0`；内部硬件 ID、进程名、协议名和 Android 包名保持不变，避免破坏现有安装与升级路径。
- Windows 桌面端同时识别旧显示器名 `Tablet Display` 和新名称 `USB Tablet Display`，允许旧驱动平滑过渡。

## 2026-10-08：生成 v0.2.0 GitHub 体验包

- 新增 `packaging/Build-ReleasePackages.ps1`，统一构建 Windows Release 桌面端、控制器、Release 驱动包和 Android APK，并输出用户指定的 Windows ZIP 与 Android APK。
- 桌面端和控制器启动脚本支持便携目录，不再要求运行于源码仓库；ADB 会依次从包内工具目录、Android SDK 环境变量、用户默认 SDK、开发机兼容路径和 `PATH` 查找。
- Windows 包新增 ADB 下载、驱动安装、首次配置和完整卸载脚本。配置脚本可以创建桌面快捷方式，控制器继续隐藏运行。
- Windows 包内说明补全六项内容：安装说明、环境要求、首次连接、常见故障、卸载与恢复、已知限制；明确说明当前仍为 ADB 与自签名驱动的开发预览版。
- Android `versionCode` 升至 2、`versionName` 统一为 `0.2.0`；桌面端、控制器、Android 与驱动对外版本统一为 v0.2.0。
- 新增 `packaging/Test-ReleasePackages.ps1`。验证结果：下载文件 SHA-256 通过、ZIP 内 16 个文件清单通过、脚本语法通过、便携桌面应用启动通过、APK 包名/版本/应用名/minSdk/targetSdk 元数据通过。

## 2026-10-08：发布包真实平板短时测试

- 从 Windows ZIP 独立解压目录运行，发布 APK 成功安装到真实 HUAWEI DBR-W10；包内 ADB 下载脚本执行通过。
- 成功建立 1920×1200 扩展副屏；平板截图确认 Windows 桌面画面，日志确认 NVIDIA H.264、硬件编码、零拷贝与零错误。
- Android 模拟点击成功回传，Windows 注入计数为 2；普通权限停止事件成功关闭控制器并移除软件显示设备，再次连接不重复安装 APK。
- 发现三个待处理问题：Visual C++ x64 运行库未在安装流程中处理；既有 0.2.1 驱动优先于发布包 0.2.0；首次副屏枚举超时后需手动重启控制器。
- 本次实际绑定既有 0.2.1 驱动，未完成包内 Release 驱动加载、干净机器兼容性、持续 120fps 或 8 小时稳定性验收。详细证据与限制见 `docs/release-test-report-v0.2.0.md`。

## 2026-10-15：Windows 统一安装器 0.2.2

- 新增带图形界面的统一安装器，使用 Windows 自带 C# 编译器构建，可选择目录、显示安装进度，提供静默安装和 Windows 应用卸载入口。
- 内置 ADB、.NET Framework 4.8.1 与 Visual C++ x64 离线依赖，构建和安装时验证 Microsoft 运行库签名；普通用户无需安装开发工具。
- 桌面、Android 与驱动版本统一到 0.2.2，驱动新版本优先于此前安装的 0.2.1。更新时保留旧驱动，发现更高版本时明确停止，避免“安装成功但仍使用高版本旧驱动”的误判。
- 新增安装记录与资源归属跟踪，卸载只清理安装器新增的驱动/证书信任，保留原有驱动、原有证书信任、共享运行库与诊断日志。
- 控制器新增不创建屏幕的依赖探针；安装版控制器日志移到 ProgramData 的日志目录，普通用户桌面端可以读取。
- 本机完成 9 项安装、启动、重复安装和卸载恢复检查，均通过。此次测试移除临时安装目录和新增 oem49.inf，原来的 oem39.inf/0.2.1.0 恢复，源代码与旧开发产物保留。
- 附带 `Test-CleanWindows.ps1`，自动区分开发机与干净机并生成 JSON 报告。当前无干净 Windows/虚拟机可访问，干净机验收未执行；详见 `docs/windows-installer-validation.md`。

## 2026-10-16：其他电脑试用教程与测试包

- 新增 `docs/other-pc-quickstart.md`，说明完整解压、统一安装、平板授权、扩展显示、基础触控、故障日志、自动验收和卸载步骤。
- 新增 `packaging/Build-TestKit.ps1`，将既有 0.2.2 安装 EXE、APK、验收脚本和中文 TXT 教程合为 `TabletDisplay-TestKit-v0.2.2.zip`，方便通过 U 盘携带。
- 提供可双击的 `Test-Windows.cmd` 与重启后继续的 `Resume-Test.cmd`；仍要求管理员授权，不修改系统级执行策略。
- 区分手动体验与自动首次安装验收，避免先手动安装后运行脚本导致“已有安装”的误解；明确自动验收不能替代真实 USB 画面测试。

## 2026-10-16：启动时自动安装/更新平板应用 0.2.3

- Windows“启动扩展屏”先检查目标 USB 平板的 applicationId 与 versionCode，未安装时自动安装，旧版本更新，同版本跳过，更高版本保留。
- 新增可独立验证的 Android 同步模块；安装前检查包内 APK 的 SHA-256，成功后重新查询平板版本确认生效。更新使用 `adb install -r`，不自动卸载应用或使用降级参数。
- 签名冲突、设备离线、安装被拒绝及安装确认超时分别处理；桌面端对签名冲突和 USB 安装确认显示可读中文提示，初次安装/更新结果显示在状态文本中。
- ADB 子进程并发读取输出并设置时间上限；桌面进程也修复先阻塞读取输出导致超时无效的问题，为平板确认预留等待时间。
- 包内新增 `android-app.json` 与同步脚本；Windows、Android、驱动和安装器更新为 0.2.3，Android versionCode=4；同步更新携带教程。
- 自动化回归覆盖 15 项：首次安装、旧版升级、同版跳过、新版不降级、强制修复、签名冲突、设备拒绝/离线、未知版本、文件完整性、安装后校验、真实 ADB 输出捕获与进程超时。设备安装场景使用模拟响应；当前没有连接真实平板，实际安装/升级链路仍需实机复测。

## 2026-10-16：修复设置未生效 0.2.4

- 根因：WPF 的分辨率、帧率和码率等控件仍为 UI 预览，没有事件把选值传给控制器；编码器固定使用 120fps / 16 Mbps。Android 的高刷新率开关仅请求平板本机屏幕模式，不是电脑视频设置。
- 新增用户级 `settings.ini`，桌面端原子保存，原生控制器严格校验并按版本号监听。正式接入四种分辨率、60/120 Hz 显示模式、30/60/120fps 编码上限、2～50 Mbps 码率、画质预设及原生触控/仅显示开关。
- 连接中点击“应用设置”会停止并重建视频/触控链路，保留控制器进程和虚拟显示设备；Windows 模式拒绝或编码失败不会虚报成功。显示与编码版本号均确认后才报告设置生效；诊断状态区分实际副屏模式、编码目标与当前编码帧率。
- Android 保存实际已支持的偏好设置，刷新率请求在 Surface 已创建后也可更新，重连时重置帧率采样。性能浮层区分解码 FPS 与平板实际 Hz，并列出可用物理刷新率。平板画质、触控板、软键盘等尚未接入的选项，以及 Windows 未接入的预览控件已禁用并提示限制。
- `Test-DesktopSettings.ps1` 通过 8 项真实 WPF 控件事件检查，不保存用户配置、不启动副屏。
- `Test-SessionSettings.ps1 -Live` 通过 12 项持久化、原生解析、实际显示模式与编码器目标检查：1080p60/30fps/6Mbps → 1920×1200@120Hz/120fps/16Mbps → 720p60/60fps/8Mbps；同一控制器内切换成功，非法配置拒绝后可恢复。证据位于 `dist/settings-tests/853e1b13bee5434c9c05954e33a4d7b1/result.json`。
- 本机实时测试使用已有 `oem39.inf / 0.2.1.0` 驱动；新包驱动为 0.2.4.0。没有连接真实 Android 设备，实时测试仅确认 Windows 模式与 NVIDIA 编码器初始化/目标，不代表实际传输或平板显示达到 120fps。
- Windows、Android 和统一安装器版本统一为 0.2.4，Android versionCode=5。未修改启动安全配置，未提交 Git；本轮不宣称完成干净电脑、真机全链路或长时间稳定性验收。
- 最终构建与包检查通过：Windows 桌面端 0 警告/0 错误、控制器和驱动 Release、Android APK、驱动 CAT/INF/DLL 签名与完整性、ZIP 18 项文件清单、打包脚本语法、独立解压桌面启动及 APK 元数据。15 项 Android 安装同步回归通过；Android JVM 单元测试 2 项通过。
- Android JVM 测试首次启动失败源于开发机 PATH 中现有的多余双引号使 Java 参数被拆开；仅在本次测试子进程清理引号并关闭配置缓存后通过，未修改用户或系统 PATH。

## 2026-10-29：v0.2.5 缺陷修复与真机回归

- 根据发布前测试修复输入连接空闲断开检测，设置变更后不再丢失首个点按；增加 EOF/本地停止两个 JVM 回归用例。
- Android 视频改为等比居中、黑边无输入，触控归一化坐标相对有效视频区域；横向源在竖向平板上不再拉伸。
- 卸载保留可重试入口和归属记录到文件清理成功，锁定载荷后失败/解锁后重试两个隔离回归通过。
- 统一安装器构建同步刷新体验 ZIP，并逐字节核验安装器、APK 与验收脚本一致；版本更新为 0.2.5 / Android versionCode=6。
- 调整高帧率测试源后，Windows 编码短时采样达到 118～120fps。此前约 64fps 的图案受 WinForms 消息定时器调度影响，不应推断为编码器上限；本轮仍不宣称端到端呈现持续 120fps。
- 4 项 JVM、8 项 WPF 设置、15 项 Android 安装同步回归、发布包与签名完整性检查通过；真实设备回归验证首击、拖拽、仅显示、黑边输入隔离、30fps 实时切换和应用重启重连。
- 真机回归与测试边界详见 `docs/fixes-and-verification-v0.2.5.md`。未修改启动安全策略、未替用户选择签名身份或 LICENSE、未上传 GitHub。
