package com.example.tabletdisplay.ui.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.tabletdisplay.R
import com.example.tabletdisplay.decoder.ReceiverStatus
import com.example.tabletdisplay.theme.TabletBlueLight
import com.example.tabletdisplay.theme.TabletSuccess
import com.example.tabletdisplay.theme.TabletWarning
import com.example.tabletdisplay.ui.components.StatusPill

@Composable
fun ConnectionHomeScreen(
  lastStatus: ReceiverStatus,
  onStartDisplay: () -> Unit,
  onOpenSettings: () -> Unit,
  onOpenDiagnostics: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val (statusText, statusColor) =
    when (lastStatus) {
      is ReceiverStatus.Decoding -> "上次会话已连接" to TabletSuccess
      is ReceiverStatus.Connected -> "电脑已连接" to TabletSuccess
      is ReceiverStatus.Error -> "需要检查连接" to MaterialTheme.colorScheme.error
      ReceiverStatus.Starting -> "正在准备" to TabletWarning
      is ReceiverStatus.Waiting -> "等待电脑" to TabletBlueLight
      ReceiverStatus.Stopped -> "显示已暂停" to TabletWarning
    }

  Box(
    modifier =
      modifier
        .fillMaxSize()
        .background(
          Brush.radialGradient(
            colors = listOf(Color(0xFF163247), Color(0xFF0D1B2A)),
            radius = 1200f,
          )
        )
        .padding(24.dp),
  ) {
    Row(modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter), verticalAlignment = Alignment.CenterVertically) {
      Image(painter = painterResource(R.drawable.ic_launcher_foreground_generated), contentDescription = null, modifier = Modifier.size(48.dp))
      Column(modifier = Modifier.padding(start = 10.dp).weight(1f)) {
        Text("USB Tablet Display", color = Color.White, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Text("USB 平板扩展屏", color = Color(0xFFAFC0CE), style = MaterialTheme.typography.bodySmall)
      }
      OutlinedButton(onClick = onOpenSettings) { Text("设置") }
    }

    Column(
      modifier = Modifier.align(Alignment.Center).widthIn(max = 520.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
    ) {
      Box(
        modifier = Modifier.size(160.dp).background(Color(0xFF153A52), RoundedCornerShape(38.dp)),
        contentAlignment = Alignment.Center,
      ) {
        Image(
          painter = painterResource(R.drawable.ic_launcher_foreground_generated),
          contentDescription = "USB Tablet Display",
          modifier = Modifier.size(132.dp),
        )
      }
      Spacer(Modifier.height(24.dp))
      StatusPill(statusText, statusColor)
      Spacer(Modifier.height(18.dp))
      Text("准备连接 Windows 电脑", color = Color.White, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
      Text(
        "请连接支持数据传输的 USB 线，并在电脑端打开 USB Tablet Display。当前开发版本需要 USB 调试授权。",
        color = Color(0xFFB6C4CF),
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        modifier = Modifier.padding(top = 12.dp),
      )
      Spacer(Modifier.height(26.dp))
      Button(onClick = onStartDisplay, modifier = Modifier.fillMaxWidth().height(52.dp)) {
        Text("进入扩展屏", fontWeight = FontWeight.SemiBold)
      }
      OutlinedButton(onClick = onOpenDiagnostics, modifier = Modifier.fillMaxWidth().padding(top = 10.dp).height(50.dp)) {
        Text("测试连接")
      }
    }

    Row(
      modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth(),
      horizontalArrangement = Arrangement.Center,
    ) {
      Text("视频 27183  ·  输入 27184  ·  仅监听本机回环", color = Color(0xFF75899A), style = MaterialTheme.typography.labelSmall)
    }
  }
}
