import CoreBluetooth
import Foundation
import Observation
import RowCoachKit

/// Ein gefundenes Bluetooth-Gerät (PM5, FTMS-Rudergerät oder Pulsgurt).
struct DiscoveredDevice: Identifiable, Equatable {
    enum Kind: String {
        case pm5 = "PM5", ftmsRower = "FTMS", heartRate = "Pulsgurt"
        /// Rudergerät (PM5 oder FTMS): belegt denselben Platz, es ist immer nur eines verbunden
        var isRower: Bool { self != .heartRate }
    }
    let id: UUID
    var name: String
    var kind: Kind
    var rssi: Int
}

enum LinkState: String {
    case idle = "nicht verbunden", scanning = "suche …", connecting = "verbinde …", connected = "verbunden"
}

/// Verwaltet die Bluetooth-Verbindungen zu Rudergerät und Pulsgurt (CoreBluetooth, Hauptthread).
/// Rudergerät ist ein Concept2 PM5 (eigenes Protokoll) oder – Beta, mit echter Hardware ungetestet – ein Gerät mit
/// Bluetooth FTMS (Rower Data 0x2AD1). Beide belegen denselben Platz (`pm5`, `pm5State`, `pm5Name`); `rowerKind` sagt,
/// welches Protokoll. Bietet ein Gerät beides an, gilt das PM5-Protokoll (mehr Daten).
/// Merkt sich die zuletzt verwendeten Geräte und verbindet sich beim Start automatisch neu.
@Observable
final class DeviceManager: NSObject {
    private(set) var bluetoothReady = false
    private(set) var discovered: [DiscoveredDevice] = []
    private(set) var pm5State: LinkState = .idle
    private(set) var strapState: LinkState = .idle
    private(set) var pm5Name: String?
    /// Protokoll des gewählten Rudergeräts (gemerkt mit dem Gerät)
    private(set) var rowerKind: RowingMachineKind = .pm5
    /// FTMS: vom Gerät gemeldete Fähigkeiten (0x2ACC), für die Diagnose
    private(set) var ftmsFeatures: FTMSFeatures?
    /// FTMS: letzte Statusmeldung des Geräts (0x2ADA), für die Diagnose
    private(set) var ftmsStatus: FTMSMachineStatus?
    private(set) var strapName: String?
    private(set) var strapBattery: Int?
    private(set) var snapshot = RowingSnapshot()
    private(set) var lastSummary: PM5WorkoutSummary?
    private(set) var lastError: String?
    /// Zähler je Characteristic für die Diagnose-Ansicht
    private(set) var messageCounts: [String: Int] = [:]
    /// Simulator liefert die Daten (echte PM5- und Gurtdaten werden dann ignoriert)
    private(set) var simulatorActive = false
    /// Welches Protokoll der Simulator nachbildet (`-simulateFTMS 1`/`2`: FTMS)
    private(set) var simulatorKind: RowingMachineKind = .pm5
    /// Protokoll, aus dem die Ruderdaten gerade kommen (Simulator oder echtes Gerät)
    var activeMachineKind: RowingMachineKind { simulatorActive ? simulatorKind : rowerKind }
    /// Takt der echten Schläge für die Ruderfigur
    @ObservationIgnored private var strokeTracker = StrokePhaseTracker()
    /// FTMS: Rower Data → Snapshot (Teilpakete, Schläge aus dem Zähler, fehlende Werte ableiten)
    @ObservationIgnored private var ftmsTracker = FTMSRowerTracker()

    /// Wird bei jedem neuen Pulswert aufgerufen (für Apple Health).
    var onHeartRate: ((HeartRateMeasurement, Date) -> Void)? = nil
    /// Wird bei jeder PM5-Nachricht aufgerufen (Aufzeichnung).
    var onPM5Message: ((PM5Message, Date) -> Void)? = nil
    /// Wird bei jedem FTMS-Rower-Data-Paket aufgerufen, nachdem `snapshot` aktualisiert ist.
    var onFTMSData: ((FTMSRowerData, Date) -> Void)? = nil

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var pm5: CBPeripheral?
    @ObservationIgnored private var strap: CBPeripheral?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let pm5Key = "device.pm5", strapKey = "device.strap", rowerKindKey = "device.pm5.kind"

