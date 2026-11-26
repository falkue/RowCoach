import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import RowCoachKit

/// Anmeldung über Firebase Authentication (docs/SYNC.md, „Anmeldung“): E-Mail/Passwort mit Bestätigungslink und
/// „Passwort vergessen“, Google. Sign in with Apple folgt vor dem Store-Start (App-Store-Richtlinie 4.8).
/// Solange Firebase nicht eingerichtet ist, gilt niemand als angemeldet, und es geht keine Anfrage hinaus.
final class FirebaseAuthProvider: AuthProvider {
    private func requireAuth() throws -> Auth {
        guard FirebaseBootstrap.isConfigured else { throw SyncError.unavailable }
        return Auth.auth()
    }

    static func map(_ u: User) -> SyncUser {
        SyncUser(uid: u.uid, email: u.email, emailVerified: u.isEmailVerified,
                 providers: u.providerData.map(\.providerID))
    }

    func currentUser() async -> SyncUser? {
        guard FirebaseBootstrap.isConfigured, let u = Auth.auth().currentUser else { return nil }
        return Self.map(u)
    }

    func signIn(email: String, password: String) async throws -> SyncUser {
        let auth = try requireAuth()
        do {
            return Self.map(try await auth.signIn(withEmail: email, password: password).user)
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Neues Konto; der Bestätigungslink geht sofort hinaus
    func register(email: String, password: String) async throws -> SyncUser {
        let auth = try requireAuth()
        do {
            let user = try await auth.createUser(withEmail: email, password: password).user
            try? await user.sendEmailVerification()
            return Self.map(user)
        } catch {
            throw Self.mapError(error)
        }
    }

    func sendEmailVerification() async throws {
        guard let user = try requireAuth().currentUser else { throw SyncError.notSignedIn }
        do { try await user.sendEmailVerification() } catch { throw Self.mapError(error) }
    }

    func sendPasswordReset(email: String) async throws {
        let auth = try requireAuth()
        do { try await auth.sendPasswordReset(withEmail: email) } catch { throw Self.mapError(error) }
    }

    func reload() async throws -> SyncUser? {
        let auth = try requireAuth()
        guard let user = auth.currentUser else { return nil }
        do { try await user.reload() } catch { throw Self.mapError(error) }
        // neues ID-Token, damit die Regeln `email_verified` sehen
        _ = try? await auth.currentUser?.getIDTokenResult(forcingRefresh: true)
        return auth.currentUser.map(Self.map)
    }

    func signOut() async throws {
        guard FirebaseBootstrap.isConfigured else { return }
        try Auth.auth().signOut()
        await MainActor.run { GIDSignIn.sharedInstance.signOut() }
    }

    func deleteAccount() async throws {
        guard let user = try requireAuth().currentUser else { throw SyncError.notSignedIn }
        do { try await user.delete() } catch { throw Self.mapError(error) }
    }

    // MARK: Google

    static var googleAvailable: Bool { FirebaseBootstrap.googleClientID != nil }

    @MainActor
    func signInWithGoogle() async throws -> SyncUser {
        let auth = try requireAuth()
        guard let clientID = FirebaseBootstrap.googleClientID else { throw SyncError.unavailable }
        guard let presenter = Self.topViewController() else { throw SyncError.unavailable }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch {
            throw SyncError.server(error.localizedDescription)
        }
        guard let idToken = result.user.idToken?.tokenString else { throw SyncError.invalidCredentials }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                       accessToken: result.user.accessToken.tokenString)
        do {
            return Self.map(try await auth.signIn(with: credential).user)
        } catch {
            throw Self.mapError(error)
        }
    }

    @MainActor
    func handle(url: URL) -> Bool {
        guard FirebaseBootstrap.isConfigured else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: Fehler

    /// Firebase-Fehlercodes (FIRAuthErrorDomain) → gemeinsame Fehler des Kits
    static func mapError(_ error: Error) -> SyncError {
        if let e = error as? SyncError { return e }
        let ns = error as NSError
        guard ns.domain == "FIRAuthErrorDomain" else { return .server(ns.localizedDescription) }
        switch ns.code {
        case 17004, 17009, 17011, 17008: return .invalidCredentials // ungültig, falsches Passwort, unbekannt, E-Mail-Form
        case 17007: return .emailInUse
        case 17026: return .weakPassword
        case 17020: return .network(ns.localizedDescription)
        case 17014: return .server(String(localized: "Bitte melde dich neu an und versuche es dann noch einmal."))
        default: return .server(ns.localizedDescription)
        }
    }
}
