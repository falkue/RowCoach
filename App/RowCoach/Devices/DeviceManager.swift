import CoreBluetooth
import Foundation
import Observation
import RowCoachKit

/// Ein gefundenes Bluetooth-Gerät (PM5 oder Pulsgurt).
struct DiscoveredDevice: Identifiable, Equatable {
    enum Kind: String { case pm5 = "PM5", heartRate = "Pulsgurt" }
    let id: UUID
    var name: String
    var kind: Kind
    var rssi: Int
}

enum LinkState: String {
    case idle = "nicht verbunden", scanning = "suche …", connecting = "verbinde …", connected = "verbunden"
}

/// Verwaltet die Bluetooth-Verbindungen zu PM5 und Pulsgurt (CoreBluetooth, Hauptthread).
/// Merkt sich die zuletzt verwendeten Geräte und verbindet sich beim Start automatisch neu.
@Observable
final class DeviceManager: NSObject {
    private(set) var bluetoothReady = false
    private(set) var discovered: [DiscoveredDevice] = []
    private(set) var pm5State: LinkState = .idle
    private(set) var strapState: LinkState = .idle
    private(set) var pm5Name: String?
    private(set) var strapName: String?
    private(set) var strapBattery: Int?
    private(set) var snapshot = RowingSnapshot()
    private(set) var lastSummary: PM5WorkoutSummary?
    private(set) var lastError: String?
    /// Zähler je Characteristic für die Diagnose-Ansicht
    private(set) var messageCounts: [String: Int] = [:]
    /// Simulator liefert die Daten (echte PM5- und Gurtdaten werden dann ignoriert)
    private(set) var simulatorActive = false
    /// Takt der echten Schläge für die Ruderfigur
    @ObservationIgnored private var strokeTracker = StrokePhaseTracker()

    /// Wird bei jedem neuen Pulswert aufgerufen (für Apple Health).
    var onHeartRate: ((HeartRateMeasurement, Date) -> Void)? = nil
    /// Wird bei jeder PM5-Nachricht aufgerufen (Aufzeichnung).
    var onPM5Message: ((PM5Message, Date) -> Void)? = nil

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var pm5: CBPeripheral?
    @ObservationIgnored private var strap: CBPeripheral?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let pm5Key = "device.pm5", strapKey = "device.strap"

    private static let pm5Chars: [CBUUID: PM5.Characteristic] = Dictionary(
        uniqueKeysWithValues: PM5.Characteristic.allCases.map { (CBUUID(string: $0.uuid), $0) })

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: Bedienung

    func startScan() {
        guard bluetoothReady else { return }
        discovered.removeAll()
        // Ohne Service-Filter: der PM5 kündigt nicht in jedem Zustand seinen Service an; gefiltert wird nach Name/Service.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if pm5 == nil { pm5State = .scanning }
        if strap == nil { strapState = .scanning }
    }

    func stopScan() {
        central.stopScan()
        if pm5State == .scanning { pm5State = .idle }
        if strapState == .scanning { strapState = .idle }
    }

    func connect(_ device: DiscoveredDevice) {
        guard let p = peripherals[device.id] else { return }
        switch device.kind {
        case .pm5:
            if let old = pm5, old != p { central.cancelPeripheralConnection(old) }
            pm5 = p; pm5State = .connecting; pm5Name = device.name
            defaults.set(p.identifier.uuidString, forKey: Self.pm5Key)
        case .heartRate:
            if let old = strap, old != p { central.cancelPeripheralConnection(old) }
            strap = p; strapState = .connecting; strapName = device.name
            defaults.set(p.identifier.uuidString, forKey: Self.strapKey)
        }
        p.delegate = self
        central.connect(p)
    }

    func disconnect(_ kind: DiscoveredDevice.Kind, forget: Bool = false) {
        let p = kind == .pm5 ? pm5 : strap
        if let p { central.cancelPeripheralConnection(p) }
        if forget { defaults.removeObject(forKey: kind == .pm5 ? Self.pm5Key : Self.strapKey) }
    }

    func resetSnapshot() { snapshot = RowingSnapshot() }

    /// Schlagphase 0…1 im Takt der echten Schläge (0 = Wasserfassen); nil, wenn keine Schläge erkannt werden.
    func strokePhase(at date: Date = Date()) -> Double? {
        strokeTracker.phase(at: date.timeIntervalSinceReferenceDate, strokeRate: snapshot.strokeRate)
    }

    /// Schaltet zwischen echtem PM5 und Simulator um. Der Zustand beginnt jeweils neu.
    func setSimulatorActive(_ on: Bool) {
        guard on != simulatorActive else { return }
        simulatorActive = on
        snapshot = RowingSnapshot()
        strokeTracker = StrokePhaseTracker()
        lastSummary = nil
    }

    // MARK: Gemeinsamer Eingang (PM5 über Bluetooth oder Simulator)

    /// Simulator: dieselben Bytes wie vom PM5, über denselben Parser.
    func ingestSimulated(characteristic: PM5.Characteristic, bytes: [UInt8], at date: Date = Date()) {
        guard simulatorActive else { return }
        handlePM5(characteristic, bytes: bytes, at: date, label: "Sim")
    }

    /// Simulator: Bytes eines Pulsgurts (Heart Rate Measurement).
    func ingestSimulatedHeartRate(bytes: [UInt8], at date: Date = Date()) {
        guard simulatorActive else { return }
        handleHeartRate(bytes: bytes, at: date, label: "Sim")
    }

