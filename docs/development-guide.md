# 开发、构建与项目结构

通过 USB 数据线将 Android 平板变成 Windows 10/11 扩展显示器。

当前原型已打通 Windows 虚拟扩展屏、DXGI 抓屏、D3D11 零拷贝硬件 H.264 编码、ADB/USB 传输、Android `MediaCodec` 硬解显示及原生触控回传。Windows 已提供可双击运行的桌面设置应用；Android 已提供连接、全屏快捷控制、设置与诊断界面。开发连接仍使用 ADB；软键盘内容回传和产品化 USB 通道尚未完成。

## 当前结构

- `windows/driver/TabletDisplayDriver/`：本项目的独立 Windows 间接显示驱动工程。
- `windows/desktop/TabletDisplayDesktop/`：Windows 桌面设置应用（WPF/.NET Framework 4.8.1）。
- `windows/driver/upstream/`：Microsoft IddSample 上游验证样例，只用于参考和回归对照。
- `android/TabletDisplayApp/`：Android 10+ 平板客户端工程。
- `android/*.ps1`：Android 环境检查与 APK 构建入口。
- `docs/`：阶段验收条件、调试和测试记录。
- `需求分析/`：原始需求说明。

产品化桌面端、平板端、设置与诊断界面的完整规格见 [产品需求与双端界面规格](product-requirements-and-ui-spec.md)。

## 开发机要求

当前开发机已验证以下环境可用：

1. Visual Studio 2022（C++ 桌面开发工作负载）。
2. Windows SDK 10.0.26100。
3. WDK 10.0.26100.6584。
4. Microsoft OpenJDK 17。
5. Android SDK Platform 36、Build Tools 36.0.0 与 Platform Tools/ADB 37.0.1。

由于当前 Visual Studio 实例没有提供 WDK VSIX 项目模板，本仓库通过 `windows/driver/LocalWdkToolset.props` 在项目级显式引用 UMDF 与 IddCx 构建依赖；不修改 Visual Studio 或 Windows Kits 安装目录。

不要在日常主力机上启用测试签名或加载未签名驱动。

## 构建驱动

在已安装 WDK 的测试机上，以 PowerShell 执行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\driver\Get-IddSample.ps1
```

以 PowerShell 运行以下命令即可生成 WPP 追踪头文件并构建项目的 `Debug|x64` 驱动：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\driver\Build-TabletDisplayDriver.ps1
```

构建产物位于 `windows/driver/TabletDisplayDriver/x64/Debug/TabletDisplayDriver.dll`。首期支持一台名为 **USB Tablet Display** 的虚拟显示器，并为 1280×720、1920×1080、1920×1200、2560×1600 提供 60Hz 兼容模式和实验性 120Hz 模式。

在测试机上部署前，仍需准备测试签名并安装驱动；这会改变 Windows 的安全启动/驱动加载状态，因此不会自动执行。

## 生成开发驱动包

以下命令会重新编译驱动、同步 INF/DLL，并生成未签名 CAT：

```powershell
.\windows\driver\Build-DriverPackage.ps1
```

开发测试证书和 CAT 签名分别通过以下脚本生成：

```powershell
.\windows\driver\New-TestSigningCertificate.ps1
.\windows\driver\Sign-DriverPackage.ps1
```

已验证的签名包位于 `windows/driver/package/Debug-x64/`。测试证书私钥只保存在当前 Windows 用户的个人证书库，不导出到仓库；`windows/driver/certificates/` 仅保存可以公开分发的 `.cer` 公钥证书。

`Enable-TestSigning.ps1` 与 `Install-TestDriver.ps1` 会改变 Windows 启动配置和系统证书/驱动仓库，只应在明确同意后的管理员 PowerShell 中运行。

测试结束后的回滚入口为 `Uninstall-TestDriver.ps1` 和 `Disable-TestSigning.ps1`：先退出控制程序并卸载测试驱动，再关闭测试签名，最后重启 Windows。

