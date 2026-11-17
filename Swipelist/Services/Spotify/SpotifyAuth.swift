import AuthenticationServices
import Foundation
import UIKit

/// Drives the Spotify OAuth PKCE flow and holds session state.
@MainActor
final class SpotifyAuth: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var user: SpotifyUser?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let service = SpotifyService.shared
    private let keychain = KeychainService.shared
    private var session: ASWebAuthenticationSession?

    var hasReadAccess: Bool {
        Set((keychain.load(.grantedScopes) ?? "").split(separator: " ").map(String.init)).isSuperset(of: SpotifyConfig.readScopes)
    }
    var hasListeningHistoryAccess: Bool { keychain.hasListeningHistoryScopes }

    var isConfigured: Bool { !SpotifyConfig.clientID.isEmpty }

    /// Restores a previous session on launch.
    func restoreSession() async {
        guard keychain.hasValidToken else {
            isAuthenticated = false
            return
        }
        // A grant without playlist scopes fails only at save time, which is the
        // worst possible moment — force a fresh sign-in instead.
        guard keychain.hasPlaylistScopes else {
            keychain.clearAll()
            isAuthenticated = false
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            user = try await service.currentUser()
            isAuthenticated = true
        } catch {
            do {
                try await service.refreshAccessToken()
                user = try await service.currentUser()
                isAuthenticated = true
            } catch {
                keychain.clearAll()
                isAuthenticated = false
            }
        }
    }

    func signIn(readAccess: Bool = false) async {
        guard isConfigured else {
            errorMessage = APIError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        // Preserve the existing grant if the user cancels the permission upgrade.
        let verifier = SpotifyService.generateCodeVerifier()
        let challenge = SpotifyService.generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

        guard let authURL = service.buildAuthorizationURL(codeChallenge: challenge, state: state, readAccess: readAccess) else {
            errorMessage = "Couldn't build the Spotify sign-in URL."
            return
        }

        do {
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: SpotifyConfig.callbackScheme
                ) { url, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: APIError.invalidResponse) }
                }
                session.presentationContextProvider = PresentationAnchor.shared
                // Fresh browser each time, so the consent screen always appears and
                // scopes are re-granted rather than silently reused.
                session.prefersEphemeralWebBrowserSession = true
                self.session = session
                session.start()
            }
            self.session = nil

            let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
            guard let returnedState = components?.queryItems?.first(where: { $0.name == "state" })?.value,
                  returnedState == state else {
                errorMessage = "Sign-in response didn't match the request."
                return
            }
            guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
                errorMessage = "Spotify didn't return an authorization code."
                return
            }

            try await service.exchangeCode(code, codeVerifier: verifier)
            user = try await service.currentUser()
            isAuthenticated = true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User backed out — not an error worth showing.
            session = nil
        } catch {
            session = nil
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        service.logout()
        isAuthenticated = false
        user = nil
    }
}

/// Supplies the window ASWebAuthenticationSession presents from.
private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationAnchor()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return ASPresentationAnchor() }
        return scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first ?? UIWindow(windowScene: scene)
    }
}
