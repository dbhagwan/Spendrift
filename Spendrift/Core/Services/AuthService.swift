import AuthenticationServices
import Foundation

/// Sign in with Apple. The Apple user identifier is stored in the Keychain and
/// exchanged with the backend for a session token. No passwords on device.
@MainActor
@Observable
final class AuthService {
    private(set) var isSignedIn: Bool

    init() {
        isSignedIn = KeychainStore.get(.appleUserID) != nil
    }

    func handleAuthorization(_ result: Result<ASAuthorization, Error>) async -> Bool {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return false
            }
            KeychainStore.set(credential.user, for: .appleUserID)
            // TODO(backend): exchange `credential.identityToken` for a backend
            // session via POST /auth/apple, then store the session token:
            // KeychainStore.set(session.token, for: .sessionToken)
            isSignedIn = true
            return true
        case .failure:
            return false
        }
    }

    /// Development bypass so the app is navigable without an Apple ID
    /// (e.g. in the simulator without an account configured).
    func signInForDevelopment() {
        KeychainStore.set("dev-user", for: .appleUserID)
        isSignedIn = true
    }

    func signOut() {
        KeychainStore.delete(.appleUserID)
        KeychainStore.delete(.sessionToken)
        isSignedIn = false
    }
}
