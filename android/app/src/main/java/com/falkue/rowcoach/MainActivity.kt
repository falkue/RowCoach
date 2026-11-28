package com.falkue.rowcoach

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.falkue.rowcoach.ble.PM5BleClient
import com.falkue.rowcoach.course.Course
import com.falkue.rowcoach.ui.HomeScreen
import com.falkue.rowcoach.ui.RideScreen
import com.falkue.rowcoach.ui.RideSource
import com.falkue.rowcoach.ui.RowCoachTheme

class MainActivity : ComponentActivity() {
    private lateinit var ble: PM5BleClient

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Beim Rudern soll der Bildschirm anbleiben
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        ble = PM5BleClient(applicationContext)
        setContent { RowCoachTheme { RowCoachApp(ble) } }
    }

    override fun onDestroy() {
        if (isFinishing) ble.disconnect()
        super.onDestroy()
    }
}

/** Zwei Bildschirme ohne Navigationsbibliothek: Startseite und Fahrt. */
@Composable
private fun RowCoachApp(ble: PM5BleClient) {
    val context = LocalContext.current
    val courses = remember { Course.loadAll(context) }
    var ride by remember { mutableStateOf<Pair<Course, RideSource>?>(null) }

    val current = ride
    if (current == null) {
        HomeScreen(
            courses = courses,
            ble = ble,
            onDemoRide = { ride = it to RideSource.SIMULATOR },
            onPm5Ride = { ride = it to RideSource.PM5 },
        )
    } else {
        RideScreen(course = current.first, source = current.second, ble = ble, onBack = { ride = null })
    }
}
