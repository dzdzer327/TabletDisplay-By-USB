package com.example.tabletdisplay.ui.diagnostics

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.view.WindowManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.example.tabletdisplay.decoder.ReceiverStatus
import com.example.tabletdisplay.theme.TabletSuccess
import com.example.tabletdisplay.theme.TabletWarning
import com.example.tabletdisplay.ui.DisplayPreferences
import com.example.tabletdisplay.ui.components.DiagnosticRow
import com.example.tabletdisplay.ui.components.SectionCard
import com.example.tabletdisplay.ui.components.TabletTopBar

@Composable
fun DiagnosticsScreen(
  status: ReceiverStatus,
  preferences: DisplayPreferences,
  onBack: () -> Unit,
  onRetry: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val context = LocalContext.current
  val connected = status is ReceiverStatus.Connected || status is ReceiverStatus.Decoding
  val decoding = status as? ReceiverStatus.Decoding
  val hasError = status is ReceiverStatus.Error
  val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
  @Suppress("DEPRECATION")
  val refreshRate = windowManager.defaultDisplay.refreshRate
  val statusDescription = statusDescription(status)
  val summary =
    buildString {
      appendLine("USB Tablet Display Android 诊断摘要")
      appendLine("设备：${Build.MANUFACTURER} ${Build.MODEL}")
      appendLine("Android：${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT}")
      appendLine("屏幕刷新率：${"%.0f".format(refreshRate)} Hz")
      appendLine("接收状态：$statusDescription")
      if (decoding != null) appendLine("视频：${decoding.width}×${decoding.height}，已呈现 ${decoding.frameCount} 帧")
      appendLine("触控：${if (preferences.touchEnabled) preferences.inputMode.title else "关闭"}")
      appendLine("画质偏好：${preferences.qualityPreset.title}")
      appendLine("视频端口：27183；输入端口：27184")
    }

  Column(modifier = modifier.fillMaxSize().safeDrawingPadding()) {
    TabletTopBar("连接测试与诊断", onBack)
    Column(
      modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      SectionCard(title = "连接测试") {
        DiagnosticRow("Android 应用", "运行正常", TabletSuccess)
        DiagnosticRow("视频监听端口", "27183 已配置", TabletSuccess)
        DiagnosticRow("Windows 视频连接", if (connected) "已连接" else "等待连接", if (connected) TabletSuccess else TabletWarning)
        DiagnosticRow("硬件解码", if (decoding != null) "正在呈现" else "等待视频", if (decoding != null) TabletSuccess else TabletWarning)
        DiagnosticRow("触控回传", if (preferences.touchEnabled) "${preferences.inputMode.title}已开启" else "已关闭", if (preferences.touchEnabled) TabletSuccess else Color.Gray)
        if (hasError) {
          Text(
            "错误：${status.message}",
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodyMedium,
          )
        }
      }

      SectionCard(title = "实时信息") {
        DiagnosticValue("连接状态", statusDescription)
        DiagnosticValue("当前视频", decoding?.let { "${it.width} × ${it.height}" } ?: "--")
        DiagnosticValue("累计呈现", decoding?.let { "${it.frameCount} 帧" } ?: "--")
        DiagnosticValue("屏幕刷新率", "${"%.0f".format(refreshRate)} Hz")
        DiagnosticValue("设备", "${Build.MANUFACTURER} ${Build.MODEL}")
        DiagnosticValue("系统", "Android ${Build.VERSION.RELEASE} · API ${Build.VERSION.SDK_INT}")
      }

      SectionCard(title = "诊断摘要") {
        Text(summary, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
          OutlinedButton(
            onClick = {
              val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
              clipboard.setPrimaryClip(ClipData.newPlainText("USB Tablet Display diagnostics", summary))
            },
            modifier = Modifier.weight(1f),
          ) {
            Text("复制摘要")
          }
          Button(onClick = onRetry, modifier = Modifier.weight(1f)) { Text("返回并重试") }
        }
      }
    }
  }
}

@Composable
private fun DiagnosticValue(label: String, value: String) {
  Row(modifier = Modifier.fillMaxWidth()) {
    Text(label, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
    Text(value)
  }
}

private fun statusDescription(status: ReceiverStatus): String =
  when (status) {
    ReceiverStatus.Starting -> "正在启动"
    is ReceiverStatus.Waiting -> "等待 Windows 连接"
    is ReceiverStatus.Connected -> "已连接，等待关键帧"
    is ReceiverStatus.Decoding -> "正在显示 Windows 副屏"
    is ReceiverStatus.Error -> "连接错误"
    ReceiverStatus.Stopped -> "已暂停"
  }
