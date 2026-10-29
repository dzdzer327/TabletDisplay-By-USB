# Windows 统一安装器与验证记录

日期：2026-10-15；产品版本：0.2.2。

## 安装产物

- `dist/TabletDisplay-Windows-x64-v0.2.2-Setup.exe`：离线 Windows x64 安装器。
- `dist/TabletDisplay-Android-v0.2.2.apk`：配套 Android 应用。
- `dist/Test-CleanWindows.ps1`：带到另一台 Windows 上的验收入口。
- `dist/SHA256SUMS.txt`：下载文件校验值。

安装器使用 Windows 自带的 .NET C# 编译器生成，带管理员 manifest 和图形安装窗口。依次校验载荷、检查平台和版本、安装缺少的 Microsoft 运行库、复制应用与 ADB、导入项目证书、预置驱动、创建快捷方式并注册应用卸载入口。

安装目标默认为 `%ProgramFiles%\USB Tablet Display`，可以选择空目录或已有产品目录。拒绝磁盘根目录、系统根目录及其他非空目录。安装不修改 Secure Boot、测试签名、系统 PATH 或全局 PowerShell 执行策略。

控制器增加 `--dependency-check`，仅检查原生依赖加载，不创建副屏；安装日志与控制器日志位于 `%ProgramData%\USB Tablet Display\Logs`。目录只为日志授予普通用户修改权限，安装程序与驱动文件仍位于受保护安装目录。

## 本机结果

Windows 11 家庭版 x64、版本 10.0.26200；已有 Visual Studio、WDK、JDK、Android SDK 和运行库。

自动验收明确记录 `EnvironmentClean=false`，不得将此记录用作干净系统验收。

最终 EXE 的本机回归结果为 9/9 通过，报告位于 `dist/clean-windows-results/result-20261015-231203.json`。报告记录的安装器 SHA-256 与最终发布文件一致：`F658697E92782828B572D4D6438F74780A022BD0556C23E13F951F6E64D23FC2`。安装界面已从最终 EXE 渲染检查，中文文字、目录框及安装按钮正常显示，预览位于 `dist/installer-test-evidence/installer-ui.png`。

| 检查 | 结果 |
| --- | --- |
| 统一安装器执行 | 退出码 0，安装状态 Installed |
| .NET Framework | 已安装，Release=533509 |
| 原生控制器运行依赖 | 依赖探针退出码 0 |
| 内置 ADB | 从 Program Files 下的包内路径运行成功 |
| 驱动入库/更新 | 0.2.2.0 / oem49.inf 入库，PnPUtil 确认安装到已有软件设备 |
| 桌面/开始菜单/卸载入口 | 均存在 |
| 桌面应用 | 启动后持续运行，正常关闭 |
| 重复安装 | 退出码 0，复用已安装驱动包 |
| 卸载恢复 | 应用目录、卸载注册和安装器新增驱动移除；已有驱动保留 |

卸载后已有设备重新绑定原来的 `oem39.inf / 0.2.1.0`，原本可信的开发证书仍在。测试临时安装的应用目录可通过重新运行安装器恢复，项目源码和原有开发产物未删除。卸载保留 Microsoft 共享运行库、诊断日志和原有驱动版本。

本机已有 Microsoft 运行库，因此缺少运行库时的安装分支尚未实测。当前没有连接 Android 平板，本轮未重复验证真实 USB 视频/触控链路，也未测帧率与长时间稳定性。

## 干净 Windows 验收边界

当前主机没有 Windows Sandbox、Hyper-V 或其他虚拟机，也没有第二台可访问的 Windows 电脑。因此无开发环境的 Windows 验收尚未执行。

将 Setup EXE、`Test-CleanWindows.ps1` 和校验文件复制到另一台 Windows 10 22H2/Windows 11 x64；用管理员 Windows PowerShell 执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-CleanWindows.ps1
```

默认检测到开发工具就拒绝标记为干净验收。需要验证卸载时加 `-TestUninstall`；运行库要求重启时，报告为 `RestartRequired`，重启后加 `-ResumeAfterRestart` 继续。输出 JSON 在脚本同目录的 `clean-windows-results`。

完成自动检查后，实体机器还需要连接平板验证驱动实际启动、窗口拖入副屏、触控、USB 拔插和重连。普通虚拟机中的驱动入库和桌面启动结果不能代替真实显卡和 USB 链路验收。

## 依赖来源

Microsoft 运行库在构建时验证 Microsoft Authenticode 签名，并随安装器内置；ADB 保留原 Platform-Tools 目录中的 NOTICE 和许可证文件。

- [.NET Framework 4.8.1 官方离线安装器](https://dotnet.microsoft.com/en-us/download/dotnet-framework/thank-you/net481-offline-installer)
- [Microsoft Visual C++ Redistributable 官方说明](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170)

Windows 安装 EXE 尚未使用公开信任的代码签名证书；显示驱动仍是项目开发证书签名版本。
