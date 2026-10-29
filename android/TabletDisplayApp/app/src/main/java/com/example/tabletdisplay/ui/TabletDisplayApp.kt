package com.example.tabletdisplay.ui

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.example.tabletdisplay.decoder.ReceiverStatus
import com.example.tabletdisplay.ui.diagnostics.DiagnosticsScreen
import com.example.tabletdisplay.ui.display.TabletDisplayScreen
import com.example.tabletdisplay.ui.home.ConnectionHomeScreen
import com.example.tabletdisplay.ui.settings.SettingsScreen

@Composable
fun TabletDisplayApp(modifier: Modifier = Modifier) {
  var destinationName by rememberSaveable { mutableStateOf(AppDestination.Display.name) }
  val context = LocalContext.current
  var preferences by remember { mutableStateOf(loadDisplayPreferences(context)) }
  val changePreferences: (DisplayPreferences) -> Unit = {
    preferences = it
    saveDisplayPreferences(context, it)
  }
  var lastReceiverStatus by remember { mutableStateOf<ReceiverStatus>(ReceiverStatus.Starting) }
  val destination = AppDestination.valueOf(destinationName)

  BackHandler(enabled = destination != AppDestination.Home) {
    destinationName =
      if (destination == AppDestination.Display) AppDestination.Home.name else AppDestination.Display.name
  }

  when (destination) {
    AppDestination.Display ->
      TabletDisplayScreen(
        preferences = preferences,
        onPreferencesChange = changePreferences,
        onStatusChanged = { lastReceiverStatus = it },
        onOpenSettings = { destinationName = AppDestination.Settings.name },
        onOpenDiagnostics = { destinationName = AppDestination.Diagnostics.name },
        onDisconnect = { destinationName = AppDestination.Home.name },
        modifier = modifier,
      )
    AppDestination.Home ->
      ConnectionHomeScreen(
        lastStatus = lastReceiverStatus,
        onStartDisplay = { destinationName = AppDestination.Display.name },
        onOpenSettings = { destinationName = AppDestination.Settings.name },
        onOpenDiagnostics = { destinationName = AppDestination.Diagnostics.name },
        modifier = modifier,
      )
    AppDestination.Settings ->
      SettingsScreen(
        preferences = preferences,
        onPreferencesChange = changePreferences,
        onBack = { destinationName = AppDestination.Display.name },
        modifier = modifier,
      )
    AppDestination.Diagnostics ->
      DiagnosticsScreen(
        status = lastReceiverStatus,
        preferences = preferences,
        onBack = { destinationName = AppDestination.Display.name },
        onRetry = { destinationName = AppDestination.Display.name },
        modifier = modifier,
      )
  }
}
