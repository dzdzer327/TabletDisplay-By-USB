# USB Tablet Display 0.2.5 安装版

双击 `TabletDisplay-Windows-x64-v0.2.5-Setup.exe`，允许管理员权限，选择目录并点击“安装”。程序会离线配置 Microsoft .NET Framework 4.8.1、Visual C++ x64 运行库、ADB 和虚拟显示驱动，创建桌面与开始菜单快捷方式。

安装后的应用无需 Visual Studio、WDK、Java 或 Android SDK。若安装日志提示需要重启，请先重启 Windows。管理员身份用另一账户授权时，所有用户都可以使用公共桌面快捷方式。

## 平板连接

1. 开启平板的开发者选项和 USB 调试，插入数据线，允许电脑调试授权。
2. 保持平板解锁。从电脑桌面启动 USB Tablet Display，点击“启动扩展屏”。
3. 电脑会检查平板应用版本，未安装时自动安装，旧版本自动更新到电脑包内置 APK 的版本，然后打开平板应用。部分设备需要在平板上确认 USB 安装。相同版本不重复安装，更高版本不降级；签名冲突时保留旧应用并提示处理。
4. 在 Windows 显示设置中选择“扩展这些显示器”并排列屏幕。

当前只自动选择一台真实 USB Android 设备，模拟器和网络 ADB 不会被选中。首次连接显示器枚举超时后，可停止再启动连接。120 Hz 仍为实验功能。

自动更新使用当前电脑安装包内置的 APK；更新电脑安装包后，下次启动扩展屏会同步新版到平板。安装目录也保留独立 APK，供手动安装备用。

## 调整显示与性能

默认 60 Hz / 60fps / 8 Mbps。首页选择 120fps 会同步选择 Windows 副屏 120 Hz，再点击“应用设置”。连接期间可切换分辨率、60/120 Hz、30/60/120fps 编码上限、2～50 Mbps 码率及触控开关；视频会短暂重连，状态在控制器确认后才显示生效。设置会保留到下次启动。

实际 Windows 刷新率、编码帧率上限、当前编码帧率和 Android 解码/物理刷新率是不同指标；静止桌面或低性能设备不能保证实际 120fps。平板“优先使用 120 Hz”仅请求平板自身刷新率，画质与编码参数由电脑控制。尚未接入的预览选项已禁用；屏幕排列、方向和缩放请使用 Windows 原生显示设置。

## 驱动与卸载

当前驱动由项目开发证书签名，安装会把该证书加入本机根证书与受信任发布者。安装器不修改 Secure Boot、测试签名或其他启动配置，不会强制删除其他版本驱动。若已安装更高版本项目驱动，会停止安装并提示使用更新的安装包。

通过 Windows“设置 → 应用 → 已安装的应用 → USB Tablet Display → 卸载”，或运行安装目录的 `Uninstall.exe`。卸载只处理本安装器新增的驱动与证书信任；已有的开发证书、其他版本驱动和 Microsoft 共享运行库会保留。

安装、控制器日志位于 `%ProgramData%\USB Tablet Display\Logs`，卸载后保留用于诊断。平板应用应在 Android 上单独卸载。

## 环境与限制

- Windows 10 22H2 / Windows 11 x64；Android 10+；支持数据传输的 USB 线。
- 当前仍依赖 USB 调试和开发证书，尚未完成 Microsoft 正式签名发布。
- 普通 Windows 虚拟机可验证安装、依赖和卸载；真实 USB、显卡编解码、扩展屏功能应在实体机上单独验收。
- 不支持多平板、无线、音频、HDR、DRM 和压感笔。

## 干净 Windows 验证

将 Setup EXE 和 `Test-CleanWindows.ps1` 复制到没有开发环境的 Windows，使用管理员 Windows PowerShell 运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-CleanWindows.ps1
```

脚本会记录机器是否已有开发工具，运行统一安装器，检查版本、运行库、ADB、驱动仓库与应用启动，随后重复安装检查幂等性。默认不会卸载，便于继续插入平板测试；使用 `-TestUninstall` 可额外验证卸载恢复。结果保存在脚本旁边的 `clean-windows-results`。

若报告为 `RestartRequired`，请重启 Windows，再使用 `-ResumeAfterRestart` 继续验收。已安装的共享运行库不会被测试脚本卸载或降级。
