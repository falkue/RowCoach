import SwiftUI
import RowCoachKit

// „Neue Schwelle erkannt“ aus Fahrten (docs/schwelle/SPEC.md 5, R2) als kurzes Fenster beim App-Start bzw. wenn die
// App aus dem Hintergrund kommt. Gezeigt von `RootView` (dort die Regeln: nicht während einer Fahrt, nicht über
// Ersteinrichtung, Gesundheitsfragen oder anderen Sheets, nicht im Testbetrieb). „Übernehmen“ = acceptRideCandidate,
// „Nicht jetzt“ = zurückstellen (wieder ab + 2 % oder nach 7 Tagen, `ThresholdDetector.shouldPrompt`). Die ruhige
// Karte auf „Heute“ (HomeView) bleibt, solange der Vorschlag offen ist.

/// Offener Vorschlag mit allem, was Fenster und Karte zeigen
struct ThresholdOffer: Equatable, Identifiable {
    let candidate: ThresholdDetector.Candidate
    /// aktive Schwelle vor der Übernahme (nil = noch keine)
    let previousW: Double?
    /// Strecke der Fahrt, aus der der Kandidat stammt (Rohtitel aus dem Training)
    let courseTitle: String?
    /// Beispiel aus `-demoThresholdCandidate 1`
    var isDemo = false

    /// gleicher Kandidat = gleiche Fahrt, gleiche Art, gleicher Wert (auf 1 W)
    var id: String {
        "\(candidate.estimate.workoutId?.uuidString ?? "-")|\(candidate.estimate.kind)|\(Int(candidate.estimate.powerW.rounded()))"
    }

    var wattsText: String { ThresholdFormat.watts(candidate.estimate.powerW) }

    /// „vorher 165 W“ (nil ohne bisherige Schwelle)
    var previousText: String? {
        previousW.map { String(localized: "vorher \(ThresholdFormat.watts($0))") }
    }

    /// Kurzname der Strecke: Teil vor „ – “ des übersetzten Titels („Alte Donau Wien“)
    var courseShort: String? {
        guard let t = courseTitle, !t.isEmpty else { return nil }
        let localized = CourseText.localized(t)
        return localized.components(separatedBy: " – ").first?.trimmingCharacters(in: .whitespaces) ?? localized
    }

    /// „Aus deiner Fahrt vom 20.11.: 24 min mit 175 W auf Alte Donau Wien.“
    var sourceText: String? {
        guard let e = candidate.effort else { return nil }
        let dateText = e.date.formatted(.dateTime.day().month(.twoDigits))
        let lengthText = PlanFormat.duration(e.duration)
        let effortText = ThresholdFormat.watts(e.power)
        if let course = courseShort {
            return String(localized: "Aus deiner Fahrt vom \(dateText): \(lengthText) mit \(effortText) auf \(course).")
        }
        return String(localized: "Aus deiner Fahrt vom \(dateText): \(lengthText) mit \(effortText).")
    }

    /// Text der ruhigen Karte auf „Heute“: „Neue Schwelle erkannt: 171 W (aus deiner Fahrt vom 20.11.: 24 min mit
    /// 175 W). Übernehmen?“
    var bannerText: String {
        guard let e = candidate.effort else { return String(localized: "Neue Schwelle erkannt: \(wattsText). Übernehmen?") }
        let dateText = e.date.formatted(.dateTime.day().month(.twoDigits))
        let lengthText = PlanFormat.duration(e.duration)
        let effortText = ThresholdFormat.watts(e.power)
        return String(localized: "Neue Schwelle erkannt: \(wattsText) (aus deiner Fahrt vom \(dateText): \(lengthText) mit \(effortText)). Übernehmen?")
    }
}

/// Regeln für das Fenster, die an Startargumenten hängen
enum ThresholdPromptPolicy {
    /// `-demoThresholdCandidate 1`: Beispiel-Kandidat, sonst gelten alle Regeln (einmal zeigen, „Nicht jetzt“ stellt
    /// zurück). `-demoThresholdCandidate 2`: zusätzlich beim Start die Zurückstellung vergessen, damit das Fenster bei
    /// jedem Start kommt. Nur Debug/Dev; im Basis-Release verwirft `AppEdition.applyLaunchArgumentPolicy` das
    /// Argument ohnehin.
    static let demoKey = "demoThresholdCandidate"
    /// feste Fahrt-id des Beispiels (damit es über Neuberechnungen derselbe Kandidat bleibt)
    private static let demoWorkoutId = UUID(uuidString: "5C4E11D0-0000-4000-8000-000000000171")!

    static var demoRequested: Bool {
        AppEdition.testArgumentsEnabled && UserDefaults.standard.integer(forKey: demoKey) >= 1
    }