只进行本机证书信任和驱动包完整性验证（不安装驱动、不修改启动配置）时，先以管理员身份运行 `Trust-LocalTestCertificate.ps1`，再运行 `Verify-DriverPackage.ps1`。验证会检查 CAT 的 Authenticode 签名，并确认 INF 与 DLL 都是该 CAT 中未被篡改的成员。

本机信任验证通过后，可在保持 Secure Boot 和正常启动配置不变的情况下，以管理员身份运行 `Install-LocalTrustedDriver.ps1`。该脚本先重复完整性验证，再通过 PnPUtil 将驱动包加入 Windows 驱动仓库；它不会创建显示设备，设备由 `TabletDisplayController.exe` 单独控制。

开发中需要替换已经预置的 USB Tablet Display 包时，使用管理员权限运行 `Update-LocalTrustedDriver.ps1`。它只查找内部 Provider 为 `Tablet Display Project` 的旧包，先卸载这些包再调用本机可信安装脚本，不处理其他显示驱动。

## 构建虚拟设备控制程序

```powershell
.\windows\controller\Build-TabletDisplayController.ps1
```

输出为 `windows/controller/TabletDisplayController/x64/Debug/TabletDisplayController.exe`。驱动成功安装后，桌面应用会隐藏启动该控制器并创建 USB Tablet Display 软件设备；在桌面应用中点击“停止扩展屏”会安全移除设备。直接从终端运行控制器时仍可按 `X` 退出。

## 构建和启动 Windows 桌面应用

桌面端不依赖额外安装 `.NET SDK`，使用本机 Visual Studio 2022 与 Windows 自带的 .NET Framework 4.8.1 构建：

```powershell
.\windows\desktop\Build-TabletDisplayDesktop.ps1
.\windows\desktop\Start-TabletDisplayDesktop.ps1 -SkipBuild
```

输出为 `windows/desktop/TabletDisplayDesktop/bin/Debug/TabletDisplayDesktop.exe`。应用提供首页、显示、画质与性能、输入、设备、诊断、设置和关于页面；可自动排除模拟器及网络 ADB，选择真实 USB 平板，并从界面启动或安全停止当前开发原型。

连接并授权平板后，可从仓库根目录启动整个开发原型：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\controller\Start-TabletDisplayPrototype.ps1
```

启动扩展屏时会检查平板应用版本：未安装时自动安装，低于电脑包内 APK 的版本时自动更新，同版本复用，更高版本不降级。版本信息和 APK SHA-256 由构建时生成的 `android-app.json` 提供，不要求用户安装 AAPT 或 Android SDK。签名冲突时保留旧应用和数据；部分机型需要在平板确认 USB 安装。更新来源为电脑安装包内置的 APK。

开发中需要覆盖安装新 APK 时，可运行 `android\Deploy-TabletDisplayApp.ps1`，或为启动脚本增加 `-ForceAndroidInstall`；启动脚本即使强制修复也不会降级更高版本。

允许弹出的管理员提示后，Windows 会出现第二块扩展屏。应用通常仍在主屏或上次关闭的位置打开，可先选中应用窗口再使用：

- `Ctrl+Alt+Right`：把当前窗口移到 USB Tablet Display。
- `Ctrl+Alt+Left`：把当前窗口移回主屏。
- `Ctrl+Alt+Home`：把看不见的鼠标光标送回主屏中央。

平板直接显示视频流中的 Windows 系统鼠标；触摸平板则通过独立回传通道注入 Windows Touch。

详细的成功判定、回滚和记录格式见 [阶段一清单](phase-1-idd-validation.md)。

## 检查 Android 环境

重新打开 VS Code 或 PowerShell 后，在仓库根目录运行：

```powershell
.\android\Check-AndroidEnvironment.ps1
```

脚本会验证 JDK、Android SDK、ADB、编译平台，并列出当前通过 USB 连接的 Android 设备。当前客户端最低支持 API 29（Android 10），编译和目标 API 为 36。

## 构建 Android 客户端

```powershell
.\android\Build-TabletDisplayApp.ps1
```

Debug APK 输出到 `android/TabletDisplayApp/app/build/outputs/apk/debug/app-debug.apk`。Gradle 缓存、`local.properties`、构建目录和 APK 已由 Android 工程的 `.gitignore` 排除，不应提交到 Git。

连接并授权一台 Android 平板后，可一键构建、覆盖安装、建立 ADB 视频及触控端口映射并启动应用：

```powershell
.\android\Deploy-TabletDisplayApp.ps1
```

Android 应用会全屏显示并在设备回环地址 `127.0.0.1:27183` 等待 H.264 视频流。等待页右侧把手可打开快捷控制层，并可进入设置、连接诊断或返回连接首页。开发协议见 [Android 视频流协议](android-video-protocol.md)。

## 生成 GitHub 体验包

普通用户现在可以使用统一安装版：`TabletDisplay-Windows-x64-v0.2.5-Setup.exe`。双击后选择目录并安装，安装器会离线配置 .NET Framework 4.8.1、Visual C++ x64 运行库、ADB 与项目驱动，创建桌面和开始菜单快捷方式，并注册 Windows 应用卸载入口。平板允许 USB 调试后，电脑在启动扩展屏时自动安装或更新配套 APK。

构建统一安装器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\Build-WindowsInstaller.ps1
```

