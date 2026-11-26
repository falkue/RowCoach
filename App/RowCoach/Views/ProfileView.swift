import SwiftUI
import UIKit
import RowCoachKit

/// Einstellungen → „Profil & Figur“: Anzeigename, Nationalität, Geschlecht, Figurtyp mit Farben, Boot und
/// Flaggen-Schalter. Speichert sofort über `RowerProfileStore` (UserDefaults "profile.rower"); die 3D-Szene baut
/// Figur und Boot beim nächsten Aufbau bzw. auf `RowerProfileStore.didChangeAppearance` neu.
/// Vorschaubilder: `Resources/AvatarPreviews/<characterId>.png` bzw. `<boatStyleId>.png` (vom 3D-Generator),
/// bis dahin Platzhalter aus den Katalogfarben.
struct ProfileView: View {
    @Bindable private var store = RowerProfileStore.shared

    private var catalog: AppearanceCatalog { store.catalog }
    private var resolved: AppearanceCatalog.Resolved { store.resolved }
    private var hasNationality: Bool { store.profile.nationality != nil }

    var body: some View {
        Form {
            previewSection
            personSection
            characterSection
            colorSection
            boatSection
            flagSection
            privacySection
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text("Profil & Figur"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
    }

    // MARK: Vorschau

    private var previewSection: some View {
        Section {
            HStack(spacing: DS.Space.m) {
                AvatarPreviewImage(id: resolved.character.id) {
                    FigurePlaceholder(skin: resolved.skin.swiftUIColor, hair: resolved.hair.swiftUIColor,
                                      shirt: resolved.shirt.swiftUIColor)
                }
                .frame(width: 88, height: 88)
                .overlay(alignment: .bottomTrailing) {
                    if let flag = resolved.shirtFlag ?? resolved.boatFlag {
                        Text(verbatim: flag).font(.title2)
                    }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: store.displayName).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(verbatim: resolved.character.name.appText).font(.subheadline).foregroundStyle(Theme.text2)
                    Text(verbatim: resolved.boat.name.appText).font(.subheadline).foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.xs)
        }
    }

    // MARK: Angaben

    private var personSection: some View {
        Section {
            TextField(text: $store.profile.displayName, prompt: Text("Ich")) { Text("Anzeigename") }
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onChange(of: store.profile.displayName) { _, name in
                    if name.count > RowerProfile.maxDisplayNameLength {
                        store.profile.displayName = String(name.prefix(RowerProfile.maxDisplayNameLength))
                    }
                }
            NavigationLink {
                CountryPickerView(selection: $store.profile.nationality)
            } label: {
                LabeledContent {
                    if let code = store.profile.nationality,
                       let c = CountryList.country(code, languageCode: AppLanguage.code) {
                        Text(verbatim: "\(c.flag) \(c.name)")
                    } else {
                        Text("Keine Angabe")
                    }
                } label: {
                    Text("Nationalität")
                }
            }
            Picker(selection: $store.profile.gender) {
                Text("Keine Angabe").tag(RowerProfile.Gender?.none)
                ForEach(RowerProfile.Gender.allCases, id: \.self) { g in
                    Self.genderLabel(g).tag(RowerProfile.Gender?.some(g))
                }
            } label: {
                Text("Geschlecht")
            }
        } header: {
            Text("Angaben")
        } footer: {
            Text("Das Geschlecht bleibt auf diesem Gerät. Die Nationalität sehen andere nur als Flagge, wenn du sie unten einschaltest.")
        }
    }

    private static func genderLabel(_ g: RowerProfile.Gender) -> Text {
        switch g {
        case .female: return Text("Weiblich")
        case .male: return Text("Männlich")
        case .diverse: return Text("Divers")
        }
    }

    // MARK: Figur

    private var characterSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Space.s)], spacing: DS.Space.s) {
                ForEach(catalog.characters) { ch in
                    characterCell(ch)
                }
            }
            .padding(.vertical, DS.Space.xs)
        } header: {
            Text("Figur")
        } footer: {
            Text("Die Figur beschreibt nur das Aussehen im Boot, unabhängig von Geschlecht und Nationalität. Eine neue Figur setzt die Farben auf ihre eigenen zurück.")
        }
    }

    private func characterCell(_ ch: AppearanceCatalog.Character) -> some View {
        let selected = store.profile.appearance.characterId == ch.id
        let own = catalog.resolve(RowerAppearance(characterId: ch.id))
        return Button {
            store.profile.appearance.characterId = ch.id
            store.profile.appearance.skinToneId = nil
            store.profile.appearance.hairColorId = nil
            store.profile.appearance.shirtColorId = nil
        } label: {
            VStack(spacing: 6) {
                AvatarPreviewImage(id: ch.id) {
                    FigurePlaceholder(skin: own.skin.swiftUIColor, hair: own.hair.swiftUIColor,
                                      shirt: own.shirt.swiftUIColor)
                }
                .frame(width: 64, height: 64)
                Text(verbatim: ch.name.appText)
                    .font(.caption)
                    .foregroundStyle(selected ? Theme.text : Theme.text2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(6)
            .background(selected ? Theme.accent.opacity(0.16) : Theme.cardRaised.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: DS.Radius.chip))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip)
                .strokeBorder(selected ? Theme.accent : Theme.cardStroke, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Farben

    private var colorSection: some View {
        Section {
            colorRow(Text("Hautton"), entries: catalog.skinTones, selection: $store.profile.appearance.skinToneId,
                     typeDefault: resolved.character.skinToneId)
            colorRow(Text("Haarfarbe"), entries: catalog.hairColors, selection: $store.profile.appearance.hairColorId,
                     typeDefault: resolved.character.hairColorId)
            colorRow(Text("Trikotfarbe"), entries: catalog.shirtColors,
                     selection: $store.profile.appearance.shirtColorId, typeDefault: resolved.character.shirtColorId)
        } header: {
            Text("Anpassen")
        }
    }

    /// Farbpunkte; die Farbe des Figurtyps entspricht „keine Überschreibung“ (nil)
    private func colorRow(_ title: Text, entries: [AppearanceCatalog.ColorEntry], selection: Binding<String?>,
                          typeDefault: String) -> some View {
        let effective = selection.wrappedValue ?? typeDefault
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            title.font(.subheadline).foregroundStyle(Theme.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(entries) { e in
                        let selected = e.id == effective
                        Button {
                            selection.wrappedValue = e.id == typeDefault ? nil : e.id
                        } label: {
                            Circle()
                                .fill(e.color.swiftUIColor)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2.5))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: e.name.appText))
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, DS.Space.xs)
    }

    // MARK: Boot

    private var boatSection: some View {
        Section {
            ForEach(catalog.boatStyles) { b in
                let selected = resolved.boat.id == b.id
                Button {
                    store.profile.appearance.boatStyleId = b.id
                } label: {
                    HStack(spacing: DS.Space.m) {
                        AvatarPreviewImage(id: b.id) { BoatPlaceholder(style: b) }
                            .frame(width: 84, height: 40)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: b.name.appText).foregroundStyle(Theme.text)
                            if let d = b.description?.appText, !d.isEmpty {
                                Text(verbatim: d).font(.footnote).foregroundStyle(Theme.text2).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent).accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        } header: {
            Text("Boot")
        }
    }

    // MARK: Flaggen

    private var flagSection: some View {
        Section {
            Toggle("Flagge auf dem Trikot", isOn: $store.profile.appearance.flagOnShirt)
                .disabled(!hasNationality)
            Toggle("Flagge auf dem Boot", isOn: $store.profile.appearance.flagOnBoat)
                .disabled(!hasNationality)
        } header: {
            Text("Flaggen")
        } footer: {
            if !hasNationality {
                Text("Für eine Flagge zuerst eine Nationalität wählen.")
            }
        }
    }

    // MARK: Datenschutz

    private var privacySection: some View {
        Section {
            Text("In Rennen und Turnieren sehen andere deinen Anzeigenamen, deine Figur mit ihren Farben und dein Boot. Deine Nationalität nur als Flagge, wenn einer der Schalter an ist. Das Geschlecht sieht niemand.")
                .font(.footnote)
                .foregroundStyle(Theme.text2)
        } header: {
            Text("Was andere sehen")
        }
    }
}

// MARK: - Länderauswahl

/// Durchsuchbare Liste aller Länder mit Flagge; „Keine Angabe“ oben
struct CountryPickerView: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CountryList.Country] = CountryList.all(languageCode: AppLanguage.code)

    var body: some View {
        List {
            if query.isEmpty {
                row(selected: selection == nil, code: nil) {
                    Text("Keine Angabe").foregroundStyle(Theme.text)
                }
            }
            ForEach(results) { c in
                row(selected: selection == c.code, code: c.code) {
                    HStack(spacing: 10) {
                        Text(verbatim: c.flag).font(.title3)
                        Text(verbatim: c.name).foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .searchable(text: $query, prompt: Text("Land suchen"))
        .onChange(of: query) { _, q in
            results = CountryList.search(q, languageCode: AppLanguage.code)
        }
        .navigationTitle(Text("Nationalität"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row<Label: View>(selected: Bool, code: String?, @ViewBuilder label: () -> Label) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                label()
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Vorschaubilder und Platzhalter

/// Vorschaubilder des 3D-Generators im Bundle (`AvatarPreviews/<id>.png`; XcodeGen legt Dateien aus Gruppen
/// flach ins Bundle, deshalb auch ohne Unterordner gesucht)
enum AvatarPreviews {
    static func image(_ id: String) -> UIImage? {
        guard !id.isEmpty else { return nil }
        if let url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "AvatarPreviews")
            ?? Bundle.main.url(forResource: id, withExtension: "png") {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }
}

/// Vorschaubild, sonst Platzhalter
struct AvatarPreviewImage<Placeholder: View>: View {
    let id: String
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let img = AvatarPreviews.image(id) {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            placeholder()
        }
    }
}

/// Platzhalter der Figur: Kopf im Hautton mit Haarkappe vor einem Kreis in der Trikotfarbe
struct FigurePlaceholder: View {
    let skin: Color
    let hair: Color
    let shirt: Color

    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(shirt.opacity(0.45))
                Circle().fill(skin).frame(width: d * 0.5, height: d * 0.5)
                // obere Hälfte als Haar (Kreisbogen 9 → 3 Uhr über oben)
                Circle().trim(from: 0.5, to: 1).fill(hair)
                    .frame(width: d * 0.54, height: d * 0.54)
                    .offset(y: -d * 0.03)
            }
            .frame(width: d, height: d)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Platzhalter des Boots: Rumpf als Kapsel mit Deck, Zierstreifen und Blattfarbe
struct BoatPlaceholder: View {
    let style: AppearanceCatalog.BoatStyle

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Capsule().fill(style.hull.swiftUIColor)
                    .frame(width: w, height: h * 0.34)
                Capsule().fill(style.deck.swiftUIColor)
                    .frame(width: w * 0.55, height: h * 0.14)
                if let stripe = style.stripe {
                    Capsule().fill(stripe.swiftUIColor)
                        .frame(width: w * 0.9, height: max(1.5, h * 0.05))
                        .offset(y: h * 0.1)
                }
                Capsule().fill(style.blade.swiftUIColor)
                    .frame(width: w * 0.16, height: h * 0.22)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                    .offset(x: w * 0.12, y: -h * 0.36)
            }
            .frame(width: w, height: h)
        }
    }
}

extension RGBColor {
    /// Farbe für SwiftUI
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
}