    private func handlePM5(_ pc: PM5.Characteristic, bytes: [UInt8], at date: Date, label: String) {
        do {
            let m = try PM5Parser.parse(characteristic: pc, bytes: bytes)
            snapshot.apply(m)
            switch m {
            case .workoutSummary(let s): lastSummary = s
            case .generalStatus(let s): strokeTracker.update(state: s.strokeState, at: date.timeIntervalSinceReferenceDate)
            case .strokeData(let s): strokeTracker.update(driveTime: s.driveTime, recoveryTime: s.recoveryTime)
            default: break
            }
            count(label + String(format: " 0x%04X", pc.rawValue))
            onPM5Message?(m, date)
        } catch {
            lastError = String(localized: "\(label): \(error)")
        }
    }

    private func handleHeartRate(bytes: [UInt8], at date: Date, label: String) {
        guard let m = HeartRateParser.parse(bytes) else { return }
        snapshot.apply(strap: m)
        count("\(label) Puls 0x2A37")
        onHeartRate?(m, date)
    }

    // MARK: intern

    private func reconnectRemembered() {
        for (key, kind) in [(Self.pm5Key, DiscoveredDevice.Kind.pm5), (Self.strapKey, .heartRate)] {
            guard let s = defaults.string(forKey: key), let id = UUID(uuidString: s),
                  let p = central.retrievePeripherals(withIdentifiers: [id]).first else { continue }
            peripherals[id] = p
            connect(DiscoveredDevice(id: id, name: p.name ?? kind.rawValue, kind: kind, rssi: 0))
        }
    }

    private func count(_ key: String) { messageCounts[key, default: 0] += 1 }
}

// MARK: - CBCentralManagerDelegate

extension DeviceManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothReady = central.state == .poweredOn
        if bluetoothReady { reconnectRemembered() } else {
            lastError = central.state == .unauthorized ? String(localized: "Bluetooth-Zugriff nicht erlaubt (Einstellungen → RowCoach)") : nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let kind: DiscoveredDevice.Kind
        if name.hasPrefix("PM5") || services.contains(CBUUID(string: PM5.discoveryService)) {
            kind = .pm5
        } else if services.contains(CBUUID(string: HeartRateProfile.service)) || name.localizedCaseInsensitiveContains("polar") {
            kind = .heartRate
        } else { return }
        peripherals[peripheral.identifier] = peripheral
        let d = DiscoveredDevice(id: peripheral.identifier, name: name.isEmpty ? kind.rawValue : name,
                                 kind: kind, rssi: RSSI.intValue)
        if let i = discovered.firstIndex(where: { $0.id == d.id }) { discovered[i] = d } else { discovered.append(d) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral == pm5 {
            pm5State = .connected
            peripheral.discoverServices([CBUUID(string: PM5.rowingService)])
        } else if peripheral == strap {
            strapState = .connected
            peripheral.discoverServices([CBUUID(string: HeartRateProfile.service), CBUUID(string: HeartRateProfile.batteryService)])
        }
        if pm5State == .connected && strapState == .connected { central.stopScan() }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastError = String(localized: "Verbindung fehlgeschlagen: \(error?.localizedDescription ?? "unbekannt")")
        if peripheral == pm5 { pm5State = .idle } else if peripheral == strap { strapState = .idle }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let remembered = [defaults.string(forKey: Self.pm5Key), defaults.string(forKey: Self.strapKey)]
        if peripheral == pm5 {
            pm5State = .idle
            if remembered[0] == nil { pm5 = nil }
        } else if peripheral == strap {
            strapState = .idle; strapBattery = nil
            snapshot.heartRate = nil; snapshot.heartRateSource = nil
            if remembered[1] == nil { strap = nil }
        }
        // Unerwartet getrennt (z. B. PM5 schläft ein): automatisch wieder verbinden, sobald erreichbar.
        if error != nil, remembered.contains(peripheral.identifier.uuidString) {
            if peripheral == pm5 { pm5State = .connecting } else if peripheral == strap { strapState = .connecting }
            central.connect(peripheral)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension DeviceManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if let pc = Self.pm5Chars[c.uuid] {
                if pc == .sampleRate {
                    // 100 ms: Schlagzustand fein genug, damit die Ruderfigur im Takt der echten Schläge bleibt
                    peripheral.writeValue(Data([PM5.SampleRate.ms100.rawValue]), for: c, type: .withResponse)
                } else if PM5.Characteristic.subscribed.contains(pc) {
                    peripheral.setNotifyValue(true, for: c)
                }
            } else if c.uuid == CBUUID(string: HeartRateProfile.measurement) {
                peripheral.setNotifyValue(true, for: c)
            } else if c.uuid == CBUUID(string: HeartRateProfile.batteryLevel) {
                peripheral.readValue(for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let data = c.value else { return }
        let bytes = [UInt8](data)
        let now = Date()
        if let pc = Self.pm5Chars[c.uuid] {
            guard !simulatorActive else { return }
            handlePM5(pc, bytes: bytes, at: now, label: "PM5")
        } else if c.uuid == CBUUID(string: HeartRateProfile.measurement) {
            guard !simulatorActive else { return }
            handleHeartRate(bytes: bytes, at: now, label: "Gurt")
        } else if c.uuid == CBUUID(string: HeartRateProfile.batteryLevel) {
            strapBattery = bytes.first.map(Int.init)
        }
    }
}

extension LinkState {
    /// Anzeige (lokalisiert); der Rohwert bleibt für das Protokoll
    var title: String {
        switch self {
        case .idle: return String(localized: "nicht verbunden")
        case .scanning: return String(localized: "sucht …")
        case .connecting: return String(localized: "verbindet …")
        case .connected: return String(localized: "verbunden")
        }
    }
}
