import RowCoachKit
import SwiftUI

/// Ergebnis eines Turnier-Rennens und Ranglisten (Bestzeiten auf der Distanz, Saisonwertung) mit Filter „Alle“ /
/// „Nur echte“. Virtuelle Teilnehmende tragen das Zeichen ✦ (VoiceOver: „virtuell“). Daten: lokale Rangliste
/// (`VirtualTournamentStore.book`), später vom Server. docs/MULTIPLAYER.md „Virtuelle Teilnehmende“.
struct RaceResultsView: View {
    let raceId: String?

    private enum Tab: Hashable { case race, best, season }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .race
    @State private var filter: RankingFilter = .all
    @State private var showInfo = false

    private var book: RaceRankingBook { VirtualTournamentStore.shared.book }
    private var raceEntries: [RaceRecordEntry] { raceId.map { book.results(raceId: $0, filter: filter) } ?? [] }
    /// Distanz und Strecke dieses Rennens (für die Bestzeiten)
    private var reference: (distance: Double, courseId: String)? {
        guard let id = raceId, let e = book.entries.first(where: { $0.raceId == id }),
              case .distance(let m) = e.target else { return nil }
        return (m, e.courseId)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Ansicht", selection: $tab) {
                        Text("Rennen").tag(Tab.race)
                        Text("Bestzeiten").tag(Tab.best)
                        Text("Saison").tag(Tab.season)
                    }
                    .pickerStyle(.segmented)
                    Picker("Teilnehmende", selection: $filter) {
                        Text("Alle").tag(RankingFilter.all)
                        Text("Nur echte").tag(RankingFilter.realOnly)
                    }
                    .pickerStyle(.segmented)
                }
                switch tab {
                case .race: raceSection
                case .best: bestSection
                case .season: seasonSection
                }
                Section {
                    Text("✦ = virtuelle Teilnehmende: erfundene Ruderer, die Turniere auffüllen. Ihre Ergebnisse entstehen aus einem Leistungsmodell.")
                        .font(.footnote)
                        .foregroundStyle(Theme.text2)
                }
            }
            .navigationTitle("Ergebnis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel(Text("Was sind virtuelle Teilnehmende?"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showInfo) { VirtualParticipantsInfoView() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var raceSection: some View {
        let list = raceEntries
        Section {
            if list.isEmpty {
                Text("Noch kein Ergebnis.").foregroundStyle(Theme.text2)
            }
            ForEach(list) { e in
                row(rank: e.place, name: e.displayName, country: e.country, isVirtual: e.isVirtual,
                    isMe: e.participantId == "me",
                    value: e.time.map { Format.duration($0, tenths: true) } ?? "\(Int(e.distance.rounded())) m")
            }
        } header: {
            if filter == .all {
                Text("\(list.count) Teilnehmende")
            } else {
                Text("\(list.count) echte Teilnehmende")
            }
        }
    }

    @ViewBuilder
    private var bestSection: some View {
        if let ref = reference {
            let rows = book.leaderboard(distance: ref.distance, courseId: ref.courseId, filter: filter)
            Section {
                ForEach(rows.prefix(200)) { r in
                    row(rank: r.rank, name: r.displayName, country: r.country, isVirtual: r.isVirtual,
                        isMe: r.participantId == "me", value: Format.duration(r.value, tenths: true))
                }
            } header: {
                Text("Bestzeiten über \(DSFormat.km(ref.distance)) auf dieser Strecke")
            }
        }
    }

    @ViewBuilder
    private var seasonSection: some View {
        let season = RowingSeason.id(at: Date().timeIntervalSince1970)
        let rows = book.seasonStandings(season: season, filter: filter)
        Section {
            ForEach(rows.prefix(200)) { r in
                row(rank: r.rank, name: r.displayName, country: r.country, isVirtual: r.isVirtual,
                    isMe: r.participantId == "me", value: "\(Int(r.value.rounded())) P.")
            }
        } header: {
            Text("Saison \(season): beste \(RaceRankingBook.seasonBestOf) Rennen je Person")
        }
    }

    private func row(rank: Int, name: String, country: String?, isVirtual: Bool, isMe: Bool, value: String) -> some View {
        HStack(spacing: 10) {
            Text("\(rank).")
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
                .foregroundStyle(Theme.text2)
            Text(name.isEmpty ? String(localized: "Ich") : name)
                .fontWeight(isMe ? .bold : .regular)
                .lineLimit(1)
            if let country {
                Text(country).font(.caption.weight(.semibold)).foregroundStyle(Theme.text2)
            }
            if isVirtual {
                Text(RaceParticipant.virtualMark).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .listRowBackground(isMe ? Theme.accent.opacity(0.18) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(rank: rank, name: name, country: country, isVirtual: isVirtual,
                                                   value: value)))
    }

    private func accessibilityText(rank: Int, name: String, country: String?, isVirtual: Bool, value: String) -> String {
        var parts = [String(localized: "Platz \(rank)"), name.isEmpty ? String(localized: "Ich") : name]
        if let country { parts.append(CountryList.name(country, languageCode: AppLanguage.code)) }
        if isVirtual { parts.append(String(localized: "virtuell")) }
        parts.append(value)
        return parts.joined(separator: ", ")
    }
}

/// Einmalige Erklärung beim ersten Turnier (und über „i“ in der Ergebnisansicht)
struct VirtualParticipantsInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Virtuelle Teilnehmende")
                        .font(.title2.weight(.bold))
                    Text("Damit jedes Turnier ein volles Feld hat, füllt RowCoach es mit virtuellen Teilnehmenden auf. Sie sind immer mit ✦ gekennzeichnet – am Boot, in der Rennanzeige, in Ergebnissen und Ranglisten.")
                    Text("Sie sind erfunden: Vorname, Land und Aussehen stammen aus offenen Namenslisten und Zufall; keine echte Person wird nachgebildet. Ihre Zeiten entstehen aus einem Leistungsmodell mit Tagesform, auf allen Geräten gleich.")
                    Text("Melden sich genug echte Ruderer an, fahren keine virtuellen mit. In den Ranglisten kannst du sie mit „Nur echte“ ausblenden.")
                }
                .padding(DS.Space.l)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verstanden") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
