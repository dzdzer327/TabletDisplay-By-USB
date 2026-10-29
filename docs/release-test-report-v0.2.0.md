# v0.2.0 发布包本机测试记录

测试日期：2026-10-08。对象为 `dist/TabletDisplay-Windows-x64-v0.2.0.zip` 与 `dist/TabletDisplay-Android-v0.2.0.apk`。

## 测试环境和范围

- Windows 11 开发机，有 Visual Studio、WDK、Visual C++ 运行库、既有开发证书信任和旧版项目驱动。
- 真实 USB 平板：HUAWEI DBR-W10，ADB 序列号 `<device-serial>`。
- 从 ZIP 解压到独立目录运行，未使用源码目录的桌面端或控制器 EXE。
- 本次是短时本机功能验证，不代表干净电脑兼容性、持续高帧率或 8 小时稳定性验收。

## 通过项

| 项目 | 结果和证据 |
| --- | --- |
| 下载文件校验 | 两个发布文件均匹配 `SHA256SUMS.txt` |
| ZIP 内容 | 16 个文件匹配 `MANIFEST.sha256`，无 PDB、OBJ、日志或源码文件 |
| 脚本与桌面启动 | 包内 PowerShell 解析通过，解压后桌面 EXE 成功启动 |
| Android 安装 | 发布 APK 成功覆盖安装；versionCode=2、versionName=0.2.0、minSdk=29、targetSdk=36 |
| ADB 安装 | 包内脚本成功从 Google 下载 Platform-Tools；包内 adb.exe 可运行 |
| 驱动安装器 | 管理员安装脚本返回 0，发布驱动加入 Driver Store；实际绑定问题见下方 |
| 独立副屏 | Windows 枚举主屏 1920×1080，副屏 1920×1200，副屏位于主屏右侧 |
| 视频链路 | 日志为 `Streaming to Android`、`hardware=1`、`zeroCopy=1`、`NVIDIA H.264 Encoder MFT`、`error=0x0` |
| 平板显示 | Android 截图实际出现 Windows 副屏桌面和任务栏 |
| 基础触控回传 | 使用 Android ADB input 模拟点击，Windows 成功注入 DOWN/UP；`touchFrames=2`、`error=0x0` |
| 普通权限停止 | 打开控制器命名事件、发送停止信号成功；控制器退出，活动软件显示设备移除 |
| 再次连接 | 使用包内 ADB 重启连接成功；跳过已安装 APK，再次显示副屏 |

截图与日志保存于 `dist/test-evidence/`。这是本地证据目录，不进入 Git。

## 发现的问题

1. **Windows 运行依赖未完整处理。** `dumpbin /dependents` 确认 Release 控制器及驱动 DLL 依赖 `MSVCP140.dll`、`VCRUNTIME140.dll`、`VCRUNTIME140_1.dll`。当前配置脚本没有检查或安装 Visual C++ x64 运行库，说明中也未列出；本机已有该依赖，干净电脑仍可能失败。
2. **已有高版本驱动时，安装成功不等于升级成功。** 发布包驱动为 0.2.0.0 / `oem45.inf`，Windows 仍选择已安装的 0.2.1.0 / `oem39.inf`。因此本次真实画面验证使用了既有 0.2.1.0 驱动，不能声称已验证发布包 Release 驱动的实际加载。未删除现有旧驱动。
3. **首次显示拓扑建立后不会自动恢复。** 首次启动在约 10 秒枚举窗口内找不到副屏，报 `No non-primary display output was found (0x887a0002)`。切换 Windows 扩展模式后，旧视频线程仍保留失败状态；停止并重启控制器后成功。源码显示初始枚举最多尝试 100 次、每次等待 100ms，失败后未自动重建该链路。

## 尚未验收

- 干净 Windows 10/11 机器安装、实际加载包内 Release 驱动。
- 持续运动画面下 60/120fps 吞吐、平板呈现帧率、端到端延迟与 CPU/GPU 开销。
- 物理 USB 拔插、休眠、旋转、分辨率变化、多次自动重连。
- 真实手指拖拽、多指手势、软键盘输入；本次只验证了自动化点击的基础注入链路。
- 连续 8 小时稳定性、卸载脚本执行后的完整恢复。本次未运行卸载脚本。

测试结束保留连接与便携桌面应用，方便继续手动操作；可在桌面端点击“停止扩展屏”退出。
