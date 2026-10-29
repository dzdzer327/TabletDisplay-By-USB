using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("USB Tablet Display Setup")]
[assembly: AssemblyProduct("USB Tablet Display")]
[assembly: AssemblyVersion("0.2.5.0")]
[assembly: AssemblyFileVersion("0.2.5.0")]

internal static class Installer
{
    internal const string ProductId = "USBTabletDisplay";
    internal const string Version = "0.2.5";
    internal const string RegistryPath = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\USBTabletDisplay";
    internal static bool Silent;
    internal static bool Remove;
    internal static Action<string> Progress = delegate { };
    internal static readonly string LogDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "USB Tablet Display", "Logs");

    [STAThread]
    private static int Main(string[] args)
    {
        Silent = Array.IndexOf(args, "--silent") >= 0;
#if UNINSTALLER
        Remove = true;
#endif
        Remove = Remove || Array.IndexOf(args, "--uninstall") >= 0;
        string target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "USB Tablet Display");
        for (int i = 0; i < args.Length; i++)
            if (args[i] == "--install-dir" && i + 1 < args.Length) target = args[++i];

        try
        {
            if (!Environment.Is64BitOperatingSystem) throw new InvalidOperationException("需要 Windows x64。");
            target = ValidateTarget(target);
            if (Remove && Array.IndexOf(args, "--worker") < 0)
            {
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey(RegistryPath))
                {
                    if (key == null) throw new InvalidOperationException("未找到应用安装记录。");
                    target = ValidateTarget(Convert.ToString(key.GetValue("InstallLocation")));
                }
                string workerDirectory = Path.Combine(Path.GetTempPath(), "USBTabletDisplay-Uninstall-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(workerDirectory);
                string worker = Path.Combine(workerDirectory, "Uninstall.exe");
                File.Copy(Assembly.GetExecutingAssembly().Location, worker);
                Process.Start(new ProcessStartInfo(worker,
                    "--uninstall --worker --install-dir " + Quote(target) + (Silent ? " --silent" : ""))
                    { UseShellExecute = false });
                return 0;
            }
            if (Silent)
            {
                Execute(target);
                return 0;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using (SetupForm form = new SetupForm(target))
            {
                Application.Run(form);
                return form.Result;
            }
        }
        catch (Exception error)
        {
            WriteLog("FAILED: " + error);
            if (!Silent) MessageBox.Show(error.Message + "\n\n日志：" + LogDirectory, "USB Tablet Display", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    internal static string ValidateTarget(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.IndexOfAny(new[] { '"', '\r', '\n' }) >= 0)
            throw new InvalidOperationException("安装目录无效。");
        string target = Path.GetFullPath(value).TrimEnd(Path.DirectorySeparatorChar);
        string root = Path.GetPathRoot(target).TrimEnd(Path.DirectorySeparatorChar);
        if (target.Equals(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("不能安装到磁盘根目录。");
        foreach (string reserved in new[] { Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) })
            if (target.Equals(reserved.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("请选择专用的应用子目录。");
        return target;
    }

    internal static string Quote(string value) { return "\"" + value.TrimEnd('\\') + "\""; }

    internal static void WriteLog(string message)
    {
        try
        {
            Directory.CreateDirectory(LogDirectory);
            File.AppendAllText(Path.Combine(LogDirectory, "installer.log"), DateTime.Now.ToString("s") + " " + message + Environment.NewLine, Encoding.UTF8);
        }
        catch { }
        Progress(message);
    }

    private static void RunPowerShell(string script, string arguments)
    {
        string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe");
        using (Process process = new Process())
        {
            process.StartInfo = new ProcessStartInfo(powershell,
                "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(script) + " " + arguments)
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) WriteLog(e.Data); };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) WriteLog(e.Data); };
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.WaitForExit();
            if (process.ExitCode != 0) throw new InvalidOperationException("安装步骤失败（代码 " + process.ExitCode + "）。请查看安装日志。");
        }
    }

    internal static void Execute(string target)
    {
        WriteLog((Remove ? "Uninstalling " : "Installing ") + Version + " at " + target);
        if (Remove)
        {
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(RegistryPath))
            {
                if (key == null || !target.Equals(Convert.ToString(key.GetValue("InstallLocation")), StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("卸载目录与系统安装记录不一致。");
            }
            string marker = Path.Combine(target, "installed-product.json");
            if (!File.Exists(marker)) throw new InvalidOperationException("未找到应用安装标记，已停止清理。");
            RunPowerShell(Path.Combine(target, "Uninstall-Product.ps1"), "-InstallDirectory " + Quote(target));
            // Keep a retryable uninstall entry and ownership marker until all
            // payload files are gone, including when another process locks one.
            DeleteProductFiles(target);
            string state = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "USB Tablet Display", "install-state.json");
            if (File.Exists(state)) File.Delete(state);
            Registry.LocalMachine.DeleteSubKeyTree(RegistryPath, false);
            WriteLog("Uninstall completed. Shared Microsoft runtimes were retained.");
            return;
        }

        string temporary = Path.Combine(Path.GetTempPath(), "USBTabletDisplay-Setup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temporary);
        try
        {
            WriteLog("Extracting embedded offline payload...");
            Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip");
            if (stream == null) throw new InvalidOperationException("安装器缺少应用载荷。");
            using (stream)
            using (ZipArchive archive = new ZipArchive(stream, ZipArchiveMode.Read))
            {
                string prefix = Path.GetFullPath(temporary).TrimEnd('\\') + "\\";
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string path = Path.GetFullPath(Path.Combine(temporary, entry.FullName.Replace('/', '\\')));
                    if (!path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("安装载荷目录无效。");
                    if (entry.Name.Length == 0) Directory.CreateDirectory(path);
                    else
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(path));
                        using (Stream input = entry.Open())
                        using (FileStream output = File.Create(path)) input.CopyTo(output);
                    }
                }
            }
            RunPowerShell(Path.Combine(temporary, "Install-Product.ps1"), "-InstallDirectory " + Quote(target));
            WriteLog("Installation completed.");
        }
        finally
        {
            if (Directory.Exists(temporary)) Directory.Delete(temporary, true);
        }
    }

    internal static void DeleteProductFiles(string target)
    {
        string[] recoveryNames = { "installed-product.json", "Uninstall.exe", "Uninstall-Product.ps1" };
        var recovery = new System.Collections.Generic.Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        foreach (string name in recoveryNames)
        {
            string path = Path.Combine(target, name);
            if (File.Exists(path)) recovery.Add(path, File.ReadAllBytes(path));
        }
        try
        {
            foreach (string directory in Directory.GetDirectories(target, "*", SearchOption.AllDirectories))
                if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("安装目录包含链接，已保留卸载入口，请人工检查。");
            foreach (string path in Directory.GetFiles(target, "*", SearchOption.AllDirectories))
                if (!recovery.ContainsKey(path)) File.Delete(path);
            foreach (string directory in Directory.GetDirectories(target)) Directory.Delete(directory, true);
            foreach (string path in recovery.Keys) File.Delete(path);
            Directory.Delete(target);
        }
        catch
        {
            foreach (var entry in recovery)
            {
                try { if (!File.Exists(entry.Key)) File.WriteAllBytes(entry.Key, entry.Value); }
                catch (Exception restoreError) { WriteLog("Could not restore uninstall recovery file: " + restoreError.Message); }
            }
            throw new IOException("有文件正在使用或无法删除。卸载入口与安装记录已保留，请关闭占用程序后重试卸载。");
        }
    }
}

