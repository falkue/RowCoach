import SwiftUI
import os
import UIKit
import RowCoachKit

/// Ruderbildschirm: hinten die 3D-Szene, darüber das HUD. Querformat (iPad) mit grossen Kacheln unten,
/// Hochformat (iPhone) kompakt. Nach dem Ziel wechselt die Ansicht zur Zusammenfassung.
/// Mit `plan` (Training): Phasenanzeige links oben, Countdown oben in der Mitte, Gesamtfortschritt statt
/// Streckenbalken, Tor in der 3D-Szene, Runden statt Ziel.
/// Mit `paceLine` (s/500 m, nur freies Rudern): Tempo-Linie in der 3D-Szene und Abstand links oben.
struct RowingView: View {
    let course: Course
    let plan: WorkoutPlan?
    /// Zieltempo der Tempo-Linie (s/500 m); nil = keine Linie
    let paceLine: Double?

    @Environment(SessionController.self) private var controller
    @Environment(DeviceManager.self) private var devices
    @Environment(SimulatorDevice.self) private var simulator
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.maxHR") private var maxHR = 185
    @AppStorage("profile.restHR") private var restHR = 55
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @State private var confirmEnd = false
    @State private var cue = TrainingCue()

    init(course: Course, plan: WorkoutPlan? = nil, paceLine: Double? = nil) {
        self.course = course
        self.plan = plan
        self.paceLine = paceLine
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
            if controller.phase == .idle || controller.course?.id != course.id || controller.plan?.id != plan?.id
                || controller.paceTarget != paceLineModel?.pace {
                controller.prepare(course: course, plan: plan, paceTarget: paceLineModel?.pace)
                cue.reset()
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: controller.phase) { _, phase in
            if phase == .idle { dismiss() }
        }
        .onChange(of: controller.planStatus) { _, status in
            if let status, let laps = controller.lapTrack { cue.update(status: status, laps: laps) }
        }
        .onChange(of: controller.planStatus?.phaseIndex) { _, _ in
            // Simulator-Ruderer folgt grob den Zielen der aktuellen Phase (für Demos und Tests)
            guard simulator.isRunning, let phase = controller.planStatus?.phase else { return }
            if let lo = phase.spmMin, let hi = phase.spmMax { simulator.strokeRate = (lo + hi) / 2 }
            if let r = phase.paceRange(best2k: TrainingSettings.best2k) {
                simulator.pace = (r.lowerBound + r.upperBound) / 2
            } else if phase.kind == .rest || phase.kind == .cooldown || phase.kind == .warmup {
                simulator.pace = TrainingSettings.best2k / 4 + 25
            }
        }
        .task {
            // Testbetrieb: Startargument `-demoFinishAfter <Sekunden>` beendet die Fahrt automatisch und speichert
            // (für Tests über die Mac-Session ohne Bedienung am iPad).
            let after = UserDefaults.standard.double(forKey: "demoFinishAfter")
            guard after > 0 else { return }
            let log = Logger(subsystem: "com.falkue.RowCoach", category: "Session")
            log.info("Demo-Ende geplant in \(Int(after), privacy: .public) s")
            do {
                try await Task.sleep(for: .seconds(after))
            } catch {
                log.info("Demo-Ende abgebrochen (Ansicht geschlossen)")
                return
            }
            log.info("Demo-Ende fällig, Phase: \(String(describing: controller.phase), privacy: .public)")
            if controller.phase == .active { controller.endAndSave() }
        }
    }

    /// Schliesst die Zusammenfassung; `onChange(of: phase)` schliesst dann den Vollbildschirm.
    private func close() {
        controller.close()
    }

    // MARK: Rudern

    private var session: RowingSession? { controller.session }
    private var snapshot: RowingSnapshot { devices.snapshot }
    private var pose: TrackPose {
        // Training: Position mit Runden (die Session selbst rechnet ohne Streckenende)
        if let laps = controller.lapTrack { return laps.pose(atDistance: session?.distance ?? 0) }
        return session?.pose ?? CourseTrack(course: course).pose(atDistance: 0)
    }
    /// Training läuft (Programm gewählt und Stand vorhanden)
    private var training: (plan: WorkoutPlan, status: PlanStatus)? {
        guard let p = controller.plan, let st = controller.planStatus else { return nil }
        return (p, st)
    }
    private var lap: Int {
        guard let laps = controller.lapTrack else { return 0 }
        return Laps.split(distance: session?.distance ?? 0, lapLength: laps.lapLength).lap
    }
    private var zones: HeartRateZones { HeartRateZones(maxHR: maxHR, restHR: restHR) }
    /// Tempo-Linie: nur beim freien Rudern (nie bei einem Training)
    private var paceLineModel: PaceLine? {
        guard plan == nil, controller.plan == nil, let p = paceLine, p > 0 else { return nil }
        return PaceLine(pace: p)
    }
    /// Abstand zur Tempo-Linie auf der Zeitbasis der angezeigten Zeit (Ruderzeit; die Linie hält bei Pausen an)
    private var paceGap: PaceLineGap? {
        guard let line = paceLineModel else { return nil }
        let total: Double? = controller.lapTrack == nil
            ? (session?.track.totalLength ?? CourseTrack(course: course).totalLength) : nil
        return line.gap(boatDistance: session?.distance ?? 0, activeTime: session?.activeTime ?? 0, total: total)
    }
    /// Figur rudert nur, solange die Fahrt läuft
    private var rowingStrokeRate: Int { session?.state == .rowing ? snapshot.strokeRate : 0 }

