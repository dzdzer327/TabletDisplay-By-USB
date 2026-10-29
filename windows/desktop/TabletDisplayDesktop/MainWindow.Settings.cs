using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace TabletDisplayDesktop
{
    public partial class MainWindow
    {
        private readonly string settingsFilePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "USB Tablet Display", "settings.ini");
        private bool settingsReady;
        private bool syncingSettings;
        private bool operationBusy;
        private SessionPreferences preferences;
        private static readonly int[] ModeWidths = { 1280, 1920, 1920, 2560 };
        private static readonly int[] ModeHeights = { 720, 1080, 1200, 1600 };
        private static readonly int[] FrameRates = { 30, 60, 120 };

        private void InitializeSessionSettings()
        {
            preferences = SessionPreferences.Load(settingsFilePath);
            LoadSettingsControls(preferences);
            settingsReady = true;
            DisablePreviewControls(this);
        }

        private void LoadSettingsControls(SessionPreferences settings)
        {
            syncingSettings = true;
            try
            {
                int mode = 2;
                for (int index = 0; index < ModeWidths.Length; index++)
                    if (ModeWidths[index] == settings.Width && ModeHeights[index] == settings.Height) mode = index;
                QuickResolutionCombo.SelectedIndex = DisplayResolutionCombo.SelectedIndex = mode;
                QuickFpsCombo.SelectedIndex = StreamFpsCombo.SelectedIndex = Array.IndexOf(FrameRates, settings.FrameRate);
                DisplayRefreshCombo.SelectedIndex = settings.RefreshRate == 120 ? 1 : 0;
                TargetBitrateSlider.Value = settings.BitrateMbps;
                QuickTouchCombo.SelectedIndex = settings.TouchEnabled ? 0 : 1;
                TouchEnabledBox.IsChecked = settings.TouchEnabled;
                PresetBalanced.IsChecked = settings.Preset == 0;
                PresetLatency.IsChecked = settings.Preset == 1;
                PresetQuality.IsChecked = settings.Preset == 2;
                PresetPower.IsChecked = settings.Preset == 3;
            }
            finally { syncingSettings = false; }
        }

        private void SettingsChoiceChanged(object sender, SelectionChangedEventArgs e)
        {
            if (!settingsReady || syncingSettings) return;
            syncingSettings = true;
            try
            {
                if (sender == QuickResolutionCombo) DisplayResolutionCombo.SelectedIndex = QuickResolutionCombo.SelectedIndex;
                if (sender == DisplayResolutionCombo) QuickResolutionCombo.SelectedIndex = DisplayResolutionCombo.SelectedIndex;
                if (sender == QuickFpsCombo) StreamFpsCombo.SelectedIndex = QuickFpsCombo.SelectedIndex;
                if (sender == StreamFpsCombo) QuickFpsCombo.SelectedIndex = StreamFpsCombo.SelectedIndex;
                if ((sender == QuickFpsCombo || sender == StreamFpsCombo) && StreamFpsCombo.SelectedIndex == 2)
                    DisplayRefreshCombo.SelectedIndex = 1;
                if (sender == DisplayRefreshCombo && DisplayRefreshCombo.SelectedIndex == 0 && StreamFpsCombo.SelectedIndex == 2)
                    QuickFpsCombo.SelectedIndex = StreamFpsCombo.SelectedIndex = 1;
                if (sender == QuickTouchCombo) TouchEnabledBox.IsChecked = QuickTouchCombo.SelectedIndex == 0;
                ClearPresetSelection();
            }
            finally { syncingSettings = false; }
            PendingSettingsText.Text = "有未应用的更改；点击“应用设置”，或下次启动扩展屏时应用。";
        }

        private void BitrateChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (!settingsReady || syncingSettings) return;
            ClearPresetSelection();
            PendingSettingsText.Text = "目标码率已更改；点击“应用设置”生效。";
        }

        private void TouchEnabledChanged(object sender, RoutedEventArgs e)
        {
            if (!settingsReady || syncingSettings) return;
            syncingSettings = true;
            QuickTouchCombo.SelectedIndex = TouchEnabledBox.IsChecked == true ? 0 : 1;
            syncingSettings = false;
            PendingSettingsText.Text = "触控设置已更改；点击首页、显示或画质页的“应用设置”生效。";
        }

        private void ClearPresetSelection()
        {
            PresetBalanced.IsChecked = PresetLatency.IsChecked = PresetQuality.IsChecked = PresetPower.IsChecked = false;
        }

        private void PresetChanged(object sender, RoutedEventArgs e)
        {
            if (!settingsReady || syncingSettings) return;
            SessionPreferences next = ReadSettingsControls();
            next.Preset = sender == PresetLatency ? 1 : sender == PresetQuality ? 2 : sender == PresetPower ? 3 : 0;
            next.FrameRate = next.Preset == 1 ? 120 : next.Preset == 3 ? 30 : 60;
            next.RefreshRate = next.FrameRate == 120 ? 120 : 60;
            next.BitrateMbps = next.Preset == 1 ? 12 : next.Preset == 2 ? 24 : next.Preset == 3 ? 6 : 8;
            LoadSettingsControls(next);
            PendingSettingsText.Text = "预设已选中；点击“应用设置”生效。";
        }

        private void RestoreSettings_Click(object sender, RoutedEventArgs e)
        {
            LoadSettingsControls(new SessionPreferences());
            PendingSettingsText.Text = "已恢复推荐值（60 Hz / 60fps / 8 Mbps），点击“应用设置”生效。";
        }

        private SessionPreferences ReadSettingsControls()
        {
            int mode = Math.Max(0, DisplayResolutionCombo.SelectedIndex);
            return new SessionPreferences
            {
                Width = ModeWidths[mode], Height = ModeHeights[mode],
                RefreshRate = DisplayRefreshCombo.SelectedIndex == 1 ? 120 : 60,
                FrameRate = FrameRates[Math.Max(0, StreamFpsCombo.SelectedIndex)],
                BitrateMbps = (int)Math.Round(TargetBitrateSlider.Value),
                TouchEnabled = TouchEnabledBox.IsChecked == true,
                Preset = PresetBalanced.IsChecked == true ? 0 : PresetLatency.IsChecked == true ? 1 :
                    PresetQuality.IsChecked == true ? 2 : PresetPower.IsChecked == true ? 3 : -1,
                Revision = preferences == null ? 0 : preferences.Revision
            };
        }

        private SessionPreferences SaveSettingsControls()
        {
            SessionPreferences selected = ReadSettingsControls();
            selected.Save(settingsFilePath);
            preferences = selected;
            return selected;
        }

        private async void ApplySettings_Click(object sender, RoutedEventArgs e)
        {
            SetBusy(true, "正在应用设置；视频会短暂重连，虚拟显示器保持连接…");
            try
            {
                SessionPreferences selected = SaveSettingsControls();
                if (IsControllerRunning())
                {
                    await WaitForSettingsAsync(selected);
                    FooterStatusText.Text = "设置已生效：" + DescribeSettings(selected);
                    PendingSettingsText.Text = "控制器已确认此设置。";
                }
                else
                {
                    FooterStatusText.Text = "设置已保存，下次启动扩展屏时生效。";
                    PendingSettingsText.Text = FooterStatusText.Text;
                }
            }
            catch (Exception error) { PendingSettingsText.Text = "设置未确认：" + error.Message; ShowError(error.Message, "应用设置失败"); }
            finally { SetBusy(false, null); }
        }

        private async Task WaitForSettingsAsync(SessionPreferences selected)
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(45);
            long lastError = 0;
            while (DateTime.UtcNow < deadline && IsControllerRunning())
            {
                RuntimeStatus runtime = ReadRuntimeStatus();
                if (runtime != null && runtime.RequestedRevision == selected.Revision)
                {
                    if (runtime.SettingsError != 0)
                        throw new InvalidOperationException("Windows 未接受显示模式（代码 " + runtime.SettingsError + "）。请尝试 1920×1080 / 60 Hz，并检查驱动版本。");
                    if (runtime.LastError != 0) lastError = runtime.LastError;
                    if (runtime.StreamRevision == selected.Revision && runtime.TargetFps == selected.FrameRate &&
                        runtime.TargetBitrate == selected.BitrateMbps * 1000000 && runtime.DisplayHz == selected.RefreshRate && runtime.LastError == 0) return;
                }
                await Task.Delay(250);
            }
            throw new TimeoutException(lastError != 0 ? "编码会话未能恢复：0x" + lastError.ToString("X") + "，请降低分辨率或帧率后重新应用。" :
                "控制器未确认设置。请停止扩展屏后使用新版重新连接；若仍失败，请查看诊断日志。");
        }

        private static string DescribeSettings(SessionPreferences selected)
        {
            return selected.Width + "×" + selected.Height + " · " + selected.RefreshRate + " Hz · 编码上限 " +
                selected.FrameRate + "fps · " + selected.BitrateMbps + " Mbps";
        }

        private static void DisablePreviewControls(DependencyObject root)
        {
            FrameworkElement control = root as FrameworkElement;
            if ((root is ComboBox || root is CheckBox || root is RadioButton || root is Slider) &&
                control != null && string.IsNullOrEmpty(control.Name))
            {
                control.IsEnabled = false;
                control.ToolTip = "此选项尚未接入。显示排列、方向和缩放请在 Windows 显示设置中调整。";
            }
            foreach (object child in LogicalTreeHelper.GetChildren(root))
            {
                DependencyObject dependency = child as DependencyObject;
                if (dependency != null) DisablePreviewControls(dependency);
            }
        }
    }
}
