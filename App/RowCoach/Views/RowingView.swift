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
    /// Dialog „Fahrt beenden“ offen (die Fahrt ist dann angehalten)
    @State private var showEnd = false
    @State private var cue = TrainingCue()
    /// Andere Ruderer und Schiffe dieser Fahrt (nil = aus); je Fahrt neu mit eigenem Startwert
    @State private var traffic: TrafficModel?

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
                                    health: controller.discardedTooShort ? .notStored
                                        : (controller.phase == .saving ? .pending
                                           : (controller.healthSaved ? .saved : .notSaved)),
                                    healthNote: controller.healthNote)
                            // „Fertig“ unten als breite Taste – nicht an der Stelle von ✕ (kein Doppeltipp)
                            .safeAreaInset(edge: .bottom) {
                                DSFooterBar {
                                    Button("Fertig") { close() }
                                        .buttonStyle(PrimaryButtonStyle(compact: true))
                                        .disabled(controller.phase == .saving)
                                        .frame(maxWidth: 560)
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
                cue.plan = plan
                traffic = TrafficModel.make(course: course, paceTarget: paceLineModel?.pace, best2k: best2k)
            }
            // Testbetrieb `-demoRace 1`: Rennen gegen zwei computergesteuerte Boote (Grundlage für Turniere)
            if UserDefaults.standard.bool(forKey: "demoRace"), controller.race == nil {
                let ownPace = simulator.isRunning ? simulator.pace : best2k / 4 + 10
                controller.attachRace(Self.demoRace(course: course, ownPace: ownPace))
            }
            traffic?.raceMode = controller.race != nil
            if traffic == nil {
                traffic = TrafficModel.make(course: course, paceTarget: paceLineModel?.pace, best2k: best2k)
            }
            feedTraffic()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: controller.phase) { _, phase in
            if phase == .idle { dismiss() }
        }
        .onChange(of: session?.distance) { _, d in
            feedTraffic()
            // Freies Rudern: Halbzeit, „Noch 500 Meter“, Tempo-Linie (Sprachcoach)
            if controller.plan == nil, d != nil { feedCoach() }
        }
        // iPhone: Haptik beim Phasenwechsel (das iPad hat keine Taptic Engine)
        .sensoryFeedback(.impact(weight: .heavy), trigger: controller.planStatus?.phaseIndex)
        .onChange(of: session?.state == .rowing) { _, _ in feedTraffic() }
        .onChange(of: controller.planStatus) { _, status in
            if let status, let laps = controller.lapTrack { cue.update(status: status, laps: laps) }
            feedCoach()
        }
        // Sprachcoach etwa jede Sekunde, auch wenn sich nichts ändert (z. B. Stillstand in einer Belastung)
        .task(id: controller.phase == .active) {
            guard controller.phase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                feedCoach()
            }
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

    /// Rennen ohne Netz gegen zwei Boote mit gleichmässigem Tempo, bezogen auf das eigene Tempo `ownPace` (beim
    /// Simulator dessen Tempo): Anna ist 6 s/500 m schneller und zieht nach etwa einer halben Minute sichtbar vorbei,
    /// Ben ist 3 s langsamer, startet aber 30 m voraus (gleich zu sehen, wird nach einigen Minuten eingeholt).
    /// Beide starten mit dem ersten eigenen Schlag. Wer neben oder hinter dem eigenen Boot fährt, ist ausserhalb des
    /// Bildes (Kamera blickt nach vorn).
    static func demoRace(course: Course, ownPace: Double) -> RaceLink {
        let length = course.turns > 0 ? 2 * course.oneWayM : course.oneWayM
        let race = Race(id: "demo-\(UUID().uuidString.prefix(8))", courseId: course.id, target: .distance(length), lanes: 3)
        // eigene Erscheinung nach der Datenschutzregel (publicAppearance), Bots je Id stabil zufällig
        let profile = RowerProfileStore.shared
        let me = RaceParticipant(id: "me", displayName: profile.displayName, lane: 2, appearance: profile.appearance)
        let bots = [
            GhostRower.steady(participant: RaceParticipant(id: "bot-a", displayName: "Anna", lane: 1, source: .bot,
                                                           appearance: .random(seed: "bot-a")),
                              pace: ownPace - 6, strokeRate: 26, duration: 3600, finishDistance: length),
            GhostRower.steady(participant: RaceParticipant(id: "bot-b", displayName: "Ben", lane: 3, source: .bot,
                                                           appearance: .random(seed: "bot-b")),
                              pace: ownPace + 3, strokeRate: 22, duration: 3600, finishDistance: length, headStart: 30),
        ]
        let mark = RaceStartMark()
        let transport = GhostRaceTransport(ghosts: bots) { mark.raceTime(local: Date().timeIntervalSince1970) }
        return RaceLink(coordinator: RaceCoordinator(race: race, me: me), transports: [transport], start: mark)
    }

    /// Stand der Fahrt an den Verkehr (Tempi der anderen richten sich nach dem eigenen Durchschnitt)
    private func feedTraffic() {
        traffic?.raceMode = controller.race != nil
        traffic?.observe(distance: session?.distance ?? 0, activeTime: session?.activeTime ?? 0,
                         rowing: session?.state == .rowing)
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
    /// Füttert den Sprachcoach mit Planstand (Training) bzw. Stand auf der Strecke (freies Rudern) und den
    /// Messwerten. Erst ab dem ersten Schlag und nicht, während der Dialog „Fahrt beenden“ die Fahrt anhält.
    private func feedCoach() {
        guard let s = session, s.state != .ready, !s.isHeld else { return }
        var free: CoachFreeRide?
        if controller.plan == nil {
            let total = s.track.totalLength
            let pace = snapshot.pace
            let gap = paceGap
            free = CoachFreeRide(distance: s.distance, total: total, paceLineGap: gap?.meters,
                                 paceLineGapSeconds: gap?.seconds,
                                 estimatedRemaining: pace > 0 ? max(total - s.distance, 0) / 500 * pace : nil)
        }
        cue.coachTick(status: controller.plan == nil ? nil : controller.planStatus, free: free, snapshot: snapshot,
                      isRowing: s.state == .rowing, distance: s.distance)
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
                    .traffic(traffic)
                    .raceRowers(controller.raceStates)
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
                    .padding(.top, wide ? 200 : geo.size.height * 0.36)
                    .allowsHitTesting(false)
                if showEnd {
                    EndRideDialog(canSave: canSave, hasStarted: session.map { $0.state != .ready } ?? false,
                                  onContinue: closeEndDialog,
                                  onSave: {
                                      showEnd = false
                                      controller.endAndSave()
                                  },
                                  onDiscard: {
                                      showEnd = false
                                      controller.cancel()
                                  })
                    .transition(.opacity)
                }
            }
        }
        .background(Theme.bg)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .animation(.easeInOut(duration: 0.2), value: showEnd)
    }

    /// Fahrt lang genug zum Speichern (mindestens 100 m und 1 min)
    private var canSave: Bool {
        guard let s = session else { return false }
        return RideSaveRule.shouldKeep(distance: s.distance, activeDuration: s.activeTime)
    }

    private func openEndDialog() {
        controller.hold()
        showEnd = true
    }

    private func closeEndDialog() {
        showEnd = false
        controller.resumeFromHold()
    }

    // Querformat iPad
    private var wideHUD: some View {
        VStack(spacing: 14) {
            topBar(compact: false)
            progressPanel(compact: false)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .hudPanel()
            HStack(alignment: .top) {
                if let t = training {
                    PhasePanel(plan: t.plan, status: t.status)
                        .frame(width: 400)
                } else if let line = paceLineModel, let gap = paceGap {
                    PaceLinePanel(pace: line.pace, gap: gap)
                }
                Spacer()
                MiniMapView(course: course, pose: pose, size: 168, traffic: traffic)
            }
            Spacer(minLength: 0)
            // Mitte unten frei lassen, damit Ruderfigur und Skulls sichtbar bleiben. Tempo (und im Training die
            // Restzeit) bekommen die ganze Breite ihrer Seite, damit die grosse Zahl nie abgeschnitten wird.
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    strokeTile(compact: false)
                        .frame(maxWidth: 280)
                    paceTile(compact: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 220, height: 1)
                VStack(alignment: .trailing, spacing: 12) {
                    if let t = training {
                        heartTile(compact: false)
                            .frame(maxWidth: 300)
                        remainingTile(t.status, compact: false)
                    } else {
                        HStack(alignment: .bottom, spacing: 12) {
                            heartTile(compact: false)
                            powerTile(compact: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
    }

    // Hochformat iPhone
    private var compactHUD: some View {
        VStack(spacing: 10) {
            topBar(compact: true)
            progressPanel(compact: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .hudPanel(cornerRadius: 12)
            HStack(alignment: .top, spacing: 8) {
                if let t = training {
                    PhasePanel(plan: t.plan, status: t.status, compact: true)
                } else if let line = paceLineModel, let gap = paceGap {
                    PaceLinePanel(pace: line.pace, gap: gap, compact: true)
                }
                Spacer(minLength: 0)
                MiniMapView(course: course, pose: pose, size: 96, traffic: traffic)
            }
            Spacer(minLength: 0)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                if let t = training {
                    GridRow {
                        paceTile(compact: true)
                        remainingTile(t.status, compact: true)
                    }
                    GridRow {
                        strokeTile(compact: true)
                        heartTile(compact: true)
                    }
                } else {
                    GridRow {
                        paceTile(compact: true)
                            .gridCellColumns(2)
                    }
                    GridRow {
                        strokeTile(compact: true)
                        heartTile(compact: true)
                    }
                }
            }
        }
        .padding(12)
    }

    /// Kopfleiste: Zeit, Distanz, Rest (bis zum Ziel bzw. Training noch), Zustand, ✕
    private func topBar(compact: Bool) -> some View {
        let size = DS.HUD.top(compact: compact)
        return HStack(alignment: .center, spacing: compact ? 14 : 28) {
            HUDStat(title: String(localized: "Zeit"), value: Format.duration(session?.activeTime ?? 0), size: size,
                    compact: compact)
            HUDStat(title: String(localized: "Distanz"), value: Format.distance(session?.distance ?? 0), size: size,
                    compact: compact)
            if let t = training {
                HUDStat(title: String(localized: "Training noch"),
                        value: t.status.finished ? "0:00" : Format.duration(t.status.estimatedRemaining), size: size,
                        compact: compact)
            } else {
                HUDStat(title: String(localized: "Bis zum Ziel"),
                        value: Format.distance(session?.remaining ?? CourseTrack(course: course).totalLength),
                        size: size, compact: compact)
            }
            Spacer(minLength: 0)
            stateBadge
            Button {
                openEndDialog()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: compact ? 18 : 22, weight: .bold))
                    .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .foregroundStyle(Theme.text)
            .accessibilityLabel(Text("Fahrt beenden"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 8 : 10)
        .hudPanel()
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch session?.state {
        case .paused:
            DSChip(String(localized: "Pause"), tone: .warn)
        case .ready, .none:
            DSChip(String(localized: "Bereit"), tone: .neutral)
        case .rowing:
            if devices.simulatorActive { DSChip(String(localized: "Simulator"), tone: .neutral) }
        case .finished:
            DSChip(String(localized: "Ziel"), tone: .ok)
        }
    }

    // MARK: Training

    /// Fortschritt: beim Training über das ganze Programm (mit Runde), sonst über die Strecke
    @ViewBuilder
    private func progressPanel(compact: Bool) -> some View {
        if let t = training {
            TrainingProgressPanel(plan: t.plan, status: t.status, best2k: best2k, lap: lap,
                                  height: compact ? 12 : 22, compact: compact)
        } else {
            CourseProgressBar(progress: session?.progress ?? 0, turnAt: course.turns > 0 ? 0.5 : nil,
                              height: compact ? 8 : 10)
        }
    }

    /// Countdown vor dem Wechsel, danach kurz die neue Phase
    @ViewBuilder
    private var trainingCallout: some View {
        if let t = training {
            if t.status.countdownActive {
                CountdownOverlay(plan: t.plan, status: t.status)
            } else if let at = controller.phaseChangedAt, Date().timeIntervalSince(at) < 3, let p = t.status.phase,
                      !t.status.finished {
                VStack(spacing: 4) {
                    Text(p.kind == .rest ? String(localized: "Pause") : String(localized: "Los!"))
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.phaseColor(p))
                        .shadow(color: .black.opacity(0.6), radius: 8)
                    Text(PhaseText.kind(plan: t.plan, index: t.status.phaseIndex))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Kacheln

    /// Ziele der aktuellen Phase (nur im Training)
    private var phaseTargets: (pace: ClosedRange<Double>?, spm: ClosedRange<Int>?, zone: Int?) {
        guard let p = training?.status.phase, !(training?.status.finished ?? true) else { return (nil, nil, nil) }
        return (p.paceRange(best2k: best2k), p.spmRange, p.hrZone)
    }

    /// Tempo /500 m: grösste Zahl; im Training mit Ziel und Ampel
    private func paceTile(compact: Bool) -> some View {
        let target = phaseTargets.pace
        let light: TargetLight? = target.map { TargetLight.pace(snapshot.pace, target: $0) }
        return HUDTile(title: String(localized: "Tempo"), value: Format.pace(snapshot.pace), unit: "/500 m",
                       detail: target.map { String(localized: "Ziel \(PlanFormat.paceRange($0))") },
                       light: light, shouldIncrease: LightSymbol.paceDirection(snapshot.pace, target: target),
                       size: DS.HUD.main(compact: compact), compact: compact)
    }

    private func strokeTile(compact: Bool) -> some View {
        let target = phaseTargets.spm
        let light: TargetLight? = target.map { TargetLight.strokeRate(snapshot.strokeRate, target: $0) }
        let range = target.map { Double($0.lowerBound)...Double($0.upperBound) }
        return HUDTile(title: String(localized: "Schlagzahl"),
                       value: snapshot.strokeRate > 0 ? "\(snapshot.strokeRate)" : "–", unit: "/min",
                       detail: target.map { String(localized: "Ziel \(PlanFormat.strokeRate($0))") },
                       light: light,
                       shouldIncrease: LightSymbol.valueDirection(Double(snapshot.strokeRate), target: range),
                       size: DS.HUD.tile(compact: compact), compact: compact)
    }

    /// Restzeit der Phase, im Training so gross wie das Tempo
    private func remainingTile(_ status: PlanStatus, compact: Bool) -> some View {
        HUDTile(title: PhaseText.remainingTitle(status.phase), value: PhaseText.remaining(status),
                detail: status.phase?.kind == .rest ? (status.phase?.activeRest == false
                    ? String(localized: "Stillstand") : String(localized: "locker weiterrudern")) : nil,
                accentBar: Theme.phaseColor(status.phase),
                size: DS.HUD.main(compact: compact), compact: compact)
    }

    private func powerTile(compact: Bool) -> some View {
        HUDTile(title: String(localized: "Leistung"),
                value: snapshot.displayPower > 0 ? "\(snapshot.displayPower)" : "–", unit: "W",
                size: DS.HUD.tile(compact: compact), compact: compact)
    }

    /// Puls: Zahl weiss, Zone als Farbbalken; im Training mit Zielzone und Ampel
    private func heartTile(compact: Bool) -> some View {
        let targetZone = phaseTargets.zone
        guard let hr = snapshot.heartRate else {
            return HUDTile(title: String(localized: "Puls"), value: "–", unit: "/min",
                           detail: String(localized: "kein Gurt"), size: DS.HUD.tile(compact: compact),
                           compact: compact)
        }
        let z = zones.zone(for: hr)
        let light: TargetLight? = targetZone.map { TargetLight.heartRate(zone: z, target: $0) }
        // kurz, damit nichts abgeschnitten wird: „Z2 → Z4“ (aktuell → Ziel)
        let current = z == 0 ? String(localized: "locker") : "Z\(z)"
        let detail = targetZone.map { "\(current) → Z\($0)" } ?? Theme.zoneName(z)
        return HUDTile(title: String(localized: "Puls"), value: "\(hr)", unit: "/min", detail: detail, light: light,
                       shouldIncrease: targetZone.map { z < $0 }, accentBar: Theme.zoneColor(z),
                       size: DS.HUD.tile(compact: compact), compact: compact)
    }

    // MARK: Hinweise in der Bildmitte

    @ViewBuilder
    private var statusBanner: some View {
        if let s = session {
            if s.state == .ready {
                banner(title: String(localized: "Bereit"), text: readyHint)
            } else if s.state == .paused {
                banner(title: String(localized: "Pause"), text: String(localized: "Weiter mit dem nächsten Schlag."))
            } else if let at = controller.lapChangedAt, Date().timeIntervalSince(at) < 5 {
                banner(title: String(localized: "Runde \(lap + 1)"), text: String(localized: "Zurück am Start – das Training geht weiter."))
            } else if training?.status.countdownActive != true,
                      let split = controller.lastSplit, let at = controller.lastSplitAt, Date().timeIntervalSince(at) < 5 {
                banner(title: String(localized: "\(Int(split.endDistance)) m"), text: String(localized: "Split \(Format.pace(split.pace)) /500 m"))
            } else if let at = controller.turnReachedAt, Date().timeIntervalSince(at) < 5 {
                banner(title: String(localized: "Wende"), text: String(localized: "Halbzeit – zurück zum Start."))
            }
        }
    }

    private var readyHint: String {
        if devices.simulatorActive { return String(localized: "Der Simulator startet die Fahrt mit dem ersten Schlag.") }
        if devices.pm5State != .connected { return String(localized: "PM5 nicht verbunden – auf dem Startbildschirm über den Gerätestatus koppeln.") }
        return String(localized: "Der erste Schlag startet die Fahrt.")
    }

    private func banner(title: String, text: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
            Text(text).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .hudPanel(cornerRadius: 20)
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
    }
}