    private var rowing: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                RowingSceneView(course: course, pose: pose, strokeRate: rowingStrokeRate,
                                strokePhase: session?.state == .rowing ? devices.strokePhase() : nil,
                                gates: cue.gate.map { [$0] } ?? [],
                                paceLineDistance: paceGap?.lineDistance,
                                paceLineLaps: controller.lapTrack != nil)
                    .ignoresSafeArea()
                if wide {
                    wideHUD
                } else {
                    compactHUD
                }
                statusBanner
                // Countdown bzw. neue Phase: oben in der Mitte, zwischen Phasenanzeige und Navigator
                trainingCallout
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, wide ? 190 : geo.size.height * 0.36)
                    .allowsHitTesting(false)
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
            topBar(statSize: 34, showSpeed: true)
            progressPanel(height: 22)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .hudPanel()
            HStack(alignment: .top) {
                if let t = training {
                    PhasePanel(status: t.status, best2k: best2k, snapshot: snapshot, zones: zones)
                        .frame(width: 380)
                } else if let line = paceLineModel, let gap = paceGap {
                    PaceLinePanel(pace: line.pace, gap: gap)
                }
                Spacer()
                MiniMapView(course: course, pose: pose, size: 210)
            }
            Spacer(minLength: 0)
            // Mitte unten frei lassen, damit Ruderfigur und Skulls sichtbar bleiben
            HStack(alignment: .bottom, spacing: 12) {
                HStack(spacing: 12) {
                    paceTile(size: 52)
                    strokeTile(size: 52)
                }
                .frame(maxWidth: .infinity)
                Color.clear.frame(width: 300, height: 1)
                HStack(spacing: 12) {
                    heartTile(size: 52)
                    powerTile(size: 52)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
    }

    // Hochformat iPhone
    private var compactHUD: some View {
        VStack(spacing: 10) {
            topBar(statSize: 24)
            progressPanel(height: 12)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .hudPanel(cornerRadius: 12)
            HStack(alignment: .top, spacing: 8) {
                if let t = training {
                    PhasePanel(status: t.status, best2k: best2k, snapshot: snapshot, zones: zones, compact: true)
                } else if let line = paceLineModel, let gap = paceGap {
                    PaceLinePanel(pace: line.pace, gap: gap, compact: true)
                }
                Spacer(minLength: 0)
                MiniMapView(course: course, pose: pose, size: 120)
            }
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

    /// showSpeed: im Querformat wandert die Geschwindigkeit in die Kopfleiste, damit unten die Mitte frei bleibt
    private func topBar(statSize: CGFloat, showSpeed: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 20) {
            HUDStat(title: "Zeit", value: Format.duration(session?.activeTime ?? 0), size: statSize)
            HUDStat(title: "Distanz", value: Format.distance(session?.distance ?? 0), size: statSize)
            if let t = training {
                HUDStat(title: "Training noch",
                        value: t.status.finished ? "0:00" : Format.duration(t.status.estimatedRemaining), size: statSize)
            } else {
                HUDStat(title: "Bis zum Ziel",
                        value: Format.distance(session?.remaining ?? CourseTrack(course: course).totalLength),
                        size: statSize)
            }
            if showSpeed {
                HUDStat(title: "Geschwindigkeit", value: String(format: "%.1f km/h", snapshot.speed * 3.6), size: statSize)
            }
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

    // MARK: Training

    /// Fortschritt: beim Training über das ganze Programm (mit Runde), sonst über die Strecke
    @ViewBuilder
    private func progressPanel(height: CGFloat) -> some View {
        if let t = training {
            TrainingProgressPanel(plan: t.plan, status: t.status, best2k: best2k, lap: lap, height: height)
        } else {
            CourseProgressBar(progress: session?.progress ?? 0, turnAt: course.turns > 0 ? 0.5 : nil,
                              height: height > 12 ? 10 : 8)
        }
    }

    /// Countdown vor dem Wechsel, danach kurz der Name der neuen Phase
    @ViewBuilder
    private var trainingCallout: some View {
        if let t = training {
            if t.status.countdownActive {
                CountdownOverlay(status: t.status)
            } else if let at = controller.phaseChangedAt, Date().timeIntervalSince(at) < 3, let p = t.status.phase,
                      !t.status.finished {
                VStack(spacing: 4) {
                    Text(p.kind == .rest ? "Pause" : "Los!")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.phaseColor(p.kind))
                        .shadow(color: .black.opacity(0.6), radius: 8)
                    Text(p.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                }
                .allowsHitTesting(false)
            }
        }
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
        HUDTile(title: "Leistung", value: snapshot.displayPower > 0 ? "\(snapshot.displayPower)" : "–", unit: "W", size: size)
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
            } else if let at = controller.lapChangedAt, Date().timeIntervalSince(at) < 5 {
                banner(title: "Runde \(lap + 1)", text: "Zurück am Start – das Training geht weiter.")
            } else if training?.status.countdownActive != true,
                      let split = controller.lastSplit, let at = controller.lastSplitAt, Date().timeIntervalSince(at) < 5 {
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
