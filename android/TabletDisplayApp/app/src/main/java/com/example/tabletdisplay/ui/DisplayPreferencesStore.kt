package com.example.tabletdisplay.ui

import android.content.Context

fun loadDisplayPreferences(context: Context): DisplayPreferences {
  val stored = context.getSharedPreferences("display-preferences", Context.MODE_PRIVATE)
  return DisplayPreferences(
    touchEnabled = stored.getBoolean("touchEnabled", true),
    inputMode = if (stored.getString("inputMode", "NativeTouch") == "DisplayOnly") InputMode.DisplayOnly else InputMode.NativeTouch,
    keepScreenOn = stored.getBoolean("keepScreenOn", true),
    prefer120Hz = stored.getBoolean("prefer120Hz", true),
    rotationLocked = stored.getBoolean("rotationLocked", false),
    showPerformanceOverlay = stored.getBoolean("showPerformanceOverlay", false),
  )
}

fun saveDisplayPreferences(context: Context, preferences: DisplayPreferences) {
  context.getSharedPreferences("display-preferences", Context.MODE_PRIVATE).edit()
    .putBoolean("touchEnabled", preferences.touchEnabled)
    .putString("inputMode", preferences.inputMode.name)
    .putBoolean("keepScreenOn", preferences.keepScreenOn)
    .putBoolean("prefer120Hz", preferences.prefer120Hz)
    .putBoolean("rotationLocked", preferences.rotationLocked)
    .putBoolean("showPerformanceOverlay", preferences.showPerformanceOverlay)
    .apply()
}
