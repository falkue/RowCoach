package com.falkue.rowcoach.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Marke „Bahnen“ (docs/marke): Kobalt und Gelb */
object Bahnen {
    val Kobalt = Color(0xFF2340FF)
    val Gelb = Color(0xFFFFD60A)
    val Tinte = Color(0xFF0B0F1E)
    val Papier = Color(0xFFF6F6F2)
}

@Composable
fun RowCoachTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Bahnen.Kobalt,
            onPrimary = Color.White,
            secondary = Bahnen.Gelb,
            onSecondary = Bahnen.Tinte,
            background = Bahnen.Papier,
            surface = Color.White,
            onSurface = Bahnen.Tinte,
        ),
        content = content,
    )
}
