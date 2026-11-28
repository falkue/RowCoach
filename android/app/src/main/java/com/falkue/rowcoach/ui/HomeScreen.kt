package com.falkue.rowcoach.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.falkue.rowcoach.ble.BleState
import com.falkue.rowcoach.ble.PM5BleClient
import com.falkue.rowcoach.course.Course

@Composable
fun HomeScreen(
    courses: List<Course>,
    ble: PM5BleClient,
    onDemoRide: (Course) -> Unit,
    onPm5Ride: (Course) -> Unit,
) {
    val bleState by ble.state.collectAsState()
    Column(Modifier.fillMaxSize().background(Bahnen.Kobalt).safeDrawingPadding()) {
        // Kopf: Marke
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("RowCoach", color = Bahnen.Gelb, fontSize = 30.sp, fontWeight = FontWeight.Black)
                Text("Android-Machbarkeitstest · Strecken in 3D", color = Color.White.copy(alpha = 0.85f),
                    fontSize = 14.sp)
            }
        }
        Row(Modifier.fillMaxSize().background(Bahnen.Papier).padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            // Strecken
            Column(Modifier.weight(1.4f)) {
                Text("Strecken", fontWeight = FontWeight.Bold, fontSize = 18.sp, color = Bahnen.Tinte)
                Spacer(Modifier.height(8.dp))
                if (courses.isEmpty()) {
                    Text("Keine Strecke in den Assets. Auf dem Mac android/fetch_assets.sh ausführen und neu bauen.",
                        color = Bahnen.Tinte)
                }
                LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(courses, key = { it.id }) { c ->
                        CourseCard(c, pm5Ready = bleState == BleState.CONNECTED,
                            onDemoRide = { onDemoRide(c) }, onPm5Ride = { onPm5Ride(c) })
                    }
                }
            }
            // PM5
            Pm5Panel(ble, Modifier.weight(1f))
        }
    }
}

@Composable
private fun CourseCard(c: Course, pm5Ready: Boolean, onDemoRide: () -> Unit, onPm5Ride: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = Color.White), shape = RoundedCornerShape(14.dp)) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Text(c.title, fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 2,
                overflow = TextOverflow.Ellipsis, color = Bahnen.Tinte)
            Text("${c.region} · ${formatDistance(c.totalM)}", fontSize = 13.sp, color = Bahnen.Tinte.copy(0.7f))
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(onClick = onDemoRide, colors = ButtonDefaults.buttonColors(
                    containerColor = Bahnen.Gelb, contentColor = Bahnen.Tinte)) {
                    Text("Demo-Fahrt", fontWeight = FontWeight.Bold)
                }
                OutlinedButton(onClick = onPm5Ride, enabled = pm5Ready) { Text("Mit PM5 fahren") }
            }
        }
    }
}

@Composable
private fun Pm5Panel(ble: PM5BleClient, modifier: Modifier) {
    val state by ble.state.collectAsState()
    val devices by ble.devices.collectAsState()
    val message by ble.message.collectAsState()
    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (ble.hasPermissions()) ble.startScan()
    }
    Column(modifier) {
        Text("Concept2 PM5", fontWeight = FontWeight.Bold, fontSize = 18.sp, color = Bahnen.Tinte)
        Spacer(Modifier.height(8.dp))
        Card(colors = CardDefaults.cardColors(containerColor = Color.White), shape = RoundedCornerShape(14.dp)) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Text(when (state) {
                    BleState.IDLE -> "Nicht verbunden"
                    BleState.SCANNING -> "Suche läuft"
                    BleState.CONNECTING -> "Verbinde"
                    BleState.DISCOVERING -> "Lese Dienste"
                    BleState.CONNECTED -> "Verbunden"
                    BleState.FAILED -> "Fehler"
                }, fontWeight = FontWeight.SemiBold, color = Bahnen.Tinte)
                message?.let { Text(it, fontSize = 13.sp, color = Bahnen.Tinte.copy(0.7f)) }
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (state == BleState.CONNECTED) {
                        OutlinedButton(onClick = { ble.disconnect() }) { Text("Trennen") }
                    } else if (state == BleState.SCANNING) {
                        OutlinedButton(onClick = { ble.stopScan() }) { Text("Suche stoppen") }
                    } else {
                        Button(onClick = {
                            if (ble.hasPermissions()) ble.startScan()
                            else permLauncher.launch(PM5BleClient.requiredPermissions())
                        }) { Text("PM5 suchen") }
                    }
                }
                devices.forEach { d ->
                    Row(Modifier.fillMaxWidth().clickable { ble.connect(d.address) }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.width(8.dp).height(8.dp).background(Bahnen.Kobalt, RoundedCornerShape(4.dp)))
                        Spacer(Modifier.width(8.dp))
                        Text(d.name, Modifier.weight(1f), color = Bahnen.Tinte)
                        Text("${d.rssi} dBm", fontSize = 12.sp, color = Bahnen.Tinte.copy(0.6f))
                    }
                }
            }
        }
    }
}
