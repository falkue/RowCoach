import SwiftUI

/// Geräte koppeln: PM5 und Polar-Gurt (H9/H10) suchen, verbinden, vergessen.
struct DevicesView: View {
    @Environment(DeviceManager.self) private var devices

    var body: some View {
        NavigationStack {
            List {
                Section("Verbunden") {
                    row(kind: .pm5, name: devices.pm5Name, state: devices.pm5State)
                    row(kind: .heartRate, name: devices.strapName, state: devices.strapState)
                }
                Section {
                    ForEach(devices.discovered) { d in
                        Button {
                            devices.connect(d)
                        } label: {
                            HStack {
                                Image(systemName: d.kind == .pm5 ? "figure.rower" : "heart.fill")
                                VStack(alignment: .leading) {
                                    Text(d.name)
                                    Text(d.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Gefunden")
                } footer: {
                    Text("PM5: im Monitor „Connect“ wählen, damit er sichtbar ist. Polar-Gurt: anlegen und Elektroden befeuchten. Den Gurt nicht zusätzlich in den iPad-Bluetooth-Einstellungen koppeln.")
                }
                if let e = devices.lastError {
                    Section { Text(e).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Geräte")
            .toolbar {
                Button("Suchen") { devices.startScan() }.disabled(!devices.bluetoothReady)
            }
            .onDisappear { devices.stopScan() }
        }
    }

    @ViewBuilder
    private func row(kind: DiscoveredDevice.Kind, name: String?, state: LinkState) -> some View {
        HStack {
            Image(systemName: kind == .pm5 ? "figure.rower" : "heart.fill")
            VStack(alignment: .leading) {
                Text(name ?? kind.rawValue)
                Text(state.rawValue).font(.caption).foregroundStyle(state == .connected ? .green : .secondary)
            }
            Spacer()
            if name != nil {
                Button("Vergessen", role: .destructive) { devices.disconnect(kind, forget: true) }
                    .buttonStyle(.borderless)
            }
        }
    }
}
