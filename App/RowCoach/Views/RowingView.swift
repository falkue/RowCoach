import SwiftUI
import UIKit
import RowCoachKit

/// Ruderbildschirm: hinten die 3D-Szene, darüber das HUD. Querformat (iPad) mit grossen Kacheln unten,
/// Hochformat (iPhone) kompakt. Nach dem Ziel wechselt die Ansicht zur Zusammenfassung.
struct RowingView: View {
    let course: Course

    @Environment(SessionController.self) private var controller
    @Environment(DeviceManager.self) private var devices
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.maxHR") private var maxHR = 185
    @AppStorage("profile.restHR") private var restHR = 55
    @State private var confirmEnd = false

    init(course: Course) {
        self.course = course
    }

    var body: some View {
        Group {
            switch controller.phase {
            case .saving, .done:
                if let record = controller.record {
                    NavigationStack {
                        SummaryView(record: record,
                                    health: controller.phase == .saving ? .pending
                                        : (controller.healthSaved ? .saved : .notSaved),
                                    healthNote: controller.healthNote)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Fertig") { close() }
                                        .disabled(controller.phase == .saving)
                                }
                            }
                    }
                } else {
                    ProgressView()
                }
            case .idle, .active:
                rowing
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if controller.phase == .idle || controller.course?.id != course.id {
                controller.prepare(course: course)
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: controller.phase) { _, phase in
            if phase == .idle { dismiss() }
        }
    }

    /// Schliesst die Zusammenfassung; `onChange(of: phase)` schliesst dann den Vollbildschirm.
    private func close() {
        controller.close()
    }

    // MARK: Rudern

    private var session: RowingSession? { controller.session }
    private var snapshot: RowingSnapshot { devices.snapshot }
    private var pose: TrackPose { session?.pose ?? CourseTrack(course: course).pose(atDistance: 0) }
    private var zones: HeartRateZones { HeartRateZones(maxHR: maxHR, restHR: restHR) }
    /// Figur rudert nur, solange die Fahrt läuft
    private var rowingStrokeRate: Int { session?.state == .rowing ? snapshot.strokeRate : 0 }

    private var rowing: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                RowingSceneView(course: course, pose: pose, strokeRate: rowingStrokeRate, strokePhase: nil)
                    .ignoresSafeArea()
                if wide {
                    wideHUD
                } else {
                    compactHUD
                }
                statusBanner
            }
        }
        .background(Theme.background)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .confirmationDialog("Fahrt beenden?", isPresented: $confirmEnd, titleVisibility: .visible) {
            if let s = session, s.state != .ready {
                Button("Beenden und speichern") { controller.endAndSave() }
            }
            Button("Verwerfen", role: .destructive) { controller.cancel() }
            Button("Weiterrudern", role: .cancel) {}
        } message: {
            Text(session?.state == .ready ? "Es wurde noch nicht gerudert." : "Das Training wird bis hierher gespeichert.")
        }
    }

    // Querformat iPad
    private var wideHUD: some View {
        VStack(spacing: 14) {
            topBar(statSize: 34)
            CourseProgressBar(progress: session?.progress ?? 0, turnAt: course.turns > 0 ? 0.5 : nil)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .hudPanel()
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                paceTile(size: 56)
                speedTile(size: 56)
                strokeTile(size: 56)
                heartTile(size: 56)
                powerTile(size: 56)
            }
        }
        .padding(20)
    }

    // Hochformat iPhone
    private var compactHUD: some View {
        VStack(spacing: 10) {
            topBar(statSize: 24)
            CourseProgressBar(progress: session?.progress ?? 0, turnAt: course.turns > 0 ? 0.5 : nil, height: 8)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .hudPanel(cornerRadius: 12)
            Spacer(minLength: 0)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    paceTile(size: 40)
                    heartTile(size: 40)
                }
                GridRow {
                    strokeTile(size: 34)
                    powerTile(size: 34)
                }
                GridRow {
                    speedTile(size: 34)
                        .gridCellColumns(2)
                }
            }
        }
        .padding(12)
    }

    private func topBar(statSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 20) {
            HUDStat(title: "Zeit", value: Format.duration(session?.activeTime ?? 0), size: statSize)
            HUDStat(title: "Distanz", value: Format.distance(session?.distance ?? 0), size: statSize)
            HUDStat(title: "Bis zum Ziel", value: Format.distance(session?.remaining ?? CourseTrack(course: course).totalLength),
                    size: statSize)
            Spacer(minLength: 0)
            stateBadge
            Button {
                confirmEnd = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Fahrt beenden")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .hudPanel()
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch session?.state {
        case .paused:
            badge("Pause", color: .orange)
        case .ready, .none:
            badge("Bereit", color: Theme.accent)
        case .rowing:
            if devices.simulatorActive { badge("Simulator", color: .purple) }
        case .finished:
            badge("Ziel", color: .green)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.85)))
            .foregroundStyle(.black)
    }

    // MARK: Kacheln

    private func paceTile(size: CGFloat) -> some View {
        HUDTile(title: "Tempo", value: Format.pace(snapshot.pace), unit: "/500 m", size: size)
    }

    private func speedTile(size: CGFloat) -> some View {
        HUDTile(title: "Geschwindigkeit", value: String(format: "%.1f", snapshot.speed * 3.6), unit: "km/h", size: size)
    }

    private func strokeTile(size: CGFloat) -> some View {
        HUDTile(title: "Schlagzahl", value: snapshot.strokeRate > 0 ? "\(snapshot.strokeRate)" : "–", unit: "/min",
                size: size)
    }

    private func powerTile(size: CGFloat) -> some View {
        HUDTile(title: "Leistung", value: snapshot.power > 0 ? "\(snapshot.power)" : "–", unit: "W", size: size)
    }

    private func heartTile(size: CGFloat) -> some View {
        if let hr = snapshot.heartRate {
            let z = zones.zone(for: hr)
            return HUDTile(title: "Puls", value: "\(hr)", unit: "bpm", detail: Theme.zoneName(z),
                           tint: Theme.zoneColor(z), size: size)
        }
        return HUDTile(title: "Puls", value: "–", unit: "bpm", detail: "kein Gurt", size: size)
    }

    // MARK: Hinweise in der Bildmitte

    @ViewBuilder
    private var statusBanner: some View {
        if let s = session {
            if s.state == .ready {
                banner(title: "Bereit", text: readyHint)
            } else if s.state == .paused {
                banner(title: "Pause", text: "Weiter mit dem nächsten Schlag.")
            } else if let split = controller.lastSplit, let at = controller.lastSplitAt, Date().timeIntervalSince(at) < 5 {
                banner(title: "\(Int(split.endDistance)) m", text: "Split \(Format.pace(split.pace)) /500 m")
            } else if let at = controller.turnReachedAt, Date().timeIntervalSince(at) < 5 {
                banner(title: "Wende", text: "Halbzeit – zurück zum Start.")
            }
        }
    }

    private var readyHint: String {
        if devices.simulatorActive { return "Der Simulator startet die Fahrt mit dem ersten Schlag." }
        if devices.pm5State != .connected { return "PM5 nicht verbunden – unter „Geräte“ koppeln oder den Simulator einschalten." }
        return "Der erste Schlag startet die Fahrt."
    }

    private func banner(title: String, text: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(text).font(.headline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .hudPanel(cornerRadius: 20)
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
    }
}
