package com.example.tabletdisplay.ui.settings

import android.app.Activity

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.tabletdisplay.ui.DisplayPreferences
import com.example.tabletdisplay.ui.InputMode
import com.example.tabletdisplay.ui.QualityPreset
import com.example.tabletdisplay.ui.components.SectionCard
import com.example.tabletdisplay.ui.components.SettingSwitch
import com.example.tabletdisplay.ui.components.TabletTopBar
import kotlin.math.roundToInt

@Composable
fun SettingsScreen(
  preferences: DisplayPreferences,
  onPreferencesChange: (DisplayPreferences) -> Unit,
  onBack: () -> Unit,
  modifier: Modifier = Modifier,
) {
  @Suppress("DEPRECATION")
  val display = (LocalContext.current as? Activity)?.windowManager?.defaultDisplay
  val rates = display?.supportedModes?.map { it.refreshRate.roundToInt() }?.distinct()?.sorted().orEmpty()
  val highRefreshSupported = rates.any { it >= 90 }
  Column(modifier = modifier.fillMaxSize().safeDrawingPadding()) {
    TabletTopBar("设置", onBack)
    Column(
      modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      SectionCard(title = "输入模式") {
        InputMode.entries.forEach { mode ->
          Row(
            modifier =
              Modifier.fillMaxWidth().selectable(
                selected = preferences.inputMode == mode,
                enabled = mode != InputMode.Touchpad,
                onClick = { onPreferencesChange(preferences.copy(inputMode = mode)) },
              ),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            RadioButton(
              enabled = mode != InputMode.Touchpad,
              selected = preferences.inputMode == mode,
              onClick = { onPreferencesChange(preferences.copy(inputMode = mode)) },
            )
            Column(modifier = Modifier.padding(start = 8.dp)) {
              Text(mode.title, fontWeight = FontWeight.Medium)
              Text(mode.description, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            }
          }
        }
      }

      SectionCard(title = "触控与手势") {
        SettingSwitch(
          title = "允许控制电脑",
          description = "关闭后平板只显示画面",
          checked = preferences.touchEnabled,
          onCheckedChange = { onPreferencesChange(preferences.copy(touchEnabled = it)) },
        )
        SettingSwitch(
          title = "自然滚动",
          description = "此独立开关尚未接入，原生触控手势由 Windows 应用处理",
          checked = preferences.naturalScrolling,
          onCheckedChange = { onPreferencesChange(preferences.copy(naturalScrolling = it)) },
          enabled = false,
        )
        SettingSwitch(
          title = "双指缩放",
          description = "此独立开关尚未接入，原生触控手势由 Windows 应用处理",
          checked = preferences.pinchToZoom,
          onCheckedChange = { onPreferencesChange(preferences.copy(pinchToZoom = it)) },
          enabled = false,
        )
      }

      SectionCard(title = "画质预设") {
        Text("请在电脑端选择分辨率、帧率或码率，然后点击“应用设置”。平板端画质控制尚未接入。", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          QualityPreset.entries.forEach { preset ->
            FilterChip(
              enabled = false,
              selected = preferences.qualityPreset == preset,
              onClick = { onPreferencesChange(preferences.copy(qualityPreset = preset)) },
              label = { Text(preset.title) },
              modifier = Modifier.weight(1f),
            )
          }
        }
      }

      SectionCard(title = "显示") {
        SettingSwitch(
          title = "优先高刷新率（目标 120 Hz）",
          description = "仅调整平板本机屏幕，不改变电脑编码帧率。屏幕报告的模式：${rates.joinToString(" / ")} Hz" + if (highRefreshSupported) "" else "；未检测到高刷新率支持",
          checked = preferences.prefer120Hz && highRefreshSupported,
          enabled = highRefreshSupported,
          onCheckedChange = { onPreferencesChange(preferences.copy(prefer120Hz = it)) },
        )
        SettingSwitch(
          title = "保持屏幕常亮",
          description = "显示 Windows 画面时不自动熄屏",
          checked = preferences.keepScreenOn,
          onCheckedChange = { onPreferencesChange(preferences.copy(keepScreenOn = it)) },
        )
        SettingSwitch(
          title = "锁定当前方向",
          description = "锁定平板应用方向；Windows 副屏方向由电脑设置",
          checked = preferences.rotationLocked,
          onCheckedChange = { onPreferencesChange(preferences.copy(rotationLocked = it)) },
        )
        SettingSwitch(
          title = "显示性能浮层",
          description = "在画面左上角显示分辨率、帧率和连接状态",
          checked = preferences.showPerformanceOverlay,
          onCheckedChange = { onPreferencesChange(preferences.copy(showPerformanceOverlay = it)) },
        )
      }

      SectionCard(title = "连接") {
        SettingSwitch(
          title = "自动连接",
          description = "此开关尚未接入，请从电脑端启动连接",
          enabled = false,
          checked = preferences.autoConnect,
          onCheckedChange = { onPreferencesChange(preferences.copy(autoConnect = it)) },
        )
        Text("当前连接方式：ADB 开发通道", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
      }
    }
  }
}
