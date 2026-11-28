package com.falkue.rowcoach.ble

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import com.falkue.rowcoach.pm5.PM5
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class FoundDevice(val address: String, val name: String, val rssi: Int)

enum class BleState { IDLE, SCANNING, CONNECTING, DISCOVERING, CONNECTED, FAILED }

/**
 * Concept2 PM5 über Bluetooth LE: suchen, verbinden, 0x0034 (100 ms) schreiben, Notifications abonnieren.
 * Rohe Bytes gehen an [onNotification] – dieselbe Senke wie beim Simulator (RowingState.ingest).
 * Entspricht dem PM5-Teil von App/RowCoach/Devices/DeviceManager.swift (ohne FTMS und Pulsgurt).
 *
 * Android verarbeitet GATT-Schreibvorgänge nur einzeln; deshalb eine kleine Warteschlange [ops].
 */
@SuppressLint("MissingPermission") // Berechtigungen prüft hasPermissions() vor jedem Aufruf
class PM5BleClient(private val context: Context) {
    companion object {
        private const val TAG = "RowCoachBLE"
        private const val SCAN_TIMEOUT_MS = 15_000L

        /** Laufzeit-Berechtigungen je nach Android-Version */
        fun requiredPermissions(): Array<String> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            } else {
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
            }
    }

    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val adapter get() = manager?.adapter
    private val main = Handler(Looper.getMainLooper())

    private val _state = MutableStateFlow(BleState.IDLE)
    val state: StateFlow<BleState> = _state.asStateFlow()
    private val _devices = MutableStateFlow<List<FoundDevice>>(emptyList())
    val devices: StateFlow<List<FoundDevice>> = _devices.asStateFlow()
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    /** Senke für rohe Notifications (Main-Thread) */
    var onNotification: ((PM5.Characteristic, ByteArray) -> Unit)? = null

    private var gatt: BluetoothGatt? = null
    private val ops = ArrayDeque<(BluetoothGatt) -> Boolean>()
    private var opBusy = false
    var notificationCount = 0
        private set

    fun hasPermissions(): Boolean = requiredPermissions().all {
        context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    val isBluetoothOn: Boolean get() = adapter?.isEnabled == true

    // MARK: Suchen

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.scanRecord?.deviceName ?: result.device.name ?: ""
            val uuids = result.scanRecord?.serviceUuids.orEmpty()
            val isPm5 = name.startsWith("PM5") || uuids.contains(ParcelUuid(PM5.discoveryService))
            if (!isPm5) return
            val d = FoundDevice(result.device.address, name.ifEmpty { "PM5" }, result.rssi)
            val list = _devices.value.filterNot { it.address == d.address } + d
            _devices.value = list.sortedByDescending { it.rssi }
        }

        override fun onScanFailed(errorCode: Int) {
            fail("Suche fehlgeschlagen (Code $errorCode)")
        }
    }

    fun startScan() {
        if (!hasPermissions()) return fail("Bluetooth-Berechtigung fehlt")
        if (!isBluetoothOn) return fail("Bluetooth ist aus")
        val scanner = adapter?.bluetoothLeScanner ?: return fail("kein BLE-Scanner")
        _devices.value = emptyList()
        _message.value = if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R)
            "Suche … (Android ≤ 11: Standort muss eingeschaltet sein)" else "Suche …"
        _state.value = BleState.SCANNING
        // Ohne Filter suchen: manche PM5 werben die Discovery-UUID nur in der Scan-Antwort; Auswahl im Callback
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanner.startScan(null, settings, scanCallback)
        main.postDelayed({ if (_state.value == BleState.SCANNING) stopScan() }, SCAN_TIMEOUT_MS)
    }

    fun stopScan() {
        if (hasPermissions()) adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        if (_state.value == BleState.SCANNING) {
            _state.value = BleState.IDLE
            _message.value = if (_devices.value.isEmpty()) "Kein PM5 gefunden – PM5 aufwecken (Menü → Connect)" else null
        }
    }

    // MARK: Verbinden

    fun connect(address: String) {
        if (!hasPermissions()) return fail("Bluetooth-Berechtigung fehlt")
        stopScan()
        val device: BluetoothDevice = adapter?.getRemoteDevice(address) ?: return fail("Gerät unbekannt")
        _state.value = BleState.CONNECTING
        _message.value = "Verbinde mit ${device.name ?: address} …"
        gatt?.close()
        gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    fun disconnect() {
        if (hasPermissions()) gatt?.disconnect()
        gatt?.close()
        gatt = null
        ops.clear(); opBusy = false
        _state.value = BleState.IDLE
        _message.value = null
    }

    private fun fail(msg: String) {
        Log.w(TAG, msg)
        _message.value = msg
        _state.value = BleState.FAILED
    }

    private fun enqueue(op: (BluetoothGatt) -> Boolean) {
        ops.addLast(op)
        pump()
    }

    private fun pump() {
        if (opBusy) return
        val g = gatt ?: return
        while (ops.isNotEmpty()) {
            val op = ops.removeFirst()
            if (op(g)) { opBusy = true; return }  // wartet auf onDescriptorWrite / onCharacteristicWrite
        }
    }

    private fun opDone() {
        main.post { opBusy = false; pump() }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    _state.value = BleState.DISCOVERING
                    _message.value = "Dienste werden gelesen …"
                    g.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    g.close()
                    if (gatt == g) gatt = null
                    ops.clear(); opBusy = false
                    if (_state.value != BleState.IDLE) fail("Verbindung getrennt (Status $status)")
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                val service = g.getService(PM5.rowingService)
                if (status != BluetoothGatt.GATT_SUCCESS || service == null) {
                    fail("PM5-Ruderdienst nicht gefunden"); return@post
                }
                // 1) Takt 100 ms (wie iOS), 2) Notifications einzeln einschalten
                service.getCharacteristic(PM5.Characteristic.SAMPLE_RATE.uuid)?.let { c ->
                    enqueue { gg -> writeCharacteristic(gg, c, byteArrayOf(PM5.SAMPLE_RATE_100MS)) }
                }
                for (pc in PM5.Characteristic.subscribed) {
                    val c = service.getCharacteristic(pc.uuid) ?: continue
                    enqueue { gg -> enableNotify(gg, c) }
                }
                enqueue { _ ->
                    _state.value = BleState.CONNECTED
                    _message.value = "Verbunden"
                    false
                }
            }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) = opDone()

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) = opDone()

        // Android 13+: Wert kommt als Parameter
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            deliver(c, value)
        }

        // bis Android 12: Wert steht in der Characteristic
        @Deprecated("API < 33")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                @Suppress("DEPRECATION")
                deliver(c, c.value?.copyOf() ?: return)
            }
        }
    }

    private fun deliver(c: BluetoothGattCharacteristic, value: ByteArray) {
        val pc = PM5.Characteristic.from(c.uuid) ?: return
        main.post {
            notificationCount++
            onNotification?.invoke(pc, value)
        }
    }

    private fun writeCharacteristic(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(c, value, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) ==
                BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                c.value = value
                c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                g.writeCharacteristic(c)
            }
        }

    private fun enableNotify(g: BluetoothGatt, c: BluetoothGattCharacteristic): Boolean {
        g.setCharacteristicNotification(c, true)
        val d = c.getDescriptor(PM5.cccd) ?: return false
        val v = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeDescriptor(d, v) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                d.value = v
                g.writeDescriptor(d)
            }
        }
    }
}
