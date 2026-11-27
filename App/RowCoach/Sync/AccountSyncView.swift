import SwiftUI
import RowCoachKit

/// Einstellungen → Konto & Synchronisation (docs/SYNC.md). Ohne Konto bleibt alles auf dem Gerät; erst „Anmelden“
/// oder „Registrieren“ richtet Firebase ein. Synchronisation und Forschung sind getrennte Schalter, beide aus,
/// bis man sie selbst einschaltet.
struct AccountSyncView: View {
    @State private var sync = SyncController.shared
    @State private var email = ""
    @State private var password = ""
    @State private var registering = false
    @State private var confirmSync = false
    @State private var confirmDeleteData = false
    @State private var confirmDeleteAccount = false
    @State private var exportURL: URL?

    var body: some View {
        Form {
            introSection
            if !sync.serverAvailable {
                Section {
                    Text("In diesem Build ist kein Server eingerichtet. Die App funktioniert vollständig ohne Konto.")
                        .foregroundStyle(Theme.text2)
                }
            } else if let user = sync.user {
                if user.canWrite {
                    accountSection(user)
                    syncSection
                    researchSection
                    dataSection
                } else {
                    verifySection(user)
                }
            } else {
                signInSection
            }
            messagesSection
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text("Konto & Synchronisation"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(sync.isWorking)
        .overlay { if sync.isWorking { ProgressView() } }
        .task { if sync.user != nil { await sync.refreshUser() } }
        .confirmationDialog("Synchronisation einschalten?", isPresented: $confirmSync, titleVisibility: .visible) {
            Button("Einwilligen und einschalten") { Task { await sync.setSyncEnabled(true) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(SyncSettings.syncConsentText)
        }
        .confirmationDialog("Alle Server-Daten löschen?", isPresented: $confirmDeleteData, titleVisibility: .visible) {
            Button("Server-Daten löschen", role: .destructive) { Task { await sync.deleteServerData() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Fahrten, Einstellungen und Einwilligungen werden vom Server entfernt. Auf diesem Gerät bleibt alles erhalten. Die Synchronisation wird ausgeschaltet.")
        }
        .confirmationDialog("Konto löschen?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Konto und Server-Daten löschen", role: .destructive) { Task { await sync.deleteAccount() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Konto und alle Server-Daten werden endgültig gelöscht. Auf diesem Gerät bleibt alles erhalten.")
        }
    }

    // MARK: Abschnitte

    private var introSection: some View {
        Section {
            Text("RowCoach funktioniert vollständig ohne Konto und ohne Internet. Mit einem kostenlosen Konto kannst du deine Fahrten, dein Profil und deine Trainingseinstellungen zwischen deinen Geräten abgleichen.")
                .font(.footnote)
                .foregroundStyle(Theme.text2)
        }
    }

    private var signInSection: some View {
        Group {
            Section {
                Button {
                    Task { await sync.signInWithGoogle() }
                } label: {
                    Label("Mit Google anmelden", systemImage: "person.crop.circle")
                }
                .disabled(!sync.googleAvailable)
                .foregroundStyle(Theme.link)
            } footer: {
                if !sync.googleAvailable {
                    Text("Anmeldung mit Google ist in diesem Build noch nicht eingerichtet.")
                }
            }
            Section {
                Picker("Konto", selection: $registering) {
                    Text("Anmelden").tag(false)
                    Text("Registrieren").tag(true)
                }
                .pickerStyle(.segmented)
                TextField("E-Mail-Adresse", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Passwort", text: $password)
                    .textContentType(registering ? .newPassword : .password)
                Button(registering ? String(localized: "Konto erstellen") : String(localized: "Anmelden")) {
                    Task {
                        if registering {
                            await sync.register(email: email, password: password)
                        } else {
                            await sync.signIn(email: email, password: password)
                        }
                        password = ""
                    }
                }
                .disabled(email.isEmpty || password.isEmpty)
                .foregroundStyle(Theme.link)
                if !registering {
                    Button("Passwort vergessen?") { Task { await sync.resetPassword(email: email) } }
                        .foregroundStyle(Theme.link)
                }
            } header: {
                Text("Mit E-Mail")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(registering ? String(localized: "Nach der Registrierung kommt ein Bestätigungslink per E-Mail. Sobald du ihn öffnest, startet die Synchronisation von selbst. Passwort mindestens 6 Zeichen.")
                         : String(localized: "Ohne Anmeldung sendet RowCoach nichts an unseren Server."))
                    Text("Mit der Anmeldung schaltest du die Synchronisation ein:") + Text(" ") + Text(SyncSettings.syncConsentText)
                }
            }
        }
    }

    private func verifySection(_ user: SyncUser) -> some View {
        Section {
            Text("Bitte bestätige deine E-Mail-Adresse. Der Link ging an \(user.email ?? "–").")
            Button("Ich habe bestätigt") { Task { await sync.checkVerification() } }
                .foregroundStyle(Theme.link)
            Button("Link erneut senden") { Task { await sync.resendVerification() } }
                .foregroundStyle(Theme.link)
            Button("Abmelden", role: .destructive) { Task { await sync.signOut() } }
        } header: {
            Text("Konto")
        }
    }

    private func accountSection(_ user: SyncUser) -> some View {
        Section {
            LabeledContent("Angemeldet als", value: user.email ?? "–")
            Button("Abmelden") { Task { await sync.signOut() } }
                .foregroundStyle(Theme.link)
        } header: {
            Text("Konto")
        } footer: {
            Text("Beim Abmelden bleiben alle Daten auf diesem Gerät.")
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("Synchronisation", isOn: Binding(
                get: { sync.syncEnabled },
                set: { on in
                    if on { confirmSync = true } else { Task { await sync.setSyncEnabled(false) } }
                }))
            if sync.syncEnabled {
                if let last = sync.lastSync {
                    LabeledContent("Zuletzt abgeglichen", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if sync.pendingRides > 0 {
                    LabeledContent("Ausstehende Fahrten", value: "\(sync.pendingRides)")
                }
                if let s = sync.statusText {
                    Text(s).font(.footnote).foregroundStyle(Theme.bad)
                }
                Button("Jetzt abgleichen") { Task { await sync.syncNow() } }
                    .foregroundStyle(Theme.link)
            }
        } header: {
            Text("Synchronisation")
        } footer: {
            Text("Kostenlos. Abgeglichen werden Fahrten mit Belastung, Profil und Figur, Puls und Bestzeit, Trainingsplan und Motivations-Einstellungen. Die Daten liegen in der Schweiz (Zürich).")
        }
    }

    private var researchSection: some View {
        Section {
            Toggle("Daten für Forschung freigeben", isOn: Binding(
                get: { sync.researchConsent },
                set: { on in Task { await sync.setResearchConsent(on) } }))
            if sync.researchConsent, let at = sync.researchConsentAt {
                LabeledContent("Eingewilligt am", value: at.formatted(date: .abbreviated, time: .shortened))
            }
        } header: {
            Text("Forschung")
        } footer: {
            Text(SyncSettings.researchConsentText)
        }
    }

    private var dataSection: some View {
        Section {
            Button("Server-Daten exportieren") {
                Task { exportURL = await sync.exportServerData() }
            }
            .foregroundStyle(Theme.link)
            if let url = exportURL {
                ShareLink(item: url) { Label("Export teilen", systemImage: "square.and.arrow.up") }
            }
            Button("Alle Server-Daten löschen", role: .destructive) { confirmDeleteData = true }
            Button("Konto löschen", role: .destructive) { confirmDeleteAccount = true }
        } header: {
            Text("Deine Daten")
        } footer: {
            Text("Der Export enthält alles, was auf dem Server zu deinem Konto liegt (JSON).")
        }
    }

    @ViewBuilder
    private var messagesSection: some View {
        if sync.errorMessage != nil || sync.infoMessage != nil {
            Section {
                if let e = sync.errorMessage { Text(e).foregroundStyle(Theme.bad) }
                if let i = sync.infoMessage { Text(i).foregroundStyle(Theme.text2) }
            }
            .font(.footnote)
        }
    }
}
