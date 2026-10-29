using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace TabletDisplayDesktop
{
    public partial class MainWindow : Window
    {
        private static readonly string[] PageTitles =
        {
            "首页", "显示", "画质与性能", "输入", "设备", "诊断", "设置", "关于"
        };

        private readonly DispatcherTimer statusTimer;
        private readonly string repositoryRoot;
        private bool refreshRunning;
        private long previousSentBytes = -1;
        private DateTime previousSentAt = DateTime.MinValue;
        private string lastDeviceSerial = string.Empty;
        private string lastDeviceModel = string.Empty;

        public MainWindow()
        {
            InitializeComponent();
            InitializeSessionSettings();
            repositoryRoot = FindRepositoryRoot();
            statusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            statusTimer.Tick += async delegate { await RefreshStatusAsync(false); };
        }

        private async void Window_Loaded(object sender, RoutedEventArgs e)
        {
            FooterStatusText.Text = repositoryRoot == null
                ? "未找到项目目录；连接操作不可用"
                : "桌面应用已启动，正在检查连接环境";
            await RefreshStatusAsync(true);
            statusTimer.Start();
        }

        private void Window_Closed(object sender, EventArgs e)
        {
            statusTimer.Stop();
        }

        private void Navigation_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (PageTabs == null || Navigation.SelectedIndex < 0) return;
            PageTabs.SelectedIndex = Navigation.SelectedIndex;
            TopPageTitle.Text = PageTitles[Navigation.SelectedIndex];
        }

        private async void RefreshButton_Click(object sender, RoutedEventArgs e)
        {
            await RefreshStatusAsync(true);
        }

        private async void StartButton_Click(object sender, RoutedEventArgs e)
        {
            if (repositoryRoot == null)
            {
                ShowError("无法定位项目目录，不能启动开发原型。", "启动失败");
                return;
            }

            if (IsControllerRunning())
            {
                FooterStatusText.Text = "扩展屏已经在运行";
                return;
            }

            SetBusy(true, "正在检查平板应用并按需安装或更新；请留意平板安装确认…");
            try
            {
                SessionPreferences selectedSettings = SaveSettingsControls();
                DeviceInfo selectedDevice = await ReadAndroidDeviceAsync();
                if (selectedDevice == null)
                {
                    throw new InvalidOperationException("未检测到真实 USB 平板；模拟器和网络 ADB 设备不会被自动选择");
                }

                string script = FindControllerStartScript();
                if (script == null)
                {
                    throw new FileNotFoundException("未找到控制器启动脚本");
                }
                ProcessResult result = await RunProcessAsync(
                    "powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -SkipBuild -Serial \"" + selectedDevice.Serial + "\" -SettingsPath \"" + settingsFilePath + "\"",
                    repositoryRoot,
                    270000);

                if (result.ExitCode != 0)
                {
                    string combined = result.StandardError + "\n" + result.StandardOutput;
                    if (combined.Contains("ADB_UPDATE_SIGNATURE_MISMATCH"))
                        throw new InvalidOperationException("平板上的旧应用签名不同，无法直接更新。未自动卸载旧应用，请先确认是否需要保留其数据。");
                    if (combined.Contains("ADB_INSTALL_USER_ACTION"))
                        throw new InvalidOperationException("请解锁平板，允许 USB 安装或确认安装提示，然后重新启动扩展屏。");
                    throw new InvalidOperationException(FirstUsefulLine(result.StandardError, result.StandardOutput));
                }

                FooterStatusText.Text = "正在等待 Windows 模式与编码器确认设置…";
                await WaitForSettingsAsync(selectedSettings);
                FooterStatusText.Text = "扩展屏设置已确认：" + DescribeSettings(selectedSettings);
                PendingSettingsText.Text = "控制器已确认此设置。";
                if (result.StandardOutput.Contains("ANDROID_APP_STATUS=Installed")) FooterStatusText.Text += "；平板应用已自动安装";
                if (result.StandardOutput.Contains("ANDROID_APP_STATUS=Updated")) FooterStatusText.Text += "；平板应用已自动更新";
            }
            catch (Exception error)
            {
                ShowError("无法启动扩展屏：" + error.Message, "启动失败");
                FooterStatusText.Text = "启动失败，请运行连接测试";
            }
            finally
            {
                SetBusy(false, null);
                await RefreshStatusAsync(true);
            }
        }

        private async void StopButton_Click(object sender, RoutedEventArgs e)
        {
            SetBusy(true, "正在安全停止视频、输入和虚拟显示器…");
            try
            {
                EventWaitHandle stopEvent = EventWaitHandle.OpenExisting(
                    "Global\\TabletDisplayControllerStop",
                    EventWaitHandleRights.Modify);
                using (stopEvent)
                {
                    stopEvent.Set();
                }

                DateTime deadline = DateTime.UtcNow.AddSeconds(8);
                while (IsControllerRunning() && DateTime.UtcNow < deadline)
                {
                    await Task.Delay(250);
                }

                FooterStatusText.Text = IsControllerRunning()
                    ? "控制器仍在退出，请稍候"
                    : "扩展屏已停止";
            }
            catch (WaitHandleCannotBeOpenedException)
            {
                ShowError("当前运行的控制器不是支持界面停止的新版本。请先重新构建控制器，或在旧控制台中按 X。", "无法停止");
            }
            catch (UnauthorizedAccessException)
            {
                ShowError("没有权限请求控制器停止。请重新构建并重新启动控制器。", "无法停止");
            }
            finally
            {
                SetBusy(false, null);
                await RefreshStatusAsync(true);
            }
        }

        private void OpenDisplaySettings_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Process.Start(new ProcessStartInfo("ms-settings:display") { UseShellExecute = true });
            }
            catch (Exception error)
            {
                ShowError(error.Message, "无法打开 Windows 显示设置");
            }
        }

        private void ReturnCursor_Click(object sender, RoutedEventArgs e)
        {
            NativeMethods.RECT workArea = new NativeMethods.RECT();
            if (NativeMethods.SystemParametersInfo(0x0030, 0, ref workArea, 0))
            {
                NativeMethods.SetCursorPos(
                    workArea.Left + (workArea.Right - workArea.Left) / 2,
                    workArea.Top + (workArea.Bottom - workArea.Top) / 2);
                FooterStatusText.Text = "鼠标已移回主屏工作区中央";
            }
        }

        private async void TestConnection_Click(object sender, RoutedEventArgs e)
        {
            Navigation.SelectedIndex = 5;
            RunDiagnosticsButton.IsEnabled = false;
            DiagnosticsText.Text = "正在运行连接测试…";
            ResetDiagnosticRows();

            StringBuilder summary = new StringBuilder();
            summary.AppendLine("USB Tablet Display 连接测试");
            summary.AppendLine("时间：" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            summary.AppendLine();

            bool controller = IsControllerRunning();
            SetDiagnosticRow(DiagServiceIcon, DiagServiceText, controller, controller ? "正在运行" : "尚未运行");
            summary.AppendLine("Windows 控制器：" + (controller ? "通过" : "未运行"));

            bool driver = false;
            try
            {
                ProcessResult pnp = await RunProcessAsync("pnputil.exe", "/enum-devices /class Display", repositoryRoot, 10000);
                driver = pnp.StandardOutput.IndexOf("Tablet Display", StringComparison.OrdinalIgnoreCase) >= 0 ||
                         (controller && FindLatestRuntimeLog() != null);
            }
            catch { }
            SetDiagnosticRow(DiagDriverIcon, DiagDriverText, driver, driver ? "已加载" : "未检测到");
            summary.AppendLine("虚拟显示驱动：" + (driver ? "通过" : "未检测到活动设备"));

            DeviceInfo device = await ReadAndroidDeviceAsync();
            bool usb = device != null;
            SetDiagnosticRow(DiagUsbIcon, DiagUsbText, usb, usb ? device.Model : "没有已授权设备");
            summary.AppendLine("USB / ADB：" + (usb ? "通过（" + device.Model + "）" : "失败；请检查数据线和 USB 调试授权"));

            RuntimeStatus runtime = ReadRuntimeStatus();
            bool video = runtime != null && runtime.EncodedFrames > 0 && runtime.LastError == 0;
            SetDiagnosticRow(DiagVideoIcon, DiagVideoText, video, video ? runtime.VideoFps + " fps" : "等待视频会话");
            summary.AppendLine("视频通道：" + (video ? "通过（" + runtime.Width + "×" + runtime.Height + "，" + runtime.VideoFps + "fps）" : "尚未收到有效编码状态"));

            bool input = runtime != null && runtime.InputConnected;
            SetDiagnosticRow(DiagInputIcon, DiagInputText, input, input ? "已连接" : "等待平板连接");
            summary.AppendLine("触控通道：" + (input ? "通过" : "尚未连接"));
            summary.AppendLine();

            if (video && input)
            {
                summary.AppendLine("结论：视频和输入链路均正常。");
            }
            else if (!usb)
            {
                summary.AppendLine("建议：确认数据线支持数据传输，并在平板上允许 USB 调试授权。当前版本仍使用 ADB 开发连接。");
            }
            else if (!controller)
            {
                summary.AppendLine("建议：返回首页，点击“开始扩展屏”。");
            }
            else
            {
                summary.AppendLine("建议：保持平板应用位于前台，等待关键帧；仍未恢复时停止后重新连接。");
            }

            DiagnosticsText.Text = summary.ToString();
            RunDiagnosticsButton.IsEnabled = true;
            FooterStatusText.Text = "连接测试完成";
            await RefreshStatusAsync(true);
        }

        private async void PerformanceTest_Click(object sender, RoutedEventArgs e)
        {
            FooterStatusText.Text = "性能测试 UI 已就绪；自动测试动画将在后续引擎接口中接入";
            await Task.Delay(50);
            MessageBox.Show(
                this,
                "当前界面已能读取实时捕获、编码和帧率数据。\n\n自动生成 30 秒测试动画需要下一阶段的服务控制接口，当前不会擅自移动或覆盖你的窗口。",
                "性能测试",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }

        private void CopyDiagnostics_Click(object sender, RoutedEventArgs e)
        {
            Clipboard.SetText(DiagnosticsText.Text ?? string.Empty);
            FooterStatusText.Text = "诊断摘要已复制";
        }

        private void OpenLogFolder_Click(object sender, RoutedEventArgs e)
        {
            string log = FindLatestRuntimeLog();
            string folder = log == null ? repositoryRoot : Path.GetDirectoryName(log);
            if (folder != null && Directory.Exists(folder))
            {
                Process.Start(new ProcessStartInfo("explorer.exe", "\"" + folder + "\"") { UseShellExecute = true });
            }
        }

        private async Task RefreshStatusAsync(bool includeDeviceProbe)
        {
            if (refreshRunning) return;
            refreshRunning = true;
            try
            {
                bool controller = IsControllerRunning();
                RuntimeStatus runtime = ReadRuntimeStatus();
                DeviceInfo device = includeDeviceProbe || string.IsNullOrEmpty(lastDeviceSerial)
                    ? await ReadAndroidDeviceAsync()
                    : new DeviceInfo(lastDeviceSerial, lastDeviceModel);

                if (device != null)
                {
                    lastDeviceSerial = device.Serial;
                    lastDeviceModel = device.Model;
                    DeviceNameText.Text = device.Model;
                    DeviceDetailsText.Text = "序列号 " + device.Serial + " · 已通过 ADB 授权";
                    UsbModeText.Text = "USB：数据连接正常";
                    SidebarDeviceText.Text = device.Model;
                }
                else
                {
                    lastDeviceSerial = string.Empty;
                    lastDeviceModel = string.Empty;
                    DeviceNameText.Text = "未检测到 Android 平板";
                    DeviceDetailsText.Text = "请连接支持数据传输的 USB 线并允许授权";
                    UsbModeText.Text = "USB：等待设备";
                    SidebarDeviceText.Text = "未检测到平板";
                }

                if (controller && runtime != null && runtime.EncodedFrames > 0)
                {
                    SetConnectionVisual("扩展屏正在运行", device == null ? "视频引擎已启动，等待平板" : device.Model + " 已连接", Brushes.MediumSeaGreen);
                    HeroStatusTitle.Text = "扩展屏正在运行";
                    HeroStatusDetail.Text = runtime.StatusText;
                    HeroDisplayDetail.Text = runtime.Width + " × " + runtime.Height + " · 编码 " + runtime.VideoFps + " / 目标 " + runtime.TargetFps + "fps · " + runtime.DisplayHz + " Hz";
                    StartButton.IsEnabled = false;
                    StopButton.IsEnabled = true;
                }
                else if (controller)
                {
                    SetConnectionVisual("正在建立画面", device == null ? "等待平板连接" : device.Model, (Brush)FindResource("WarningBrush"));
                    HeroStatusTitle.Text = "正在建立画面";
                    HeroStatusDetail.Text = runtime == null ? "控制器已启动，等待视频状态" : runtime.StatusText;
                    HeroDisplayDetail.Text = "请保持平板应用位于前台";
                    StartButton.IsEnabled = false;
                    StopButton.IsEnabled = true;
                }
                else if (device != null)
                {
                    SetConnectionVisual("平板已就绪", device.Model, (Brush)FindResource("PrimaryBrush"));
                    HeroStatusTitle.Text = "平板已连接，扩展屏未启动";
                    HeroStatusDetail.Text = "点击“开始扩展屏”建立视频和触控会话。";
                    HeroDisplayDetail.Text = "开发连接：ADB · " + device.Serial;
                    StartButton.IsEnabled = true;
                    StopButton.IsEnabled = false;
                }
                else
                {
                    SetConnectionVisual("未连接", "请连接 Android 平板", Brushes.Gray);
                    HeroStatusTitle.Text = "等待 Android 平板";
                    HeroStatusDetail.Text = "请使用支持数据传输的 USB 线连接平板。";
                    HeroDisplayDetail.Text = "当前开发版需要 USB 调试授权";
                    StartButton.IsEnabled = true;
                    StopButton.IsEnabled = false;
                }

                ApplyRuntimeMetrics(controller ? runtime : null);
                StartButton.IsEnabled = !operationBusy && !controller;
                StopButton.IsEnabled = !operationBusy && controller;
            }
            finally
            {
                refreshRunning = false;
            }
        }

        private void ApplyRuntimeMetrics(RuntimeStatus runtime)
        {
            if (runtime == null)
            {
                FpsText.Text = "-- fps";
                BitrateText.Text = "-- Mbps";
                EncodingPathText.Text = "--";
                CaptureTimeText.Text = "-- μs";
                EncodeTimeText.Text = "-- μs";
                ZeroCopyText.Text = "等待会话";
                AppliedSettingsText.Text = "Windows 实际模式：未连接";
                VideoTargetText.Text = "编码目标：未连接；当前选择可保存到下次启动。";
                previousSentBytes = -1;
                previousSentAt = DateTime.MinValue;
                return;
            }

            FpsText.Text = runtime.VideoFps + " fps";
            AppliedSettingsText.Text = "Windows 实际模式：" + runtime.DisplayWidth + "×" + runtime.DisplayHeight + " · " + runtime.DisplayHz + " Hz";
            VideoTargetText.Text = "已生效编码目标：" + runtime.TargetFps + "fps · " + (runtime.TargetBitrate / 1000000.0).ToString("0.#") +
                " Mbps；当前编码 " + runtime.VideoFps + "fps。静态桌面帧率降低属于正常现象。";
            EncodingPathText.Text = runtime.Hardware ? "硬件 / " + (runtime.ZeroCopy ? "D3D11" : "内存") : "软件编码";
            CaptureTimeText.Text = runtime.CaptureUs + " μs";
            EncodeTimeText.Text = runtime.EncodeUs + " μs";
            ZeroCopyText.Text = runtime.ZeroCopy ? "已启用" : "未启用";
            ZeroCopyText.Foreground = runtime.ZeroCopy ? (Brush)FindResource("SuccessBrush") : (Brush)FindResource("WarningBrush");

            DateTime now = DateTime.UtcNow;
            if (previousSentBytes >= 0 && runtime.SentBytes >= previousSentBytes && previousSentAt != DateTime.MinValue)
            {
                double seconds = (now - previousSentAt).TotalSeconds;
                if (seconds > 0.2)
                {
                    double mbps = (runtime.SentBytes - previousSentBytes) * 8.0 / seconds / 1000000.0;
                    BitrateText.Text = mbps.ToString("0.0") + " Mbps";
                }
            }
            previousSentBytes = runtime.SentBytes;
            previousSentAt = now;
        }

        private void SetConnectionVisual(string state, string detail, Brush brush)
        {
            SidebarStatusText.Text = state;
            TopStatusText.Text = state;
            SidebarStatusDot.Fill = brush;
            TopStatusDot.Fill = brush;
            HeroStatusDot.Fill = brush;
            if (!string.IsNullOrEmpty(detail)) SidebarDeviceText.Text = detail;
        }

        private void SetBusy(bool busy, string text)
        {
            operationBusy = busy;
            QuickApplyButton.IsEnabled = DisplayApplyButton.IsEnabled = VideoApplyButton.IsEnabled = !busy;
            StartButton.IsEnabled = !busy && !IsControllerRunning();
            StopButton.IsEnabled = !busy && IsControllerRunning();
            RunDiagnosticsButton.IsEnabled = !busy;
            if (!string.IsNullOrEmpty(text)) FooterStatusText.Text = text;
        }

        private void ResetDiagnosticRows()
        {
            TextBlock[] icons = { DiagServiceIcon, DiagDriverIcon, DiagUsbIcon, DiagVideoIcon, DiagInputIcon };
            TextBlock[] labels = { DiagServiceText, DiagDriverText, DiagUsbText, DiagVideoText, DiagInputText };
            foreach (TextBlock icon in icons) icon.Foreground = Brushes.Goldenrod;
            foreach (TextBlock label in labels) label.Text = "正在检查";
        }

        private void SetDiagnosticRow(TextBlock icon, TextBlock text, bool success, string detail)
        {
            icon.Foreground = success ? Brushes.MediumSeaGreen : Brushes.IndianRed;
            text.Text = detail;
            text.Foreground = success ? Brushes.SeaGreen : Brushes.IndianRed;
        }

        private RuntimeStatus ReadRuntimeStatus()
        {
            try
            {
                string logPath = FindLatestRuntimeLog();
                if (logPath == null) return null;
                string lastLine = File.ReadLines(logPath).LastOrDefault(line => line.StartsWith("driverFrames=", StringComparison.Ordinal));
                if (lastLine == null) return null;
                return RuntimeStatus.Parse(lastLine);
            }
            catch
            {
                return null;
            }
        }

        private string FindLatestRuntimeLog()
        {
            string installedLog = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "USB Tablet Display", "Logs", "TabletDisplayController.runtime.log");
            if (File.Exists(installedLog)) return installedLog;
            if (repositoryRoot == null) return null;
            string portableRuntime = Path.Combine(repositoryRoot, "runtime");
            string controllerRoot = Directory.Exists(portableRuntime)
                ? portableRuntime
                : Path.Combine(repositoryRoot, "windows", "controller", "TabletDisplayController", "x64");
            if (!Directory.Exists(controllerRoot)) return null;
            return Directory.GetFiles(controllerRoot, "TabletDisplayController.runtime.log", SearchOption.AllDirectories)
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault();
        }

        private async Task<DeviceInfo> ReadAndroidDeviceAsync()
        {
            string adb = FindAdb();
            if (adb == null) return null;
            try
            {
                ProcessResult result = await RunProcessAsync(adb, "devices -l", repositoryRoot, 6000);
                foreach (string line in result.StandardOutput.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    Match match = Regex.Match(line, "^(\\S+)\\s+device(?:\\s|$).*(?:model:)(\\S+)", RegexOptions.IgnoreCase);
                    if (match.Success)
                    {
                        string serial = match.Groups[1].Value;
                        if (IsPhysicalUsbSerial(serial))
                        {
                            return new DeviceInfo(serial, FormatDeviceModel(match.Groups[2].Value));
                        }
                    }
                }
            }
            catch { }
            return null;
        }

        private static bool IsPhysicalUsbSerial(string serial)
        {
            return !serial.StartsWith("emulator-", StringComparison.OrdinalIgnoreCase) &&
                   serial.IndexOf(':') < 0;
        }

        private static string FormatDeviceModel(string model)
        {
            if (string.Equals(model, "DBR_W10", StringComparison.OrdinalIgnoreCase))
            {
                return "HUAWEI DBR-W10";
            }
            return model.Replace('_', ' ');
        }

        private string FindAdb()
        {
            string[] candidates =
            {
                repositoryRoot == null ? null : Path.Combine(repositoryRoot, "tools", "platform-tools", "adb.exe"),
                Path.Combine(Environment.GetEnvironmentVariable("ANDROID_HOME") ?? string.Empty, "platform-tools", "adb.exe"),
                Path.Combine(Environment.GetEnvironmentVariable("ANDROID_SDK_ROOT") ?? string.Empty, "platform-tools", "adb.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Android", "Sdk", "platform-tools", "adb.exe"),
                @"D:\DevTools\Android\Sdk\platform-tools\adb.exe"
            };
            foreach (string candidate in candidates)
            {
                if (!string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate)) return candidate;
            }
            string path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            foreach (string folder in path.Split(Path.PathSeparator))
            {
                try
                {
                    string candidate = Path.Combine(folder.Trim(), "adb.exe");
                    if (File.Exists(candidate)) return candidate;
                }
                catch { }
            }
            return null;
        }

        private static bool IsControllerRunning()
        {
            try { return Process.GetProcessesByName("TabletDisplayController").Length > 0; }
            catch { return false; }
        }

        private static bool TrySetTabletDisplayRefreshRate(int refreshRate)
        {
            for (uint index = 0; ; index++)
            {
                NativeMethods.DISPLAY_DEVICE device = new NativeMethods.DISPLAY_DEVICE();
                device.cb = Marshal.SizeOf(typeof(NativeMethods.DISPLAY_DEVICE));
                if (!NativeMethods.EnumDisplayDevices(null, index, ref device, 0)) return false;
                bool isUsbTabletDisplay =
                    string.Equals(device.DeviceString, "USB Tablet Display", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(device.DeviceString, "Tablet Display", StringComparison.OrdinalIgnoreCase);
                if (!isUsbTabletDisplay ||
                    (device.StateFlags & NativeMethods.DisplayDeviceAttachedToDesktop) == 0)
                {
                    continue;
                }

                NativeMethods.DEVMODE current = NativeMethods.CreateDevMode();
                if (!NativeMethods.EnumDisplaySettings(device.DeviceName, NativeMethods.EnumCurrentSettings, ref current))
                {
                    return false;
                }
                if (current.dmDisplayFrequency == refreshRate) return true;

                bool modeAvailable = false;
                for (int modeIndex = 0; ; modeIndex++)
                {
                    NativeMethods.DEVMODE candidate = NativeMethods.CreateDevMode();
                    if (!NativeMethods.EnumDisplaySettings(device.DeviceName, modeIndex, ref candidate)) break;
                    if (candidate.dmPelsWidth == current.dmPelsWidth &&
                        candidate.dmPelsHeight == current.dmPelsHeight &&
                        candidate.dmDisplayFrequency == refreshRate)
                    {
                        modeAvailable = true;
                        break;
                    }
                }
                if (!modeAvailable) return false;

                current.dmDisplayFrequency = refreshRate;
                current.dmFields = NativeMethods.DmPelsWidth |
                                   NativeMethods.DmPelsHeight |
                                   NativeMethods.DmDisplayFrequency;
                return NativeMethods.ChangeDisplaySettingsEx(
                    device.DeviceName,
                    ref current,
                    IntPtr.Zero,
                    NativeMethods.CdsUpdateRegistry,
                    IntPtr.Zero) == NativeMethods.DispChangeSuccessful;
            }
        }

        private string FindRepositoryRoot()
        {
            DirectoryInfo directory = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            for (int i = 0; i < 8 && directory != null; i++, directory = directory.Parent)
            {
                if (File.Exists(Path.Combine(directory.FullName, "runtime", "Start-TabletDisplayPrototype.ps1")))
                {
                    return directory.FullName;
                }
                if (File.Exists(Path.Combine(directory.FullName, "README.md")) &&
                    File.Exists(Path.Combine(directory.FullName, "windows", "controller", "Start-TabletDisplayPrototype.ps1")))
                {
                    return directory.FullName;
                }
            }
            return null;
        }

        private string FindControllerStartScript()
        {
            if (repositoryRoot == null) return null;
            string portable = Path.Combine(repositoryRoot, "runtime", "Start-TabletDisplayPrototype.ps1");
            if (File.Exists(portable)) return portable;
            string development = Path.Combine(repositoryRoot, "windows", "controller", "Start-TabletDisplayPrototype.ps1");
            return File.Exists(development) ? development : null;
        }

        private static Task<ProcessResult> RunProcessAsync(string fileName, string arguments, string workingDirectory, int timeoutMs)
        {
            return Task.Run(delegate
            {
                using (Process process = new Process())
                {
                    process.StartInfo = new ProcessStartInfo
                    {
                        FileName = fileName,
                        Arguments = arguments,
                        WorkingDirectory = workingDirectory ?? Environment.CurrentDirectory,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true
                    };
                    process.Start();
                    Task<string> stdout = process.StandardOutput.ReadToEndAsync();
                    Task<string> stderr = process.StandardError.ReadToEndAsync();
                    if (!process.WaitForExit(timeoutMs))
                    {
                        try { process.Kill(); } catch { }
                        throw new TimeoutException("操作超时，请检查平板上的 USB 授权或安装确认后重试");
                    }
                    return new ProcessResult(process.ExitCode, stdout.Result, stderr.Result);
                }
            });
        }

        private static string FirstUsefulLine(params string[] values)
        {
            foreach (string value in values)
            {
                if (string.IsNullOrWhiteSpace(value)) continue;
                string line = value.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
                if (!string.IsNullOrWhiteSpace(line)) return line.Trim();
            }
            return "未知错误";
        }

        private void ShowError(string text, string title)
        {
            MessageBox.Show(this, text, title, MessageBoxButton.OK, MessageBoxImage.Warning);
        }

        private sealed class DeviceInfo
        {
            public DeviceInfo(string serial, string model) { Serial = serial; Model = model; }
            public string Serial { get; private set; }
            public string Model { get; private set; }
        }

        private sealed class ProcessResult
        {
            public ProcessResult(int exitCode, string stdout, string stderr)
            {
                ExitCode = exitCode;
                StandardOutput = stdout;
                StandardError = stderr;
            }
            public int ExitCode { get; private set; }
            public string StandardOutput { get; private set; }
            public string StandardError { get; private set; }
        }

        private sealed class RuntimeStatus
        {
            public int Width;
            public int Height;
            public int VideoFps;
            public int TargetFps;
            public int TargetBitrate;
            public int DisplayWidth;
            public int DisplayHeight;
            public int DisplayHz;
            public int SettingsError;
            public long RequestedRevision;
            public long StreamRevision;
            public long EncodedFrames;
            public long SentBytes;
            public long CaptureUs;
            public long EncodeUs;
            public long LastError;
            public bool InputConnected;
            public bool Hardware;
            public bool ZeroCopy;
            public string EncoderName = "--";
            public string StatusText = "正在运行";

            public static RuntimeStatus Parse(string line)
            {
                RuntimeStatus status = new RuntimeStatus();
                Match size = Regex.Match(line, "videoSize=(\\d+)x(\\d+)");
                if (size.Success)
                {
                    status.Width = ParseInt(size.Groups[1].Value);
                    status.Height = ParseInt(size.Groups[2].Value);
                }
                status.VideoFps = ParseInt(Value(line, "videoFps", "0"));
                status.TargetFps = ParseInt(Value(line, "targetFps", "0"));
                status.TargetBitrate = ParseInt(Value(line, "targetBitrate", "0"));
                status.DisplayWidth = ParseInt(Value(line, "displayWidth", "0"));
                status.DisplayHeight = ParseInt(Value(line, "displayHeight", "0"));
                status.DisplayHz = ParseInt(Value(line, "displayHz", "0"));
                status.SettingsError = ParseInt(Value(line, "settingsError", "0"));
                status.RequestedRevision = ParseLong(Value(line, "requestedRevision", "0"));
                status.StreamRevision = ParseLong(Value(line, "streamRevision", "0"));
                status.EncodedFrames = ParseLong(Value(line, "encoded", "0"));
                status.SentBytes = ParseLong(Value(line, "sentBytes", "0"));
                status.CaptureUs = ParseLong(Value(line, "captureUs", "0"));
                status.EncodeUs = ParseLong(Value(line, "encodeUs", "0"));
                status.InputConnected = Value(line, "inputConnected", "0") == "1";
                status.Hardware = Value(line, "hardware", "0") == "1";
                status.ZeroCopy = Value(line, "zeroCopy", "0") == "1";
                status.EncoderName = QuotedValue(line, "encoder") ?? "--";
                status.StatusText = QuotedValue(line, "status") ?? "正在运行";
                string error = Value(line, "error", "0").Replace("0x", string.Empty);
                long.TryParse(error, System.Globalization.NumberStyles.HexNumber, null, out status.LastError);
                return status;
            }

            private static string Value(string line, string key, string fallback)
            {
                Match match = Regex.Match(line, "(?:^|\\s)" + Regex.Escape(key) + "=([^\\s]+)");
                return match.Success ? match.Groups[1].Value : fallback;
            }

            private static string QuotedValue(string line, string key)
            {
                Match match = Regex.Match(line, "(?:^|\\s)" + Regex.Escape(key) + "=\\\"([^\\\"]*)\\\"");
                return match.Success ? match.Groups[1].Value : null;
            }

            private static int ParseInt(string value) { int result; return int.TryParse(value, out result) ? result : 0; }
            private static long ParseLong(string value) { long result; return long.TryParse(value, out result) ? result : 0; }
        }

        private static class NativeMethods
        {
            public const int EnumCurrentSettings = -1;
            public const int DisplayDeviceAttachedToDesktop = 0x1;
            public const int CdsUpdateRegistry = 0x1;
            public const int DispChangeSuccessful = 0;
            public const int DmPelsWidth = 0x00080000;
            public const int DmPelsHeight = 0x00100000;
            public const int DmDisplayFrequency = 0x00400000;

            [StructLayout(LayoutKind.Sequential)]
            public struct RECT { public int Left, Top, Right, Bottom; }

            [StructLayout(LayoutKind.Sequential)]
            public struct POINTL { public int X, Y; }

            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
            public struct DISPLAY_DEVICE
            {
                public int cb;
                [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
                [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
                public int StateFlags;
                [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceId;
                [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
            }

            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
            public struct DEVMODE
            {
                [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
                public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
                public int dmFields;
                public POINTL dmPosition;
                public int dmDisplayOrientation, dmDisplayFixedOutput;
                public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
                [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
                public short dmLogPixels;
                public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
                public int dmIcmMethod, dmIcmIntent, dmMediaType, dmDitherType;
                public int dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
            }

            public static DEVMODE CreateDevMode()
            {
                DEVMODE mode = new DEVMODE();
                mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                return mode;
            }

            [DllImport("user32.dll", CharSet = CharSet.Unicode)]
            public static extern bool EnumDisplayDevices(
                string deviceName, uint deviceIndex, ref DISPLAY_DEVICE displayDevice, uint flags);

            [DllImport("user32.dll", CharSet = CharSet.Unicode)]
            public static extern bool EnumDisplaySettings(string deviceName, int modeIndex, ref DEVMODE mode);

            [DllImport("user32.dll", CharSet = CharSet.Unicode)]
            public static extern int ChangeDisplaySettingsEx(
                string deviceName, ref DEVMODE mode, IntPtr window, int flags, IntPtr parameter);

            [DllImport("user32.dll")]
            public static extern bool SetCursorPos(int x, int y);

            [DllImport("user32.dll")]
            public static extern bool SystemParametersInfo(uint action, uint parameter, ref RECT value, uint flags);
        }
    }
}
