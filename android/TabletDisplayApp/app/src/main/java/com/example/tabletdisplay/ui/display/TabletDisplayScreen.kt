package com.example.tabletdisplay.ui.display

import android.content.Context
import android.app.Activity
import android.content.pm.ActivityInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.WindowManager
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.inputmethod.InputMethodManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.example.tabletdisplay.R
import com.example.tabletdisplay.decoder.H264StreamReceiver
import com.example.tabletdisplay.decoder.ReceiverStatus
import com.example.tabletdisplay.input.TouchInputSender
import com.example.tabletdisplay.theme.TabletBlueLight
import com.example.tabletdisplay.theme.TabletSuccess
import com.example.tabletdisplay.theme.TabletWarning
import com.example.tabletdisplay.ui.DisplayPreferences
import com.example.tabletdisplay.ui.InputMode
import com.example.tabletdisplay.ui.QualityPreset
import kotlinx.coroutines.delay
import kotlin.math.abs

@Composable
fun TabletDisplayScreen(
  preferences: DisplayPreferences,
  onPreferencesChange: (DisplayPreferences) -> Unit,
  onStatusChanged: (ReceiverStatus) -> Unit,
  onOpenSettings: () -> Unit,
  onOpenDiagnostics: () -> Unit,
  onDisconnect: () -> Unit,
  modifier: Modifier = Modifier,
) {
  var status by remember { mutableStateOf<ReceiverStatus>(ReceiverStatus.Starting) }
  val mainHandler = remember { Handler(Looper.getMainLooper()) }
  var receiver by remember { mutableStateOf<H264StreamReceiver?>(null) }
  val touchInputSender = remember { TouchInputSender() }
  var controlsVisible by remember { mutableStateOf(false) }
  var displayedFps by remember { mutableDoubleStateOf(0.0) }
  var previousFrameCount by remember { mutableLongStateOf(0L) }
  var previousFrameTime by remember { mutableLongStateOf(System.nanoTime()) }
  var videoAspect by remember { mutableStateOf(16f / 10f) }
  val context = LocalContext.current
  val view = LocalView.current
  val prefer120Hz by rememberUpdatedState(preferences.prefer120Hz)

  DisposableEffect(Unit) {
    touchInputSender.start()
    onDispose {
      receiver?.stop()
      receiver = null
      touchInputSender.stop()
    }
  }

  DisposableEffect(preferences.keepScreenOn, preferences.rotationLocked) {
    view.keepScreenOn = preferences.keepScreenOn
    val activity = context as? Activity
    activity?.requestedOrientation =
      if (preferences.rotationLocked) ActivityInfo.SCREEN_ORIENTATION_LOCKED
      else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    onDispose {
      view.keepScreenOn = false
    }
  }

  DisposableEffect(preferences.prefer120Hz) {
    val activity = context as? Activity
    val window = activity?.window
    val originalModeId = window?.attributes?.preferredDisplayModeId ?: 0
    val originalRefreshRate = window?.attributes?.preferredRefreshRate ?: 0f

    if (preferences.prefer120Hz && activity != null && window != null) {
      @Suppress("DEPRECATION")
      val requestedMode =
        activity.windowManager.defaultDisplay.supportedModes
          .filter { it.refreshRate >= 90f }
          .minByOrNull { abs(it.refreshRate - 120f) }

      if (requestedMode != null) {
        val attributes = window.attributes
        attributes.preferredDisplayModeId = requestedMode.modeId
        attributes.preferredRefreshRate = requestedMode.refreshRate
        window.attributes = attributes
      }
    }

    onDispose {
      if (window != null) {
        val attributes = window.attributes
        attributes.preferredDisplayModeId = originalModeId
        attributes.preferredRefreshRate = originalRefreshRate
        window.attributes = attributes
      }
    }
  }

  LaunchedEffect(status) {
    val now = System.nanoTime()
    val decoding = status as? ReceiverStatus.Decoding
    if (decoding == null || decoding.frameCount < previousFrameCount) {
      displayedFps = 0.0
      previousFrameCount = decoding?.frameCount ?: 0L
      previousFrameTime = now
      return@LaunchedEffect
    }
    val seconds = (now - previousFrameTime) / 1_000_000_000.0
    if (seconds >= 0.75) {
      displayedFps = (decoding.frameCount - previousFrameCount) / seconds
      previousFrameCount = decoding.frameCount
      previousFrameTime = now
    }
  }

  LaunchedEffect(controlsVisible) {
    if (controlsVisible) {
      delay(5000)
      controlsVisible = false
    }
  }

  BoxWithConstraints(modifier = modifier.fillMaxSize().background(Color.Black)) {
    val availableAspect = maxWidth / maxHeight
    val fittedWidth = if (availableAspect > videoAspect) maxHeight * videoAspect else maxWidth
    val fittedHeight = if (availableAspect > videoAspect) maxHeight else maxWidth / videoAspect
    AndroidView(
      factory = { viewContext ->
        SurfaceView(viewContext).apply {
          setOnTouchListener { view, event ->
            if (preferences.touchEnabled && preferences.inputMode == InputMode.NativeTouch) {
              touchInputSender.send(event, view.width, view.height)
            }
            true
          }
          holder.addCallback(
            object : SurfaceHolder.Callback {
              override fun surfaceCreated(holder: SurfaceHolder) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                  holder.surface.setFrameRate(
                    if (prefer120Hz) 120f else 0f,
                    Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                  )
                  tag = prefer120Hz
                }
                receiver?.stop()
                receiver =
                  H264StreamReceiver(
                      surface = holder.surface,
                      onStatus = { newStatus ->
                        mainHandler.post {
                          status = newStatus
                          if (newStatus is ReceiverStatus.Decoding && newStatus.width > 0 && newStatus.height > 0) {
                            videoAspect = newStatus.width.toFloat() / newStatus.height
                          }
                          onStatusChanged(newStatus)
                        }
                      },
                    )
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
      update = { view ->
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && view.holder.surface.isValid && view.tag != preferences.prefer120Hz) {
          view.holder.surface.setFrameRate(
            if (preferences.prefer120Hz) 120f else 0f,
            Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
          )
          view.tag = preferences.prefer120Hz
        }
        view.setOnTouchListener { _, event ->
          if (preferences.touchEnabled && preferences.inputMode == InputMode.NativeTouch) {
            touchInputSender.send(event, view.width, view.height)
          }
          true
        }
      },
      modifier = Modifier.size(fittedWidth, fittedHeight).align(Alignment.Center),
    )

    StatusOverlay(status = status, onDiagnostics = onOpenDiagnostics, modifier = Modifier.align(Alignment.Center))

    if (preferences.showPerformanceOverlay && status is ReceiverStatus.Decoding) {
      PerformanceOverlay(
        status = status as ReceiverStatus.Decoding,
        fps = displayedFps,
        touchEnabled = preferences.touchEnabled,
        modifier = Modifier.align(Alignment.TopStart).padding(14.dp),
      )
    }

    Surface(
      modifier =
        Modifier.align(Alignment.CenterEnd)
          .padding(end = 10.dp)
          .width(32.dp)
          .height(100.dp)
          .clickable { controlsVisible = !controlsVisible },
      color = Color(0xB30A84C6),
      shape = RoundedCornerShape(topStart = 12.dp, bottomStart = 12.dp),
    ) {
      Box(contentAlignment = Alignment.Center) {
        Text(if (controlsVisible) "›" else "‹", color = Color.White, style = MaterialTheme.typography.titleLarge)
      }
    }

    AnimatedVisibility(
      visible = controlsVisible,
      modifier = Modifier.align(Alignment.CenterEnd),
      enter = slideInHorizontally(initialOffsetX = { it }) + fadeIn(),
      exit = slideOutHorizontally(targetOffsetX = { it }) + fadeOut(),
    ) {
      QuickControlPanel(
        status = status,
        fps = displayedFps,
        preferences = preferences,
        onPreferencesChange = onPreferencesChange,
        onShowKeyboard = {
          val inputMethodManager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
          @Suppress("DEPRECATION")
          inputMethodManager.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
        },
        onOpenSettings = onOpenSettings,
        onOpenDiagnostics = onOpenDiagnostics,
        onDisconnect = onDisconnect,
      )
    }
  }
}

@Composable
private fun StatusOverlay(status: ReceiverStatus, onDiagnostics: () -> Unit, modifier: Modifier = Modifier) {
  if (status is ReceiverStatus.Decoding && status.frameCount > 0) return

  val (title, detail, color) =
    when (status) {
      ReceiverStatus.Starting -> Triple("正在启动", "准备视频解码器", TabletWarning)
      is ReceiverStatus.Waiting -> Triple("等待电脑画面", "请在 Windows 端点击“开始扩展屏”", TabletBlueLight)
      is ReceiverStatus.Connected -> Triple("电脑已连接", "等待 H.264 关键帧", TabletSuccess)
      is ReceiverStatus.Decoding -> Triple("正在解码", "${status.width} × ${status.height} · ${status.frameCount} 帧", TabletSuccess)
      is ReceiverStatus.Error -> Triple("连接出现问题", status.message, MaterialTheme.colorScheme.error)
      ReceiverStatus.Stopped -> Triple("显示已暂停", "返回连接首页可重新开始", TabletWarning)
    }

  Column(
    modifier =
      modifier
        .width(420.dp)
        .background(Brush.verticalGradient(listOf(Color(0xF21A2B39), Color(0xF20D1822))), RoundedCornerShape(26.dp))
        .padding(horizontal = 34.dp, vertical = 30.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Box(
      modifier = Modifier.size(100.dp).background(Color(0xFF153A52), RoundedCornerShape(25.dp)),
      contentAlignment = Alignment.Center,
    ) {
      Image(painter = painterResource(R.drawable.ic_launcher_foreground_generated), contentDescription = null, modifier = Modifier.size(84.dp))
    }
    Spacer(Modifier.height(20.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
      Spacer(Modifier.size(10.dp).background(color, CircleShape))
      Spacer(Modifier.width(9.dp))
      Text(title, color = Color.White, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
    }
    Text(
      detail,
      color = Color(0xFFB7C4CE),
      style = MaterialTheme.typography.bodyMedium,
      textAlign = TextAlign.Center,
      modifier = Modifier.padding(top = 10.dp),
    )
    Text("ADB 开发通道 · 视频端口 27183", color = Color(0xFF708797), style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(top = 14.dp))
    if (status is ReceiverStatus.Error) {
      OutlinedButton(onClick = onDiagnostics, modifier = Modifier.padding(top = 18.dp)) { Text("查看诊断") }
    }
  }
}

@Composable
private fun QuickControlPanel(
  status: ReceiverStatus,
  fps: Double,
  preferences: DisplayPreferences,
  onPreferencesChange: (DisplayPreferences) -> Unit,
  onShowKeyboard: () -> Unit,
  onOpenSettings: () -> Unit,
  onOpenDiagnostics: () -> Unit,
  onDisconnect: () -> Unit,
) {
  Surface(
    modifier = Modifier.width(280.dp).fillMaxHeight().padding(vertical = 16.dp, horizontal = 12.dp),
    color = Color(0xF2182734),
    shape = RoundedCornerShape(22.dp),
    tonalElevation = 8.dp,
  ) {
    Column(
      modifier = Modifier.fillMaxHeight().verticalScroll(rememberScrollState()).padding(20.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text("快捷控制", color = Color.White, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
      val decoding = status as? ReceiverStatus.Decoding
      Text(
        if (decoding != null) "${decoding.width} × ${decoding.height}  ·  ${"%.0f".format(fps)} fps" else "等待视频连接",
        color = if (decoding != null) TabletSuccess else TabletWarning,
        style = MaterialTheme.typography.bodyMedium,
      )

      QuickToggle("触控", preferences.touchEnabled, preferences.inputMode.title) {
        onPreferencesChange(preferences.copy(touchEnabled = !preferences.touchEnabled))
      }
      QuickToggle("旋转锁定", preferences.rotationLocked, "已锁定") {
        onPreferencesChange(preferences.copy(rotationLocked = !preferences.rotationLocked))
      }
      QuickToggle("性能浮层", preferences.showPerformanceOverlay, "已显示") {
        onPreferencesChange(preferences.copy(showPerformanceOverlay = !preferences.showPerformanceOverlay))
      }

      Text("画质预设", color = Color(0xFF8FA4B5), style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 4.dp))
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(QualityPreset.Auto, QualityPreset.LowLatency).forEach { preset ->
          OutlinedButton(enabled = false, onClick = {}, modifier = Modifier.weight(1f)) {
            Text(preset.title, color = if (preferences.qualityPreset == preset) TabletBlueLight else Color.White)
          }
        }
      }

      Text("画质与帧率请在电脑端应用设置", color = Color(0xFF8FA4B5), style = MaterialTheme.typography.bodySmall)
      Button(enabled = false, onClick = onShowKeyboard, modifier = Modifier.fillMaxWidth()) { Text("软键盘回传尚未接入") }
      OutlinedButton(onClick = onOpenSettings, modifier = Modifier.fillMaxWidth()) { Text("全部设置") }
      OutlinedButton(onClick = onOpenDiagnostics, modifier = Modifier.fillMaxWidth()) { Text("连接诊断") }
      OutlinedButton(onClick = onDisconnect, modifier = Modifier.fillMaxWidth()) {
        Text("断开并返回首页", color = Color(0xFFFFA6A6))
      }
    }
  }
}

@Composable
private fun QuickToggle(title: String, value: Boolean, enabledLabel: String, onClick: () -> Unit) {
  Surface(
    modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    color = if (value) Color(0xFF173F55) else Color(0xFF263643),
    shape = RoundedCornerShape(12.dp),
  ) {
    Row(modifier = Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
      Column(modifier = Modifier.weight(1f)) {
        Text(title, color = Color.White, fontWeight = FontWeight.Medium)
        Text(if (value) enabledLabel else "已关闭", color = Color(0xFF9FB0BE), style = MaterialTheme.typography.labelSmall)
      }
      Text(if (value) "开" else "关", color = if (value) TabletBlueLight else Color(0xFF8495A3), fontWeight = FontWeight.SemiBold)
    }
  }
}

@Composable
private fun PerformanceOverlay(status: ReceiverStatus.Decoding, fps: Double, touchEnabled: Boolean, modifier: Modifier = Modifier) {
  @Suppress("DEPRECATION")
  val physicalHz = (LocalContext.current as? Activity)?.windowManager?.defaultDisplay?.refreshRate
  Column(modifier = modifier.background(Color(0xCC0B151E), RoundedCornerShape(10.dp)).padding(horizontal = 12.dp, vertical = 9.dp)) {
    Text("${status.width}×${status.height}  解码 ${"%.1f".format(fps)} fps", color = Color.White, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.labelMedium)
    Text("平板实际屏幕 ${physicalHz?.let { "%.0f".format(it) } ?: "--"} Hz", color = Color(0xFF9CB0BE), style = MaterialTheme.typography.labelSmall)
    Text("H.264 硬解  ·  触控${if (touchEnabled) "开启" else "关闭"}", color = Color(0xFF9CB0BE), style = MaterialTheme.typography.labelSmall)
  }
}
