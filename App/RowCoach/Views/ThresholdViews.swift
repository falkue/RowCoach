import SwiftUI
import RowCoachKit

// Schwelle und Zonen (docs/schwelle/SPEC.md 4, 6, 9): Einstellungen → Profil → „Schwelle & Zonen“, Testauswahl mit
// Gesundheitsfragen, Testergebnis nach der Fahrt, Bedienelemente im Test (Talk-Test, „Ich kann nicht mehr“) und die
// Zeile „Ziele aus Schwelle …“. Die Logik liegt in RowCoachKit (Threshold/), der Zustand in `ThresholdStore`.

// MARK: - Texte

enum ThresholdFormat {
    /// „162 W“
    static func watts(_ w: Double) -> String { "\(Int(w.rounded())) W" }

    /// „2:09.3“ (Tempo /500 m)
    static func pace(_ p: Double) -> String { Format.pace(p) }

    /// „162 W · 2:09.3 /500 m“
    static func threshold(_ w: Double) -> String {
        let wattsText = watts(w), paceText = pace(ThresholdMath.pace(watts: w))
        return String(localized: "\(wattsText) · \(paceText) /500 m")
    }

    /// „12.11.2026“
    static func date(_ d: Date) -> String { d.formatted(date: .numeric, time: .omitted) }

    /// „± 3 % (157–167 W)“
    static func uncertainty(_ w: Double, sigma: Double) -> String {
        let pctText = String(format: "%.0f", sigma.rounded())
        let lo = watts(w * (1 - sigma / 100)), hi = watts(w * (1 + sigma / 100))
        let rangeText = "\(lo.replacingOccurrences(of: " W", with: ""))–\(hi)"
        return "± \(pctText) % (\(rangeText))"
    }

    /// „+5 %“ / „−4 %“
    static func change(_ pct: Double) -> String {
        let r = Int(pct.rounded())
        return r >= 0 ? "+\(r) %" : "−\(abs(r)) %"
    }

    /// Quelle mit Testname: „Schwellentest 20 Minuten (FTP)“ bzw. „Eingabe Watt“
    static func source(_ e: ThresholdEstimate) -> String {
        if let id = e.planId, let plan = PlanLibrary.plan(id: id) { return plan.shortName }
        return e.source?.title ?? e.kind
    }

    /// „aus Test 30 min, 12.11.2026“
    static func origin(_ e: ThresholdEstimate) -> String {
        let sourceText = source(e), dateText = date(e.date)
        return String(localized: "\(sourceText), \(dateText)")
    }

    static func confidenceTone(_ c: ThresholdConfidence?) -> DSChip.Tone {
        switch c {
        case .high?: return .ok
        case .medium?: return .hint
        case .low?, nil: return .warn
        }
    }
}

// MARK: - Zeile „Ziele aus Schwelle …“

/// Kleine Zeile überall, wo Ziele stehen: „Ziele aus Schwelle 162 W (Test 30 min, 12.11.)“, Farbe nach Unsicherheit;
/// bei niedriger Sicherheit „Test empfohlen“.
struct ThresholdTargetLine: View {
    @State private var store = ThresholdStore.shared

    var body: some View {
        if let a = store.active {
            let wattsText = ThresholdFormat.watts(a.powerW)
            let originText = store.isDefault ? String(localized: "Standardwert") : ThresholdFormat.origin(a)
            HStack(spacing: DS.Space.s) {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                Text("Ziele aus Schwelle \(wattsText) (\(originText))")
                if store.confidence == .low {
                    Text("Test empfohlen").foregroundStyle(Theme.warn)
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.text2)
        }
    }

    private var color: Color {
        switch store.confidence {
        case .high?: return Theme.ok
        case .medium?: return Theme.link
        default: return Theme.warn
        }
    }
}

// MARK: - Einstellungen → Schwelle & Zonen

struct ThresholdSettingsView: View {
    @State private var store = ThresholdStore.shared
    @Environment(\.rowingLaunch) private var launch
    @Environment(\.closeSettings) private var closeSettings
    @Environment(DeviceManager.self) private var devices

    private enum InputMode: String, CaseIterable, Identifiable {
        case watts, pace, best2k, unknown
        var id: String { rawValue }
    }

    @State private var mode = InputMode.watts
    @State private var wattsInput: Double?
    @State private var paceMinutes = 2
    @State private var paceSeconds = 10
    @State private var best2kInput = PaceTargets.defaultBest2k
    @State private var measuredOn = Date()
    @State private var maxHRInput: Int?
    @State private var restHRInput: Int?
    @State private var lthrInput: Int?
    @State private var birthYearInput: Int?
    @AppStorage(ThresholdSettings.heartModelKey) private var heartModel = ""
    @State private var showHealth = false
    @State private var pendingTest: String?
    @State private var saved = false
    /// Test gesperrt (z. B. Pulsgurt fehlt): Meldung nach Tippen auf die Retest-Karte
    @State private var blockedReason: String?
    /// direkt zum Abschnitt „Puls“ springen (Einstellungen → Profil → Maximal-/Ruhepuls)
    private let scrollToHeart: Bool
    private static let heartAnchor = "threshold.heart"