输出位于 `dist/TabletDisplay-Windows-x64-v0.2.5-Setup.exe`。详情见 [统一安装器说明](packaging/installer/README.md)。首次构建会下载 Microsoft 官方离线依赖并验证其签名，运行安装器时不需要网络或开发工具。

v0.2.5 将设置页接入真实后端：分辨率、60/120 Hz、30/60/120fps 编码上限、2～50 Mbps 码率与触控开关可在连接时点击“应用设置”生效，并持久化保存。状态区分别展示实际显示模式、编码目标与当前编码帧率；尚未接入的预览控件已禁用。Android 的 120 Hz 偏好只作用于平板物理屏幕，不等同于视频实际 120fps。

干净 Windows 验收入口是 `packaging/Test-CleanWindows.ps1`，构建时会一起复制到 `dist/`。脚本会记录并检查是否存在 Visual Studio、WDK、JDK 等开发环境；开发机测试必须显式传入 `-AllowDeveloperMachine`，报告不会把它当作干净机器验收。实体平板的视频与输入功能需要另行连接 USB 验证。

在已配置好 Visual Studio、WDK、Android SDK 与测试签名证书的开发机上运行：

```powershell
.\packaging\Build-ReleasePackages.ps1 -Version 0.2.5
.\packaging\Test-ReleasePackages.ps1 -Version 0.2.5
```

发布脚本会重建 Release 桌面端、Release 控制器、签名驱动包和 Android APK，并在 `dist/` 生成：

- `TabletDisplay-Windows-x64-v0.2.5.zip`
- `TabletDisplay-Android-v0.2.5.apk`
- `SHA256SUMS.txt`

Windows ZIP 是便携布局，包含桌面端、隐藏运行的控制器、驱动与开发证书、Android APK、ADB 下载脚本、安装/卸载入口，以及安装说明、环境要求、首次连接、故障排查、卸载恢复和已知限制。构建产物不会进入 Git；应作为 GitHub Release 附件单独上传。

## 许可与来源

上游样例来自 Microsoft 的 Windows Driver Samples 仓库，其许可证会随下载的源码保留。TabletDisplayDriver 当前从该样例的 IddCx 生命周期和交换链结构演进而来，后续会继续替换样例化的设备发现、帧处理和会话逻辑。
一键启动
cd 'D:\wk\kuo view'
Set-ExecutionPolicy -Scope Process Bypass
.\windows\driver\Build-TabletDisplayDriver.ps1
