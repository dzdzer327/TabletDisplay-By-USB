package com.example.tabletdisplay.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme =
  darkColorScheme(
    primary = TabletBlueLight,
    secondary = TabletBlue,
    background = TabletNavy,
    surface = TabletSurfaceDark,
    surfaceVariant = Color(0xFF1B2A38),
    onPrimary = Color(0xFF002C40),
    onBackground = Color(0xFFE8F0F7),
    onSurface = Color(0xFFE8F0F7),
  )

private val LightColorScheme =
  lightColorScheme(
    primary = TabletBlue,
    secondary = TabletBlueDark,
    background = TabletSurface,
    surface = Color.White,
    surfaceVariant = Color(0xFFE8EFF5),
    onPrimary = Color.White,
    onBackground = Color(0xFF182230),
    onSurface = Color(0xFF182230),
  )

@Composable
fun TabletDisplayTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  content: @Composable () -> Unit,
) {
  val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

  MaterialTheme(colorScheme = colorScheme, typography = Typography, content = content)
}
