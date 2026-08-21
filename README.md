# Tablet Display

Windows 10/11 通过 USB 连接 Android 平板的有线扩展显示器项目。

当前仓库已完成 Windows 虚拟显示器和 IDD 交换链取帧验证，并开始建立 Android 10+ 客户端。ADB 与 Android APK 构建环境已经可用；视频编码、USB 码流传输和输入回传仍在开发中。

## 当前结构

- `windows/driver/TabletDisplayDriver/`：本项目的独立 Windows 间接显示驱动工程。
- `windows/driver/upstream/`：Microsoft IddSample 上游验证样例，只用于参考和回归对照。
- `android/TabletDisplayApp/`：Android 10+ 平板客户端工程。
- `android/*.ps1`：Android 环境检查与 APK 构建入口。
- `docs/`：阶段验收条件、调试和测试记录。
- `需求分析/`：原始需求说明。

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

构建产物位于 `windows/driver/TabletDisplayDriver/x64/Debug/TabletDisplayDriver.dll`。首期支持一台名为 **Tablet Display** 的虚拟显示器，并提供 1280×720、1920×1080、1920×1200、2560×1600 的 60Hz 模式。

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

开发中需要替换已经预置的 Tablet Display 包时，使用管理员权限运行 `Update-LocalTrustedDriver.ps1`。它只查找 Provider 为 `Tablet Display Project` 的旧包，先卸载这些包再调用本机可信安装脚本，不处理其他显示驱动。

## 构建虚拟设备控制程序

```powershell
.\windows\controller\Build-TabletDisplayController.ps1
```

输出为 `windows/controller/TabletDisplayController/x64/Debug/TabletDisplayController.exe`。驱动成功安装后，运行该程序会创建并保持 Tablet Display 软件设备；按 `X` 退出后设备被移除。

详细的成功判定、回滚和记录格式见 [阶段一清单](docs/phase-1-idd-validation.md)。

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

连接并授权一台 Android 平板后，可一键构建、覆盖安装、建立 ADB 视频端口转发并启动应用：

```powershell
.\android\Deploy-TabletDisplayApp.ps1
```

Android 应用会全屏显示并在设备回环地址 `127.0.0.1:27183` 等待 H.264 视频流。开发协议见 [Android 视频流协议](docs/android-video-protocol.md)。

## 许可与来源

上游样例来自 Microsoft 的 Windows Driver Samples 仓库，其许可证会随下载的源码保留。TabletDisplayDriver 当前从该样例的 IddCx 生命周期和交换链结构演进而来，后续会继续替换样例化的设备发现、帧处理和会话逻辑。
一键启动
cd 'D:\wk\kuo view'
Set-ExecutionPolicy -Scope Process Bypass
.\windows\driver\Build-TabletDisplayDriver.ps1
