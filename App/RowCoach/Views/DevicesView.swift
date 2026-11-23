import SwiftUI

/// Geräte als Sheet (hinter der Statusanzeige in Kopf bzw. Toolbar): PM5 und Polar-Gurt (H9/H10) suchen,
/// verbinden, vergessen.
struct DevicesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DeviceConnectView()
                    .padding(DS.Space.l)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
            .dsSheetChrome(String(localized: "Geräte")) { dismiss() }
        }
    }
}

/// Inhalt des Geräte-Sheets (auch im ersten Start): je Gerät eine Karte mit klarem Zustand, darunter die Suche
/// mit Fortschrittsanzeige, gefundene Geräte bzw. „nichts gefunden“ mit Hinweis.
struct DeviceConnectView: View {
    @Environment(DeviceManager.self) private var devices
    @State private var scanStarted: Date?
    @State private var scanTimedOut = false

    /// Nach so vielen Sekunden ohne Fund zeigt die Suche „Nichts gefunden“ mit Hinweis
    private static let scanTimeout: Double = 12

    init() {}

    private var scanning: Bool { scanStarted != nil && !scanTimedOut }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if devices.simulatorActive {
                DSBanner(systemImage: "desktopcomputer",
                         text: String(localized: "Simulator aktiv – echte Geräte werden ignoriert."), tone: .hint)
            }
            deviceCard(kind: .pm5, name: devices.pm5Name, state: devices.pm5State,
                       detail: devices.pm5State == .connected ? String(localized: "bereit") : nil)
            deviceCard(kind: .heartRate, name: devices.strapName, state: devices.strapState,
                       detail: strapDetail)
            searchSection
            if let e = devices.lastError {
                DSBanner(systemImage: "exclamationmark.triangle", text: e, tone: .bad)
            }
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("So klappt es").font(.headline)
                Label("PM5: im Monitor „Connect“ wählen, damit er sichtbar ist.", systemImage: "1.circle")
                Label("Pulsgurt: anlegen und die Elektroden befeuchten.", systemImage: "2.circle")
                Label("Den Gurt nicht zusätzlich in den Bluetooth-Einstellungen des Geräts koppeln.",
                      systemImage: "3.circle")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.text2)
            .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
        }
        .onAppear {
            if devices.pm5State != .connected || devices.strapState != .connected { startScan() }
        }
        .onDisappear { devices.stopScan() }
        .task(id: scanStarted) {
            guard scanStarted != nil else { return }
            try? await Task.sleep(for: .seconds(Self.scanTimeout))
            if !Task.isCancelled, devices.discovered.isEmpty {
                scanTimedOut = true
                devices.stopScan()
            }
        }
    }

    private var strapDetail: String? {
        guard devices.strapState == .connected else { return nil }
        var parts: [String] = []
        if let hr = devices.snapshot.heartRate { parts.append(String(localized: "Puls \(hr)")) }
        if let b = devices.strapBattery { parts.append(String(localized: "Batterie \(b) %")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func startScan() {
        guard devices.bluetoothReady else { return }
        scanTimedOut = false
        devices.startScan()
        scanStarted = Date()
    }

    // MARK: Gerätekarte

    private func stateText(_ state: LinkState) -> String {
        switch state {
        case .connected: return String(localized: "verbunden")
        case .connecting: return String(localized: "verbindet …")
        case .scanning: return String(localized: "sucht …")
        case .idle: return String(localized: "nicht verbunden")
        }
    }

    private func deviceCard(kind: DiscoveredDevice.Kind, name: String?, state: LinkState, detail: String?) -> some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: kind == .pm5 ? "figure.rower" : "heart.fill")
                .font(.title2)
                .foregroundStyle(kind == .pm5 ? Theme.text : Theme.bad)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? (kind == .pm5 ? String(localized: "Concept2 PM5") : String(localized: "Pulsgurt")))
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(state == .connected ? Theme.ok : Theme.text3).frame(width: 8, height: 8)
                    Text(stateText(state))
                    if let detail { Text("· \(detail)") }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: DS.Space.s)
            if state == .connecting || state == .scanning {
                ProgressView()
            } else if name != nil {
                Menu {
                    Button("Vergessen", role: .destructive) { devices.disconnect(kind, forget: true) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.text2)
                }
                .accessibilityLabel(Text("Optionen"))
            }
        }
        .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
        .accessibilityElement(children: .combine)
    }

    // MARK: Suche

    @ViewBuilder
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("Geräte in der Nähe").font(.headline)
                if scanning { ProgressView().padding(.leading, 4) }
                Spacer()
                Button(scanning ? String(localized: "Sucht …") : String(localized: "Suchen")) { startScan() }
                    .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                    .disabled(!devices.bluetoothReady || scanning)
            }
            if !devices.bluetoothReady {
                Text("Bluetooth ist aus oder nicht erlaubt. In den Einstellungen des Geräts Bluetooth einschalten und RowCoach erlauben.")
                    .font(.subheadline).foregroundStyle(Theme.warn)
            } else if !devices.discovered.isEmpty {
                VStack(spacing: 0) {
                    ForEach(devices.discovered) { d in
                        Button { devices.connect(d) } label: {
                            HStack(spacing: DS.Space.m) {
                                Image(systemName: d.kind == .pm5 ? "figure.rower" : "heart.fill")
                                    .foregroundStyle(d.kind == .pm5 ? Theme.text : Theme.bad)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(.body.weight(.semibold))
                                    Text(d.kind == .pm5 ? String(localized: "Rudergerät") : String(localized: "Pulsgurt"))
                                        .font(.caption).foregroundStyle(Theme.text2)
                                }
                                Spacer()
                                Image(systemName: "cellularbars", variableValue: signal(d.rssi))
                                    .foregroundStyle(Theme.text2)
                                    .accessibilityLabel(Text("Signal"))
                                Text("Verbinden").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.link)
                            }
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if d.id != devices.discovered.last?.id { Divider().overlay(Theme.cardStroke) }
                    }
                }
                .padding(.horizontal, DS.Space.m)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            } else if scanTimedOut {
                Label("Nichts gefunden. Ist der PM5 auf „Connect“ und der Gurt angelegt? Dann erneut suchen.",
                      systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline).foregroundStyle(Theme.text2)
            } else if scanning {
                Text("Suche läuft …").font(.subheadline).foregroundStyle(Theme.text2)
            }
        }
    }

    /// Signalstärke 0…1 aus dBm (−90 schwach … −50 stark)
    private func signal(_ rssi: Int) -> Double {
        min(max((Double(rssi) + 90) / 40, 0), 1)
    }
}
