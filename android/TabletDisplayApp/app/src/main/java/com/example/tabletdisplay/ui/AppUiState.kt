package com.example.tabletdisplay.ui

enum class AppDestination {
  Display,
  Home,
  Settings,
  Diagnostics,
}

enum class InputMode(val title: String, val description: String) {
  NativeTouch("原生触控", "手指位置与 Windows 副屏绝对对应"),
  Touchpad("触控板", "界面已准备，鼠标输入后端将在下一阶段接入"),
  DisplayOnly("仅显示", "不向电脑发送任何输入"),
}

enum class QualityPreset(val title: String) {
  Auto("自动"),
  LowLatency("低延迟"),
  HighQuality("高清晰"),
  PowerSaving("省电"),
}

data class DisplayPreferences(
  val touchEnabled: Boolean = true,
  val inputMode: InputMode = InputMode.NativeTouch,
  val naturalScrolling: Boolean = true,
  val pinchToZoom: Boolean = true,
  val keepScreenOn: Boolean = true,
  val prefer120Hz: Boolean = true,
  val rotationLocked: Boolean = false,
  val qualityPreset: QualityPreset = QualityPreset.Auto,
  val showPerformanceOverlay: Boolean = false,
  val autoConnect: Boolean = true,
)
