package com.example.tabletdisplay.ui.display

import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.example.tabletdisplay.decoder.H264StreamReceiver
import com.example.tabletdisplay.decoder.ReceiverStatus

@Composable
fun TabletDisplayScreen(modifier: Modifier = Modifier) {
  var status by remember { mutableStateOf<ReceiverStatus>(ReceiverStatus.Starting) }
  val mainHandler = remember { Handler(Looper.getMainLooper()) }
  var receiver by remember { mutableStateOf<H264StreamReceiver?>(null) }

  DisposableEffect(Unit) {
    onDispose {
      receiver?.stop()
      receiver = null
    }
  }

  Box(modifier = modifier.fillMaxSize().background(Color.Black)) {
    AndroidView(
      factory = { context ->
        SurfaceView(context).apply {
          holder.addCallback(
            object : SurfaceHolder.Callback {
              override fun surfaceCreated(holder: SurfaceHolder) {
                receiver?.stop()
                receiver =
                  H264StreamReceiver(holder.surface) { newStatus ->
                      mainHandler.post { status = newStatus }
                    }
                    .also { it.start() }
              }

              override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

              override fun surfaceDestroyed(holder: SurfaceHolder) {
                receiver?.stop()
                receiver = null
              }
            }
          )
        }
      },
      modifier = Modifier.fillMaxSize(),
    )

    StatusOverlay(
      status = status,
      modifier = Modifier.align(Alignment.Center),
    )
  }
}

@Composable
private fun StatusOverlay(status: ReceiverStatus, modifier: Modifier = Modifier) {
  if (status is ReceiverStatus.Decoding && status.frameCount > 0) return

  val (title, detail) =
    when (status) {
      ReceiverStatus.Starting -> "正在启动" to "准备视频解码器"
      is ReceiverStatus.Waiting -> "等待电脑画面" to "ADB 视频端口：${status.port}"
      is ReceiverStatus.Connected -> "电脑已连接" to "等待 H.264 关键帧"
      is ReceiverStatus.Decoding -> "正在解码" to "${status.width} × ${status.height} · ${status.frameCount} 帧"
      is ReceiverStatus.Error -> "连接错误" to status.message
      ReceiverStatus.Stopped -> "显示已暂停" to "请保持应用位于前台"
    }

  Column(
    modifier =
      modifier
        .background(Color(0xCC111111), RoundedCornerShape(16.dp))
        .padding(horizontal = 28.dp, vertical = 22.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Text(text = title, color = Color.White, style = MaterialTheme.typography.titleLarge)
    Text(text = detail, color = Color(0xFFBDBDBD), style = MaterialTheme.typography.bodyMedium)
  }
}