    private static let pm5Chars: [CBUUID: PM5.Characteristic] = Dictionary(
        uniqueKeysWithValues: PM5.Characteristic.allCases.map { (CBUUID(string: $0.uuid), $0) })
    private static let ftmsChars: [CBUUID: FTMS.Characteristic] = Dictionary(
        uniqueKeysWithValues: FTMS.Characteristic.allCases.map { (CBUUID(string: $0.rawValue), $0) })
    private static let ftmsService = CBUUID(string: FTMS.service)

    override init() {
        super.init()
        rowerKind = defaults.string(forKey: Self.rowerKindKey).flatMap(RowingMachineKind.init(rawValue:)) ?? .pm5
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
        case .pm5, .ftmsRower:
            if let old = pm5, old != p { central.cancelPeripheralConnection(old) }
            pm5 = p; pm5State = .connecting; pm5Name = device.name
            rowerKind = device.kind == .ftmsRower ? .ftms : .pm5
            ftmsFeatures = nil; ftmsStatus = nil
            ftmsTracker = FTMSRowerTracker()
            defaults.set(p.identifier.uuidString, forKey: Self.pm5Key)
            defaults.set(rowerKind.rawValue, forKey: Self.rowerKindKey)
        case .heartRate:
            if let old = strap, old != p { central.cancelPeripheralConnection(old) }
            strap = p; strapState = .connecting; strapName = device.name
            defaults.set(p.identifier.uuidString, forKey: Self.strapKey)
        }
        p.delegate = self
        central.connect(p)
    }

    func disconnect(_ kind: DiscoveredDevice.Kind, forget: Bool = false) {
        let p = kind.isRower ? pm5 : strap
        if let p { central.cancelPeripheralConnection(p) }
        if forget {
            defaults.removeObject(forKey: kind.isRower ? Self.pm5Key : Self.strapKey)
            if kind.isRower { defaults.removeObject(forKey: Self.rowerKindKey) }
        }
    }

    func resetSnapshot() { snapshot = RowingSnapshot() }

    /// Schlagphase 0…1 im Takt der echten Schläge (0 = Wasserfassen); nil, wenn keine Schläge erkannt werden.
    func strokePhase(at date: Date = Date()) -> Double? {
        strokeTracker.phase(at: date.timeIntervalSinceReferenceDate, strokeRate: snapshot.strokeRate)
    }

    /// Schaltet zwischen echtem PM5 und Simulator um. Der Zustand beginnt jeweils neu.
    func setSimulatorActive(_ on: Bool, kind: RowingMachineKind = .pm5) {
        guard on != simulatorActive else { return }
        simulatorActive = on
        simulatorKind = on ? kind : .pm5
        snapshot = RowingSnapshot()
        strokeTracker = StrokePhaseTracker()
        ftmsTracker = FTMSRowerTracker()
        lastSummary = nil
    }

    // MARK: Gemeinsamer Eingang (PM5 über Bluetooth oder Simulator)

    /// Simulator: dieselben Bytes wie vom PM5, über denselben Parser.
    func ingestSimulated(characteristic: PM5.Characteristic, bytes: [UInt8], at date: Date = Date()) {
        guard simulatorActive else { return }
        handlePM5(characteristic, bytes: bytes, at: date, label: "Sim")
    }

    /// FTMS-Simulator: Rower-Data-Bytes wie von einem FTMS-Rudergerät, über denselben Parser.
    func ingestSimulatedFTMS(bytes: [UInt8], at date: Date = Date()) {
        guard simulatorActive else { return }
        handleFTMSRowerData(bytes: bytes, at: date, label: "Sim")
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

    private func handleFTMSRowerData(bytes: [UInt8], at date: Date, label: String) {
        do {
            let d = try FTMSRowerDataParser.parse(bytes)
            let t = date.timeIntervalSinceReferenceDate
            let strokes = ftmsTracker.ingest(d, at: t, into: &snapshot)
            if strokes > 0 { strokeTracker.registerStroke(at: t, interval: ftmsTracker.lastStrokeInterval) }
            count("\(label) FTMS 0x2AD1")
            onFTMSData?(d, date)
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
        let rower: DiscoveredDevice.Kind = rowerKind == .ftms ? .ftmsRower : .pm5
        for (key, kind) in [(Self.pm5Key, rower), (Self.strapKey, DiscoveredDevice.Kind.heartRate)] {
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
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let ftmsData = serviceData?[Self.ftmsService].map { [UInt8]($0) }
        let kind: DiscoveredDevice.Kind
        if name.hasPrefix("PM5") || services.contains(CBUUID(string: PM5.discoveryService)) {
            // PM5 zuerst: auch wenn er zusätzlich FTMS anbieten sollte, liefert sein eigenes Protokoll mehr Daten
            kind = .pm5
        } else if FTMSAdvertisement.isRowerCandidate(advertisesService: services.contains(Self.ftmsService)
                                                         || ftmsData != nil, serviceData: ftmsData) {
            kind = .ftmsRower
        } else if services.contains(CBUUID(string: HeartRateProfile.service)) || HeartRateProfile.looksLikeStrap(name) {
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
            if rowerKind == .ftms {
                peripheral.discoverServices([Self.ftmsService])
            } else {
                peripheral.discoverServices([CBUUID(string: PM5.rowingService)])
            }
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
        if peripheral == pm5, rowerKind == .ftms, !(peripheral.services ?? []).contains(where: { $0.uuid == Self.ftmsService }) {
            lastError = String(localized: "Das Gerät bietet keinen Bluetooth-FTMS-Dienst an.")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if service.uuid == Self.ftmsService {
            discoverFTMS(peripheral, service)
            return
        }
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
        } else if let fc = Self.ftmsChars[c.uuid] {
            handleFTMS(fc, bytes: bytes, at: now)
        } else if c.uuid == CBUUID(string: HeartRateProfile.measurement) {
            guard !simulatorActive else { return }
            handleHeartRate(bytes: bytes, at: now, label: "Gurt")
        } else if c.uuid == CBUUID(string: HeartRateProfile.batteryLevel) {
            strapBattery = bytes.first.map(Int.init)
        }
    }
}

// MARK: - FTMS (Beta)

extension DeviceManager {
    /// Characteristics des Fitness Machine Service: Rower Data und Status abonnieren, Fähigkeiten lesen.
    /// Der Control Point wird bewusst nicht beschrieben (RowCoach steuert das Gerät nicht; Rücksetzen und Pausen
    /// erkennt die Fahrt selbst), siehe docs/geraete/UMSETZUNG.md.
    fileprivate func discoverFTMS(_ peripheral: CBPeripheral, _ service: CBService) {
        let chars = service.characteristics ?? []
        for c in chars {
            switch Self.ftmsChars[c.uuid] {
            case .rowerData?, .machineStatus?: peripheral.setNotifyValue(true, for: c)
            case .feature?: peripheral.readValue(for: c)
            default: break
            }
        }
        if !chars.contains(where: { Self.ftmsChars[$0.uuid] == .rowerData }) {
            lastError = String(localized: "Das Gerät sendet keine Ruderdaten (FTMS ohne Rower Data). Ist es ein Rudergerät?")
        }
    }

    fileprivate func handleFTMS(_ fc: FTMS.Characteristic, bytes: [UInt8], at date: Date) {
        switch fc {
        case .rowerData:
            guard !simulatorActive else { return }
            handleFTMSRowerData(bytes: bytes, at: date, label: "FTMS")
        case .feature:
            ftmsFeatures = FTMSFeatures.parse(bytes)
        case .machineStatus:
            if let st = FTMSMachineStatus.parse(bytes) {
                ftmsStatus = st
                count("FTMS Status 0x2ADA")
            }
        default:
            break
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