    init(scrollToHeart: Bool = false) {
        self.scrollToHeart = scrollToHeart
    }

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear {
                    guard scrollToHeart else { return }
                    // nach dem Aufbau der Liste springen (sonst kennt sie die Zeile noch nicht)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation { proxy.scrollTo(Self.heartAnchor, anchor: .top) }
                    }
                }
        }
    }

    private var form: some View {
        Form {
            headSection
            if let card = store.retestCard {
                Section {
                    ThresholdRetestCardView(card: card, onTest: { requestTest($0) },
                                            onDismiss: { store.dismissRetestCard(card.kind) })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            inputSection
            heartSection
            zonesSection
            historySection
            testsSection
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text("Schwelle & Zonen"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadInputs)
        .onChange(of: maxHRInput) { _, _ in saveHeartIfChanged() }
        .onChange(of: restHRInput) { _, _ in saveHeartIfChanged() }
        .onChange(of: lthrInput) { _, _ in saveHeartIfChanged() }
        .onChange(of: birthYearInput) { _, _ in saveHeartIfChanged() }
        .alert(blockedReason ?? "", isPresented: Binding(get: { blockedReason != nil }, set: { if !$0 { blockedReason = nil } })) {
            Button("OK", role: .cancel) { blockedReason = nil }
        }
        .sheet(isPresented: $showHealth) {
            HealthScreenSheet(screen: store.profile.healthScreen) { answers in
                store.setHealthScreen(answers)
                if let id = pendingTest, !(answers?.blocksMaximalTests ?? true) { start(id) }
                pendingTest = nil
            }
        }
    }

    // MARK: Kopf

    private var headSection: some View {
        Section {
            if let a = store.active {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(ThresholdFormat.threshold(a.powerW)).font(.title2.bold().monospacedDigit())
                    Text(store.isDefault ? String(localized: "Standardwert – noch nicht gemessen") : ThresholdFormat.origin(a))
                        .font(.subheadline).foregroundStyle(Theme.text2)
                    if let sigma = store.activeSigma {
                        HStack(spacing: DS.Space.s) {
                            Text(ThresholdFormat.uncertainty(a.powerW, sigma: sigma)).font(.subheadline.monospacedDigit())
                            DSChip(store.confidence?.title ?? "", tone: ThresholdFormat.confidenceTone(store.confidence))
                        }
                    }
                    if let t2k = store.profile.mirrorBest2k {
                        let t2kText = Format.duration(t2k)
                        Text("entspricht 2000 m ≈ \(t2kText)").font(.subheadline).foregroundStyle(Theme.text2)
                    }
                    if let line = ThresholdSelector.enduranceProfile(store.profile) {
                        Text(line).font(.footnote).foregroundStyle(Theme.text2)
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
            if store.undoTarget != nil {
                Button("Rückgängig: vorherige Schwelle verwenden") { store.undo() }.foregroundStyle(Theme.link)
            }
            if let p = store.proposal {
                let msg = proposalText(p)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text(msg).font(.subheadline)
                    HStack {
                        Button("Übernehmen") { store.accept(id: p.estimate.id) }.foregroundStyle(Theme.link)
                        Spacer()
                        Button("Behalten") { store.keep(id: p.estimate.id) }.foregroundStyle(Theme.text2)
                    }
                    .buttonStyle(.borderless)
                }
            }
            ForEach(store.pendingCandidates) { c in
                PendingResultRow(estimate: c)
            }
        } header: {
            Text("Aktive Schwelle")
        } footer: {
            Text("Schwelle = Leistung, die du etwa 30 Minuten halten kannst. Leistungs-, Tempo- und Pulszonen und die Tempoziele aller Programme richten sich danach.")
        }
    }

    private func proposalText(_ p: ThresholdProposal) -> String {
        let dateText = ThresholdFormat.date(p.estimate.date)
        let newText = ThresholdFormat.watts(p.estimate.powerW)
        let oldText = ThresholdFormat.watts(p.current.powerW)
        return String(localized: "Dein Ergebnis vom \(dateText) ergab \(newText), eingetragen sind \(oldText). Übernehmen?")
    }

    // MARK: Eingabe

    private var inputSection: some View {
        Section {
            Picker("Eingabe", selection: $mode) {
                Text("Watt").tag(InputMode.watts)
                Text("Tempo").tag(InputMode.pace)
                Text("2000 m").tag(InputMode.best2k)
                Text("Weiss nicht").tag(InputMode.unknown)
            }
            .pickerStyle(.segmented)
            switch mode {
            case .watts:
                // Drehrad 40–600 W (gültige Spanne der Eingabe)
                WheelIntRow(label: Text("Schwellenleistung"),
                            value: Binding(get: { wattsInput.map { Int($0.rounded()) } },
                                           set: { wattsInput = $0.map(Double.init) }),
                            range: 40...600, unit: "W", fallback: Int((store.profile.thresholdW ?? 180).rounded()))
            case .pace:
                LabeledContent {
                    HStack(spacing: 0) {
                        Picker(selection: $paceMinutes) {
                            ForEach(1...3, id: \.self) { Text("\($0) min").tag($0) }
                        } label: { Text("Minuten") }
                        Picker(selection: $paceSeconds) {
                            ForEach(0..<60, id: \.self) { Text(String(format: "%02d s", $0)).tag($0) }
                        } label: { Text("Sekunden") }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 200, height: 120)
                } label: {
                    Text("Tempo an der Schwelle /500 m")
                }
            case .best2k:
                Best2kWheel(seconds: $best2kInput)
            case .unknown:
                Text("Kein Problem: Ein Test misst deine Schwelle. Der Stufentest geht ohne Ausbelastung, der 20-Minuten-Test ist genauer.")
                    .font(.subheadline)
            }
            if mode != .unknown {
                DatePicker(selection: $measuredOn, in: ...Date(), displayedComponents: .date) {
                    Text("Wann gemessen?")
                }
                Button(saved ? String(localized: "Gespeichert") : String(localized: "Als Schwelle speichern")) { saveInput() }
                    .foregroundStyle(Theme.link)
                    .disabled(!inputValid)
                if let warning = inputWarning {
                    Text(warning).font(.footnote).foregroundStyle(Theme.warn)
                }
            }
        } header: {
            Text("Schwelle eingeben")
        } footer: {
            Text("Gültig: 40–600 W, Tempo 1:15–4:00 /500 m, 2000 m in 5:20–15:00. Deine Eingabe bleibt aktiv, bis du sie änderst; Tests und Fahrten schlagen nur vor.")
        }
    }

    private var paceInput: Double { Double(paceMinutes * 60 + paceSeconds) }

    private var inputValid: Bool {
        switch mode {
        case .watts: return wattsInput.map { (40...600).contains($0) } ?? false
        case .pace: return (75...240).contains(paceInput)
        case .best2k: return (320...900).contains(best2kInput)
        case .unknown: return false
        }
    }

    private var inputWarning: String? {
        guard !inputValid, mode != .unknown else { return nil }
        switch mode {
        case .watts: return wattsInput == nil ? nil : String(localized: "Schwellenleistung zwischen 40 und 600 W eingeben.")
        case .pace: return String(localized: "Tempo zwischen 1:15 und 4:00 /500 m wählen.")
        default: return nil
        }
    }

    private func saveInput() {
        switch mode {
        case .watts: if let w = wattsInput { store.enterPower(w, date: measuredOn) }
        case .pace: store.enterPace(paceInput, date: measuredOn)
        case .best2k: store.enter2k(best2kInput, date: measuredOn)
        case .unknown: break
        }
        saved = true
    }

    // MARK: Puls

    private var heartSection: some View {
        Section {
            intRow(Text("Maximalpuls"), value: $maxHRInput, range: 120...230, unit: "/min", fallback: 185)
                .id(Self.heartAnchor)
            intRow(Text("Ruhepuls"), value: $restHRInput, range: 30...110, unit: "/min", fallback: 55)
            intRow(Text("Schwellenpuls (LTHR)"), value: $lthrInput, range: 100...215, unit: "/min", fallback: 165)
            if maxHRInput == nil {
                intRow(Text("Geburtsjahr"), value: $birthYearInput, range: 1930...Self.latestBirthYear, unit: "",
                       fallback: 1975)
            }
            Picker("Pulszonen nach", selection: $heartModel) {
                Text("Automatisch").tag("")
                Text("Schwellenpuls").tag(HeartRateZones.ModelKind.lthr.rawValue)
                Text("Herzfrequenzreserve").tag(HeartRateZones.ModelKind.reserve.rawValue)
                Text("Prozent vom Maximalpuls").tag(HeartRateZones.ModelKind.percentMax.rawValue)
            }
            Button("Pulswerte speichern") {
                store.setHeart(maxHR: maxHRInput, restHR: restHRInput, lthr: lthrInput, birthYear: birthYearInput)
            }
            .foregroundStyle(Theme.link)
        } header: {
            Text("Puls")
        } footer: {
            Text("Schwellenpuls: Durchschnittspuls der letzten 20 Minuten eines 30-Minuten-Tests. Ohne Maximalpuls schätzt die App ihn aus dem Alter (208 − 0,7 × Alter) – nur ein Startwert.")
        }
    }

    /// Pulswerte nach jeder Eingabe übernehmen (Zahlenfelder melden erst beim Verlassen); nur bei echter Änderung,
    /// damit z. B. ein gemessener Maximalpuls nicht als Eingabe umgestempelt wird
    private func saveHeartIfChanged() {
        let h = store.heart
        guard maxHRInput != h.maxHR || restHRInput != h.restHR || lthrInput != h.lthr || birthYearInput != h.birthYear
        else { return }
        store.setHeart(maxHR: maxHRInput, restHR: restHRInput, lthr: lthrInput, birthYear: birthYearInput)
    }

    /// Pulswert bzw. Geburtsjahr per Drehrad (leer = nicht eingetragen, „Leeren“ im Popover)
    private func intRow(_ label: Text, value: Binding<Int?>, range: ClosedRange<Int>, unit: String,
                        fallback: Int) -> some View {
        WheelIntRow(label: label, value: value, range: range, unit: unit, fallback: fallback)
    }

    /// jüngstes wählbares Geburtsjahr (10 Jahre)
    private static var latestBirthYear: Int { Calendar.current.component(.year, from: Date()) - 10 }

    // MARK: Zonen

    private var zonesSection: some View {
        Section {
            if let t = store.profile.thresholdW {
                ThresholdZoneTable(threshold: t, heartZones: ThresholdSettings.zones().zones)
            }
        } header: {
            Text("Zonen")
        } footer: {
            if ThresholdSettings.zones().source == .estimated {
                Text("Pulszonen geschätzt – trag Maximal- und Ruhepuls ein oder mach einen Test.")
            } else {
                Text("Leistung und Tempo in Prozent der Schwelle (UT3 bis TR/AN); Puls nach dem gewählten Modell.")
            }
        }
    }

    // MARK: Verlauf

    private var historySection: some View {
        Section {
            ForEach(store.profile.estimates.prefix(30)) { e in
                NavigationLink {
                    ThresholdEstimateDetail(id: e.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ThresholdFormat.source(e)).font(.body)
                            Text(ThresholdFormat.date(e.date)).font(.footnote).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ThresholdFormat.watts(e.powerW)).font(.body.monospacedDigit())
                            statusChip(e)
                        }
                    }
                }
            }
        } header: {
            Text("Verlauf")
        }
    }

    @ViewBuilder
    private func statusChip(_ e: ThresholdEstimate) -> some View {
        switch e.statusValue {
        case .active: DSChip(String(localized: "aktiv"), tone: .ok)
        case .candidate: DSChip(e.isHintOnly ? String(localized: "Hinweis") : String(localized: "offen"), tone: .hint)
        case .rejected: DSChip(String(localized: "verworfen"))
        case .superseded:
            let sigmaText = String(format: "%.0f", store.sigma(e).rounded())
            DSChip("± " + sigmaText + " %")
        }
    }

    // MARK: Tests

    private var preferredTest: String {
        store.retestInput(hasHeartRateStrap: devices.strapState == .connected, isBeginner: false,
                          tested2k: store.profile.estimates.contains { $0.planId == "test-2000m" }).preferredTest
    }

    private var testsSection: some View {
        Section {
            ForEach(ThresholdTestGate.testIds, id: \.self) { id in
                if let plan = PlanLibrary.plan(id: id) {
                    let gate = ThresholdTestGate(plan: plan, profile: store.profile,
                                                 strapConnected: devices.strapState == .connected || devices.simulatorActive)
                    Button {
                        requestTest(id, gate: gate)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(plan.shortName).foregroundStyle(Theme.text)
                                if id == preferredTest { DSChip(String(localized: "empfohlen"), tone: .ok) }
                            }
                            Text(plan.summary).font(.footnote).foregroundStyle(Theme.text2).lineLimit(3)
                            if let reason = gate.blockReason {
                                Text(reason).font(.footnote).foregroundStyle(Theme.warn)
                            }
                        }
                    }
                    .disabled(gate.blockReason != nil && !gate.needsHealthScreen)
                }
            }
            Picker("Bevorzugter Test", selection: Binding(get: { store.profile.preferredTest ?? "" },
                                                         set: { store.setPreferredTest($0.isEmpty ? nil : $0) })) {
                Text("Nach Profil").tag("")
                ForEach(ThresholdTestGate.testIds, id: \.self) { id in
                    Text(PlanLibrary.plan(id: id)?.shortName ?? id).tag(id)
                }
            }
            Button("Gesundheitsfragen") { showHealth = true }.foregroundStyle(Theme.link)
        } header: {
            Text("Test starten")
        } footer: {
            Text("Concept2 empfiehlt harte Belastungen erst nach ärztlicher Freigabe, wenn gesundheitliche Fragen offen sind. Bei Brustschmerz, Schwindel, ungewöhnlicher Atemnot oder Herzstolpern sofort aufhören. Der Stufentest bleibt submaximal.")
        }
    }

    /// Test starten: vorher Gesundheitsfragen, wenn nötig; gesperrt (z. B. ohne Pulsgurt) → nichts
    private func requestTest(_ id: String) {
        guard let plan = PlanLibrary.plan(id: id) else { return }
        requestTest(id, gate: ThresholdTestGate(plan: plan, profile: store.profile,
                                                strapConnected: devices.strapState == .connected || devices.simulatorActive))
    }

    private func requestTest(_ id: String, gate: ThresholdTestGate) {
        if gate.needsHealthScreen {
            pendingTest = id
            showHealth = true
        } else if let reason = gate.blockReason {
            blockedReason = reason
        } else {
            start(id)
        }
    }

    private func start(_ id: String) {
        closeSettings?()
        // erst nach dem Schliessen der Einstellungen starten (zwei Ansichten können nicht gleichzeitig erscheinen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            launch?.callAsFunction(.plan(planId: id, courseId: nil))
        }
    }

    private func loadInputs() {
        if let a = store.active {
            wattsInput = (a.powerW).rounded()
            let p = Int(ThresholdMath.pace(watts: a.powerW).rounded())
            paceMinutes = min(max(p / 60, 1), 3)
            paceSeconds = p % 60
        }
        best2kInput = store.profile.mirrorBest2k ?? PaceTargets.defaultBest2k
        let h = store.heart
        maxHRInput = h.maxHR
        restHRInput = h.restHR
        lthrInput = h.lthr
        birthYearInput = h.birthYear
    }
}