    static var demoResetsDeferral: Bool {
        AppEdition.testArgumentsEnabled && UserDefaults.standard.integer(forKey: demoKey) == 2
    }

    /// Bildschirmfotos und Testläufe über Startargumente: kein Fenster (ausser mit `-demoThresholdCandidate 1`)
    static var isTestRun: Bool {
        let d = UserDefaults.standard
        return d.bool(forKey: "photoMode") || d.string(forKey: "demoCourse") != nil || d.bool(forKey: "seedDemoHistory")
            || d.integer(forKey: "demoRace") > 0 || d.integer(forKey: "demoTournament") > 0
    }

    static var promptAllowed: Bool { demoRequested || !isTestRun }

    /// Beispiel: 4 % über der aktiven Schwelle, aus einer Fahrt vor 3 Tagen (24 min) auf der Alten Donau. Nach dem
    /// Übernehmen (aktive Schätzung trägt `demo`) bzw. Ablehnen desselben Werts kommt kein Beispiel mehr, bis eine
    /// andere Schwelle eingetragen ist.
    static func demoOffer(profile: ThresholdProfile, now: Date) -> ThresholdOffer? {
        guard demoRequested, profile.active?.details["demo"] != 1 else { return nil }
        let t = profile.thresholdW ?? 165
        let newW = (t * 1.04).rounded()
        if profile.estimates.contains(where: { $0.workoutId == demoWorkoutId && $0.statusValue == .rejected
            && abs($0.powerW - newW) < 0.5 }) { return nil }
        let duration = 1440.0
        let b = profile.exponentB
        let power = newW / pow(duration / 1800, b)
        let date = now.addingTimeInterval(-3 * 86400)
        var est = ThresholdEstimate(kind: .ridesAuto, date: date, powerW: newW, sigmaPct: 6, workoutId: demoWorkoutId,
                                    details: ["p": power, "t": duration, "b": b, "demo": 1])
        est.status = ThresholdEstimate.Status.candidate.rawValue
        let effort = ThresholdDetector.Effort(workoutId: demoWorkoutId, date: date, duration: duration, power: power,
                                              start: 300, fromHeartRate: false)
        return ThresholdOffer(candidate: ThresholdDetector.Candidate(estimate: est, effort: effort),
                              previousW: profile.thresholdW,
                              courseTitle: "Alte Donau Wien – von der Unteren zur Oberen Alten Donau", isDemo: true)
    }
}

/// Kurzes Fenster „Neue Schwelle erkannt“: Wert gross, vorher, Herkunft; „Übernehmen“ (Gelb), „Nicht jetzt“, Link
/// „Details“ (Schwelle & Zonen, im selben Fenster). Wischen nach unten zählt wie „Nicht jetzt“ (RootView).
struct ThresholdCandidateSheet: View {
    let offer: ThresholdOffer
    let onAccept: () -> Void
    let onLater: () -> Void

    @State private var showDetails = false
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(isPresented: $showDetails) { ThresholdSettingsView() }
                .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
        .onChange(of: showDetails) { _, open in
            withAnimation { detent = open ? .large : .medium }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    BahnMarker()
                    Text("NEUE SCHWELLE ERKANNT")
                        .font(.footnote.weight(.bold)).tracking(2)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                    Text(offer.wattsText)
                        .font(DSFont.display(44, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.text)
                    if let prev = offer.previousText {
                        Text(prev).font(.title3).foregroundStyle(Theme.text2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityValue)

                if let source = offer.sourceText {
                    Text(source).font(.body).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Zonen und Tempoziele richten sich danach. Übernehmen?")
                    .font(.subheadline).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: DS.Space.s) {
                    Button(action: onAccept) { Text("Übernehmen") }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .accessibilityHint(Text("Setzt die neue Schwelle für Zonen und Tempoziele."))
                    Button(action: onLater) { Text("Nicht jetzt") }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                        .accessibilityHint(Text("Fragt später wieder. Der Hinweis bleibt auf „Heute“."))
                }
                .padding(.top, DS.Space.s)

                Button { showDetails = true } label: {
                    Text("Details").font(.body.weight(.semibold)).foregroundStyle(Theme.link)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityHint(Text("Öffnet Schwelle & Zonen."))
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.top, DS.Space.l)
            .padding(.bottom, DS.Space.m)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.card)
    }

    /// „Neue Schwelle 171 Watt, vorher 165 Watt“ für VoiceOver
    private var accessibilityValue: Text {
        let w = offer.candidate.estimate.powerW
        if let p = offer.previousW {
            return Text("Neue Schwelle \(Int(w.rounded())) Watt, vorher \(Int(p.rounded())) Watt")
        }
        return Text("Neue Schwelle \(Int(w.rounded())) Watt")
    }
}