internal sealed class SetupForm : Form
{
    private readonly TextBox directory = new TextBox();
    private readonly TextBox details = new TextBox();
    private readonly Button action = new Button();
    private readonly ProgressBar progress = new ProgressBar();
    private readonly Button browse = new Button();
    private bool running;
    private bool finished;
    internal int Result = 1;

    internal SetupForm(string target)
    {
        Text = "USB Tablet Display " + Installer.Version + (Installer.Remove ? " 卸载" : " 安装");
        ClientSize = new Size(680, 455);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10F);
        Label title = new Label { Text = Installer.Remove ? "卸载 USB Tablet Display" : "安装 USB 平板扩展屏", Location = new Point(26, 20), Size = new Size(620, 36), Font = new Font(Font.FontFamily, 18F, FontStyle.Bold) };
        Label description = new Label { Text = Installer.Remove ? "将移除应用、项目驱动及本安装器新增的证书信任。" : "自动配置 ADB、Microsoft 运行库与虚拟显示驱动。\n开发预览版：安装驱动会信任随包提供的项目测试证书。", Location = new Point(28, 65), Size = new Size(620, 52) };
        directory.Text = target;
        directory.SetBounds(28, 131, 515, 30);
        directory.Enabled = !Installer.Remove;
        browse.Text = "浏览…";
        browse.SetBounds(552, 129, 98, 32);
        browse.Enabled = !Installer.Remove;
        browse.Click += delegate { using (FolderBrowserDialog dialog = new FolderBrowserDialog()) { dialog.SelectedPath = directory.Text; if (dialog.ShowDialog(this) == DialogResult.OK) directory.Text = dialog.SelectedPath; } };
        details.Multiline = true;
        details.ReadOnly = true;
        details.ScrollBars = ScrollBars.Vertical;
        details.SetBounds(28, 178, 622, 186);
        details.Text = Installer.Remove ? "点击卸载开始。Microsoft 共享运行库会保留。" : "Windows 10 22H2 / Windows 11 x64\r\n安装后连接 Android 平板，允许 USB 调试，再点击“启动扩展屏”。\r\n安装过程可离线进行；无需 Visual Studio、WDK 或 Android SDK。";
        progress.SetBounds(28, 380, 622, 15);
        action.Text = Installer.Remove ? "卸载" : "安装";
        action.SetBounds(532, 409, 118, 32);
        action.Click += async delegate
        {
            if (finished) { Close(); return; }
            running = true; action.Enabled = false; directory.Enabled = false; browse.Enabled = false;
            progress.Style = ProgressBarStyle.Marquee;
            Installer.Progress = delegate(string text) { if (!IsDisposed) BeginInvoke((Action)delegate { details.AppendText("\r\n" + text); }); };
            try
            {
                string selected = Installer.ValidateTarget(directory.Text);
                await Task.Run(delegate { Installer.Execute(selected); });
                Result = 0; progress.Style = ProgressBarStyle.Blocks; progress.Value = 100;
                details.AppendText(Installer.Remove ? "\r\n卸载完成。" : "\r\n安装完成。请从桌面快捷方式启动 USB Tablet Display。首次连接仍需在平板允许 USB 调试。若日志要求重启，请先重启电脑。");
            }
            catch (Exception error) { Installer.WriteLog("FAILED: " + error); details.AppendText("\r\n失败：" + error.Message + "\r\n日志：" + Installer.LogDirectory); progress.Style = ProgressBarStyle.Blocks; }
            finally { running = false; finished = true; action.Text = "关闭"; action.Enabled = true; }
        };
        FormClosing += delegate(object sender, FormClosingEventArgs e) { if (running) e.Cancel = true; };
        Controls.AddRange(new Control[] { title, description, directory, browse, details, progress, action });
    }
}