/// Offene Rückfrage zu einem Testergebnis (niedriger als die aktive Schwelle)
struct PendingResultRow: View {
    let estimate: ThresholdEstimate
    @State private var store = ThresholdStore.shared

    var body: some View {
        let wattsText = ThresholdFormat.watts(estimate.powerW)
        let sourceText = ThresholdFormat.source(estimate)
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("\(sourceText): \(wattsText). Übernehmen oder alte Schwelle behalten?").font(.subheadline)
            HStack {
                Button("Übernehmen") { store.accept(id: estimate.id) }.foregroundStyle(Theme.link)
                Spacer()
                Button("Behalten") { store.keep(id: estimate.id) }.foregroundStyle(Theme.text2)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Zonentabelle

struct ThresholdZoneTable: View {
    let threshold: Double
    let heartZones: HeartRateZones?
    var compact = false

    var body: some View {
        let bands = TrainingZones.bands(threshold: threshold)
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Zone").dsLabelStyle()
                Text("Watt").dsLabelStyle()
                Text("/500 m").dsLabelStyle()
                if heartZones != nil { Text("Puls").dsLabelStyle() }
            }
            ForEach(bands) { b in
                GridRow {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.zoneColor(b.zone)).frame(width: 6, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "\(b.zone) · \(b.band)").font(.subheadline.weight(.semibold))
                            if !compact { Text(b.title).font(.caption).foregroundStyle(Theme.text2) }
                        }
                    }
                    Text(wattRange(b)).font(.subheadline.monospacedDigit())
                    Text(paceRange(b)).font(.subheadline.monospacedDigit())
                    if let hz = heartZones { Text(heartRange(hz, zone: b.zone)).font(.subheadline.monospacedDigit()) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func wattRange(_ b: TrainingZones.Band) -> String {
        switch (b.lowerW, b.upperW) {
        case (nil, let hi?): return "< \(Int(hi.rounded()))"
        case (let lo?, nil): return "> \(Int(lo.rounded()))"
        case (let lo?, let hi?): return "\(Int(lo.rounded()))–\(Int(hi.rounded()))"
        default: return "–"
        }
    }

    private func paceRange(_ b: TrainingZones.Band) -> String {
        switch (b.slowPace, b.fastPace) {
        case (nil, let fast?): return "< \(Format.pace(fast))"
        case (let slow?, nil): return "> \(Format.pace(slow))"
        case (let slow?, let fast?): return "\(Format.pace(slow))–\(Format.pace(fast))"
        default: return "–"
        }
    }

    private func heartRange(_ z: HeartRateZones, zone: Int) -> String {
        let lo = z.lowerBound(zone: zone)
        if zone == HeartRateZones.count { return "≥ \(lo)" }
        return "\(lo)–\(z.lowerBound(zone: zone + 1) - 1)"
    }
}

// MARK: - Details einer Schätzung

struct ThresholdEstimateDetail: View {
    let id: UUID
    @State private var store = ThresholdStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let e = store.profile.estimate(id: id) {
                Section {
                    LabeledContent(String(localized: "Schwelle"), value: ThresholdFormat.threshold(e.powerW))
                    LabeledContent(String(localized: "Quelle"), value: ThresholdFormat.source(e))
                    LabeledContent(String(localized: "Datum"), value: ThresholdFormat.date(e.date))
                    LabeledContent(String(localized: "Unsicherheit"),
                                   value: ThresholdFormat.uncertainty(e.powerW, sigma: store.sigma(e)))
                    if e.firstOfKind {
                        Text("Erster Test dieser Art: etwas unsicherer (Gewöhnung).").font(.footnote)
                            .foregroundStyle(Theme.text2)
                    }
                }
                if !e.evaluationNotes.isEmpty {
                    Section {
                        ForEach(e.evaluationNotes, id: \.self) { n in
                            Label(n.title, systemImage: "exclamationmark.triangle").font(.subheadline)
                        }
                    } header: {
                        Text("Hinweise")
                    }
                }
                if !e.details.isEmpty {
                    Section {
                        ForEach(e.details.keys.sorted(), id: \.self) { k in
                            LabeledContent(k, value: String(format: "%.2f", e.details[k] ?? 0))
                                .font(.footnote.monospacedDigit())
                        }
                    } header: {
                        Text("Rohwerte")
                    }
                }
                Section {
                    if e.statusValue != .active {
                        Button("Als aktiv verwenden") { store.activate(id: e.id) }.foregroundStyle(Theme.link)
                    }
                    if e.statusValue != .rejected {
                        Button("Verwerfen", role: .destructive) {
                            store.reject(id: e.id)
                            dismiss()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text("Schätzung"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Testauswahl, Gesundheitsfragen

/// Darf ein Test starten? (Gesundheitsfragen vor maximalen Tests, Pulsgurt beim Stufentest)
struct ThresholdTestGate {
    static let testIds = [ThresholdRetest.submaxTest, ThresholdRetest.ftpTest, "test-2000m", ThresholdRetest.rampTest,
                          ThresholdRetest.cpTest]

    let plan: WorkoutPlan
    let profile: ThresholdProfile
    let strapConnected: Bool

    var isMaximal: Bool { ThresholdRetest.isMaximalTest(plan) }

    /// Vor dem ersten maximalen Test die Gesundheitsfragen
    var needsHealthScreen: Bool { isMaximal && profile.healthScreen == nil }

    /// Warum der Test nicht starten soll (nil = darf)
    var blockReason: String? {
        if isMaximal, profile.healthScreen?.blocksMaximalTests == true {
            return String(localized: "Bitte zuerst ärztlich abklären. Der Stufentest bleibt verfügbar.")
        }
        if needsHealthScreen { return String(localized: "Vor dem ersten maximalen Test: kurze Gesundheitsfragen.") }
        if plan.test?.requiresHeartRate == true, !strapConnected {
            return String(localized: "Pulsgurt verbinden – der Stufentest braucht den Puls.")
        }
        if plan.id == ThresholdRetest.cpTest, !profile.estimates.contains(where: { $0.source?.isTest == true }) {
            return String(localized: "Gewöhnung nötig: erst einen anderen Test machen. Das erste Mal ist meist zu vorsichtig.")
        }
        return nil
    }
}

/// Gesundheitsfragen (angelehnt an PAR-Q+); Antworten bleiben lokal
struct HealthScreenSheet: View {
    let screen: HealthScreen?
    let onDone: (HealthScreen?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [String: Bool] = [:]
    @State private var cleared = false

    private func question(_ id: String) -> String {
        switch id {
        case "heart": return String(localized: "Bekannte Herzerkrankung oder Bluthochdruck in Behandlung?")
        case "chestPain": return String(localized: "Brustschmerz in Ruhe oder bei Belastung?")
        case "dizziness": return String(localized: "Schwindel oder Bewusstlosigkeit in den letzten 12 Monaten?")
        case "chronic": return String(localized: "Andere chronische Erkrankung, die Belastung einschränkt?")
        case "medication": return String(localized: "Medikamente für Herz oder Kreislauf?")
        case "supervision": return String(localized: "Ärztlich geraten, nur unter Aufsicht zu trainieren?")
        default: return String(localized: "Schwangerschaft?")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(HealthScreen.questionIds, id: \.self) { id in
                        Toggle(isOn: Binding(get: { answers[id] ?? false }, set: { answers[id] = $0 })) {
                            Text(question(id))
                        }
                    }
                } footer: {
                    Text("Bei einem Ja schlägt die App keine maximalen Tests vor. Die Antworten bleiben auf diesem Gerät.")
                }
                if answers.values.contains(true) {
                    Section {
                        Toggle("Ärztliche Freigabe liegt vor", isOn: $cleared)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .dsSheetChrome(String(localized: "Gesundheitsfragen")) { dismiss() }
            .safeAreaInset(edge: .bottom) {
                DSFooterBar {
                    Button("Speichern") {
                        let s = HealthScreen(answeredAt: Date(), answers: answers,
                                             clearanceDate: cleared ? Date() : nil)
                        onDone(s)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                }
            }
            .onAppear {
                answers = screen?.answers ?? [:]
                cleared = screen?.clearanceDate != nil
            }
        }
    }
}

/// Hinweis vor einem Test (Programmansicht): Sicherheit, Puls, Ziele aus der Schwelle
struct ThresholdTestNotice: View {
    let plan: WorkoutPlan

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if ThresholdRetest.isMaximalTest(plan) {
                Label("Bei Brustschmerz, Schwindel, ungewöhnlicher Atemnot oder Herzstolpern sofort aufhören.",
                      systemImage: "heart.text.square")
                    .font(.footnote)
                    .foregroundStyle(Theme.warn)
            }
            if plan.test?.requiresHeartRate == true {
                Label("Pulsgurt nötig (Polar H9/H10 liefert zusätzlich die Herzfrequenzvariabilität).",
                      systemImage: "heart")
                    .font(.footnote)
                    .foregroundStyle(Theme.text2)
            }
        }
    }
}

// MARK: - Im Test

/// Bedienelemente während eines Schwellentests: Talk-Test (drei grosse Knöpfe) und „Ich kann nicht mehr“ bzw.
/// „Zu anstrengend“
struct ThresholdTestControls: View {
    @Environment(SessionController.self) private var controller

    var body: some View {
        VStack(spacing: DS.Space.s) {
            if controller.talkTestDue {
                Text("Kannst du noch in ganzen Sätzen sprechen?").font(.headline).foregroundStyle(Theme.text)
                HStack(spacing: DS.Space.s) {
                    talkButton(String(localized: "leicht"), .easy)
                    talkButton(String(localized: "geht so"), .soSo)
                    talkButton(String(localized: "nein"), .no)
                }
            }
            if controller.canEndTestPart {
                Button {
                    controller.endTestPart()
                } label: {
                    Text(controller.planStatus?.phase?.testRole == "step" ? String(localized: "Zu anstrengend")
                         : String(localized: "Ich kann nicht mehr"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
        }
        .padding(controller.talkTestDue || controller.canEndTestPart ? 12 : 0)
        .hudPanel(cornerRadius: 16)
        .opacity(controller.talkTestDue || controller.canEndTestPart ? 1 : 0)
        .allowsHitTesting(controller.talkTestDue || controller.canEndTestPart)
    }

    private func talkButton(_ title: String, _ a: TalkAnswer) -> some View {
        Button { controller.answerTalkTest(a) } label: {
            Text(title).font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(SecondaryButtonStyle(compact: true))
    }
}

// MARK: - Retest-Karten (R3, R4, R5)

/// „Wieder dabei“ (Stufentest zum Wiedereinstieg, R3), „Ziele zu hoch?“ (Test oder Schwelle −3 %, R4) und „Ziele zu
/// leicht?“ (Test, R5). Startbildschirm und „Schwelle & Zonen“; Logik in `ThresholdRetestCard` (Kit).
struct ThresholdRetestCardView: View {
    let card: ThresholdRetestCard
    /// Test starten (Plan-id)
    let onTest: (String) -> Void
    var onDismiss: (() -> Void)?

    private var testName: String { PlanLibrary.plan(id: card.testId)?.shortName ?? card.testId }

    private var title: String {
        switch card.kind {
        case .reentry: return String(localized: "Wieder dabei")
        case .tooHard: return String(localized: "Ziele zu hoch?")
        case .tooEasy: return String(localized: "Ziele zu leicht?")
        }
    }

    private var text: String {
        switch card.kind {
        case .reentry:
            return String(localized: "Nach der Pause prüft ein Stufentest mit Pulsgurt, ob deine Schwelle noch stimmt – submaximal, ohne Ausbelastung.")
        case .tooHard:
            return card.offerTest
                ? String(localized: "In den letzten harten Einheiten warst du oft deutlich langsamer als das Ziel oder am Anschlag. Ein Test klärt die Schwelle – oder du senkst sie um 3 %.")
                : String(localized: "In den letzten harten Einheiten warst du oft deutlich langsamer als das Ziel oder am Anschlag. Du kannst die Schwelle um 3 % senken.")
        case .tooEasy:
            return String(localized: "In den letzten Schwellen-Einheiten warst du klar über dem Ziel, bei niedrigem Puls. Ein Test zeigt, ob deine Schwelle gestiegen ist.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: card.kind == .tooHard ? "gauge.with.dots.needle.67percent"
                      : (card.kind == .tooEasy ? "arrow.up.right.circle" : "figure.rower"))
                    .font(.headline)
                Spacer()
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.text2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Hinweis schliessen"))
                }
            }
            Text(text).font(.subheadline).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.m) {
                if card.offerTest {
                    Button(String(localized: "Test: \(testName)")) { onTest(card.testId) }
                        .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                }
                if card.kind == .tooHard, ThresholdStore.shared.profile.thresholdW != nil {
                    Button("Schwelle −3 %") {
                        // neue aktive Schwelle: ältere Einheiten zählen nicht mehr, die Karte ist erledigt
                        ThresholdStore.shared.lowerByThreePercent()
                        ThresholdStore.shared.retestCard = nil
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                }
            }
        }
        .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
    }
}

/// Dezente Sicherheitsmeldungen in der Fahrt (docs/schwelle/SPEC.md 9): „Pulsgurt prüfen“ (Puls unplausibel hoch
/// oder sprunghaft) und im Stufentest „Puls fehlt“ (mehr als 15 s ohne Messwert). Kein Abbruch; die Auswertung
/// vermerkt den Ausfall.
struct HeartRateSafetyBanner: View {
    @Environment(SessionController.self) private var controller

    var body: some View {
        VStack(spacing: DS.Space.s) {
            if controller.heartRateMissing {
                line(systemImage: "heart.slash",
                     text: String(localized: "Puls fehlt – Gurt anfeuchten und Sitz prüfen. Die Stufe zählt, sobald der Puls wieder da ist."))
            } else if controller.heartStrapCheck {
                line(systemImage: "waveform.path.ecg",
                     text: String(localized: "Pulsgurt prüfen – der Puls wirkt unplausibel."))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.heartRateMissing)
        .animation(.easeInOut(duration: 0.25), value: controller.heartStrapCheck)
        .allowsHitTesting(false)
    }

    private func line(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .hudPanel(cornerRadius: 14)
            .transition(.opacity)
    }
}

// MARK: - Ergebnis nach der Fahrt

/// Testergebnis in der Zusammenfassung: Schwelle (Watt, Tempo, gleichwertige 2k), Vergleich, Unsicherheit,
/// Prüfhinweise, neue Zonen; „Übernehmen“/„Behalten“ bzw. „Rückgängig“ nach automatischer Übernahme.
/// Direkt nach der Fahrt wird das Ergebnis eingetragen (höher → aktiv, tiefer → Rückfrage); im Verlauf nur angezeigt.
struct ThresholdResultCard: View {
    let record: WorkoutRecord
    let live: Bool
    var talk: [Int: TalkAnswer] = [:]
    @State private var store = ThresholdStore.shared
    @State private var evaluation: ThresholdEvaluation?
    @State private var decision: ThresholdDecision?
    @State private var previousW: Double?
    @State private var evaluated = false

    private var plan: WorkoutPlan? { record.header.workoutPlanId.flatMap { PlanLibrary.plan(id: $0) } }

    var body: some View {
        Group {
            if let ev = evaluation, ev.estimate != nil || !ev.notes.isEmpty, !ev.bestMarkOnly {
                content(ev)
                    .dsCard()
            }
        }
        .task(id: record.id) { await evaluate() }
    }

    private func evaluate() async {
        // Simulatorfahrten nur direkt nach der Fahrt auswerten – in Testversionen auch später (zum Prüfen)
        #if DEBUG
        let allowSimulated = true
        #else
        let allowSimulated = live
        #endif
        guard !evaluated, let plan, ThresholdEvaluator.evaluator(for: plan) != nil,
              record.header.device.source != .simulator || allowSimulated else { return }
        evaluated = true
        let profile = store.profile
        let ride = ThresholdRideData(record: record, plan: plan, talk: talk)
        let ev = await Task.detached(priority: .userInitiated) {
            ThresholdEvaluator.evaluate(ride, profile: profile)
        }.value
        previousW = store.active?.powerW
        evaluation = ev
        guard let ev, ev.estimate != nil else { return }
        if live {
            decision = store.submit(ev)
        } else if let e = ev.estimate {
            // im Verlauf: Stand aus dem Profil (schon eingetragen?) oder nur anzeigen
            if let known = store.profile.estimates.first(where: { $0.workoutId == record.id && $0.kind == e.kind }) {
                decision = known.statusValue == .active ? .adopt(changePct: 0)
                    : (known.statusValue == .candidate && !known.isHintOnly ? ThresholdSelector.decide(known, profile: store.profile) : .hintOnly)
            } else {
                decision = ThresholdSelector.decide(e, profile: store.profile)
            }
        }
    }

    /// Schätzung dieser Fahrt im Profil (nach dem Eintragen)
    private func stored(_ e: ThresholdEstimate) -> ThresholdEstimate? {
        store.profile.estimates.first { $0.workoutId == record.id && $0.kind == e.kind }
    }

    @ViewBuilder
    private func content(_ ev: ThresholdEvaluation) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("SCHWELLENTEST").font(.footnote.weight(.bold)).tracking(2).foregroundStyle(Theme.text2)
            if let e = ev.estimate {
                Text(ThresholdFormat.threshold(e.powerW)).font(.title.bold().monospacedDigit())
                let t2kText = Format.duration(ThresholdMath.equivalentBest2k(threshold: e.powerW, b: store.profile.exponentB))
                Text("entspricht 2000 m ≈ \(t2kText)").font(.subheadline).foregroundStyle(Theme.text2)
                Text(ThresholdFormat.uncertainty(e.powerW, sigma: e.sigmaPct)).font(.subheadline.monospacedDigit())
                if let prev = previousW, prev > 0 {
                    let changeText = ThresholdFormat.change((e.powerW - prev) / prev * 100)
                    let prevText = ThresholdFormat.watts(prev)
                    Text("Bisher \(prevText) (\(changeText))").font(.subheadline).foregroundStyle(Theme.text2)
                }
                if let c = ev.comparison {
                    let cText = ThresholdFormat.watts(c.powerW)
                    let cSource = c.source?.title ?? c.kind
                    Text("Zum Vergleich: \(cSource) \(cText)").font(.footnote).foregroundStyle(Theme.text2)
                }
            }
            ForEach(ev.notes, id: \.self) { n in
                Label(n.title, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.warn)
            }
            actions(ev)
            if let lthr = ev.lthrSuggestion, store.heart.lthr != lthr {
                let lthrText = "\(lthr)"
                Button("Schwellenpuls \(lthrText) /min übernehmen") {
                    store.acceptLTHR(lthr, source: ev.lthrSource ?? "test30", date: record.header.startDate)
                }
                .foregroundStyle(Theme.link)
            }
            if let mx = ev.maxHRSuggestion, (store.heart.maxHR ?? 0) < mx {
                let maxText = "\(mx)"
                Button("Neuer Maximalpuls \(maxText)? Übernehmen") { store.acceptMaxHR(mx) }
                    .foregroundStyle(Theme.link)
            }
            if let line = ev.heartRateLine, let e = ev.estimate {
                let wattsText = ThresholdFormat.watts(e.powerW * 0.9)
                let hrText = "\(Int(line.y(at: e.powerW * 0.9).rounded()))"
                Text("Puls-Leistungs-Gerade: bei \(wattsText) etwa \(hrText) /min").font(.footnote).foregroundStyle(Theme.text2)
            }
            if ev.comparison?.source == .stepDFA {
                Text("Herzfrequenzvariabilität (DFA-alpha1): zweite Meinung, experimentell, am Rudern nicht geprüft.")
                    .font(.footnote).foregroundStyle(Theme.text2)
            }
            if let e = ev.estimate {
                ThresholdZoneTable(threshold: e.powerW, heartZones: nil, compact: true)
            }
        }
    }

    @ViewBuilder
    private func actions(_ ev: ThresholdEvaluation) -> some View {
        if let e = ev.estimate {
            let current = stored(e)
            switch decision {
            case .adopt(let pct)?:
                if current?.statusValue == .active || current == nil {
                    let changeText = ThresholdFormat.change(pct)
                    Label("Neue Schwelle übernommen (\(changeText))", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ok)
                    if store.undoTarget?.estimate == current?.id {
                        Button("Rückgängig") { store.undo() }.foregroundStyle(Theme.link)
                    }
                } else {
                    Text("Nicht übernommen.").font(.subheadline).foregroundStyle(Theme.text2)
                }
            case .ask?:
                if current?.statusValue == .active {
                    Label("Übernommen", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                } else if current?.statusValue == .rejected {
                    Text("Alte Schwelle behalten.").font(.subheadline).foregroundStyle(Theme.text2)
                } else {
                    Text("Übernehmen oder alte Schwelle behalten? Die Tagesform streut.").font(.subheadline)
                    HStack(spacing: DS.Space.m) {
                        Button("Übernehmen") { adopt(e) }.buttonStyle(PrimaryButtonStyle(compact: true))
                        Button("Behalten") { if let c = current { store.keep(id: c.id) } }
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                }
            case .hintOnly?:
                Text("Nur als Hinweis – die Schwelle bleibt, wie sie ist.").font(.subheadline).foregroundStyle(Theme.text2)
            case nil:
                EmptyView()
            }
        }
    }

    /// Übernehmen (im Verlauf auch, wenn das Ergebnis noch nicht eingetragen war)
    private func adopt(_ e: ThresholdEstimate) {
        if let c = stored(e) {
            store.accept(id: c.id)
        } else if let ev = evaluation {
            store.submit(ev)
            if let c = stored(e) { store.accept(id: c.id) }
        }
    }
}

// MARK: - Einstellungen schliessen (für „Test starten“)

private struct CloseSettingsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Schliesst das Einstellungs-Sheet (gesetzt in `SettingsView`)
    var closeSettings: (() -> Void)? {
        get { self[CloseSettingsKey.self] }
        set { self[CloseSettingsKey.self] = newValue }
    }
}
