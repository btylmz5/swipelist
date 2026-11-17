import AuthenticationServices
import Foundation
import UIKit

/// Swipelist account: sign in with Google, or email and password.
///
/// This is the app's own identity. Music services are linked to it separately, so a
/// listener can connect Spotify on one device and Apple Music on another and keep
/// the same library, taste and history.
@MainActor
final class SupabaseAuth: ObservableObject {
    static let shared = SupabaseAuth()

    @Published private(set) var session: SupabaseSession?
    @Published private(set) var displayName: String?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    var isSignedIn: Bool { session != nil }
    var userID: String? { session?.userID }

    private let keychain = KeychainService.shared
    private var webSession: ASWebAuthenticationSession?

    private init() {}

    // MARK: - Restore

    /// Reloads a stored session on launch, refreshing it if it has expired.
    func restore() async {
        guard Supabase.isConfigured,
              let data = keychain.load(.supabaseSession)?.data(using: .utf8),
              let stored = try? JSONDecoder().decode(SupabaseSession.self, from: data)
        else { return }

        if stored.isExpired {
            do {
                session = try await refresh(using: stored.refreshToken)
            } catch {
                keychain.delete(.supabaseSession)
                session = nil
            }
        } else {
            session = stored
        }
        displayName = session?.email
    }

    // MARK: - Google

    func signInWithGoogle() async {
        guard Supabase.isConfigured else {
            errorMessage = Supabase.SupabaseError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        var components = URLComponents(string: "\(Supabase.baseURL)/auth/v1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Supabase.redirectURI),
        ]
        guard let url = components.url else {
            errorMessage = "Couldn't build the sign-in URL."
            return
        }

        do {
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: url, callbackURLScheme: Supabase.callbackScheme
                ) { url, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: Supabase.SupabaseError.invalidResponse) }
                }
                session.presentationContextProvider = AuthAnchor.shared
                session.prefersEphemeralWebBrowserSession = true
                self.webSession = session
                session.start()
            }
            webSession = nil
            NSLog("SWGAUTH callback scheme=%@ host=%@ hasFragment=%d hasQuery=%d",
                  callback.scheme ?? "-", callback.host ?? "-",
                  (callback.fragment?.isEmpty == false) ? 1 : 0,
                  (callback.query?.isEmpty == false) ? 1 : 0)
            try adopt(callback: callback)
            NSLog("SWGAUTH adopted, isSignedIn=%d", session != nil ? 1 : 0)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            NSLog("SWGAUTH cancelled by user")
            webSession = nil
        } catch {
            NSLog("SWGAUTH failed: %@", error.localizedDescription)
            webSession = nil
            errorMessage = error.localizedDescription
        }
    }

    /// GoTrue returns tokens in the URL *fragment*, not the query string.
    private func adopt(callback: URL) throws {
        let fragment = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.fragment ?? ""
        var fields: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1]).removingPercentEncoding
        }

        NSLog("SWGAUTH fragment keys: %@", fields.keys.sorted().joined(separator: ","))
        if let description = fields["error_description"] {
            throw Supabase.SupabaseError.http(status: 400, message: description)
        }
        guard let accessToken = fields["access_token"],
              let refreshToken = fields["refresh_token"] else {
            let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            NSLog("SWGAUTH no tokens in fragment; query keys: %@",
                  query.map(\.name).joined(separator: ","))
            throw Supabase.SupabaseError.invalidResponse
        }
        let lifetime = Double(fields["expires_in"] ?? "3600") ?? 3600

        // The user id lives in the JWT payload; no extra round trip needed.
        let claims = Self.decodeJWT(accessToken)
        let userID = claims["sub"] as? String ?? ""
        let email = claims["email"] as? String

        store(SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(lifetime),
            userID: userID,
            email: email
        ))
    }

    // MARK: - Email + password

    func signUp(email: String, password: String) async {
        await emailRequest(path: "signup", email: email, password: password)
    }

    func signIn(email: String, password: String) async {
        await emailRequest(path: "token?grant_type=password", email: email, password: password)
    }

    private func emailRequest(path: String, email: String, password: String) async {
        guard Supabase.isConfigured else {
            errorMessage = Supabase.SupabaseError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
            let data = try await post("/auth/v1/\(path)", body: body)
            let decoded = try JSONDecoder().decode(GoTrueSession.self, from: data)
            guard let user = decoded.user else {
                // Signup with email confirmation on returns a user but no session.
                errorMessage = "Check your email to confirm the account, then sign in."
                return
            }
            store(SupabaseSession(
                accessToken: decoded.access_token,
                refreshToken: decoded.refresh_token,
                expiresAt: Date().addingTimeInterval(Double(decoded.expires_in)),
                userID: user.id,
                email: user.email
            ))
            displayName = user.displayName ?? user.email
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Session lifecycle

    /// A valid access token, refreshing first if the stored one has expired.
    func validAccessToken() async throws -> String {
        guard let current = session else { throw Supabase.SupabaseError.notSignedIn }
        guard current.isExpired else { return current.accessToken }
        let refreshed = try await refresh(using: current.refreshToken)
        session = refreshed
        return refreshed.accessToken
    }

    @discardableResult
    private func refresh(using refreshToken: String) async throws -> SupabaseSession {
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let data = try await post("/auth/v1/token?grant_type=refresh_token", body: body)
        let decoded = try JSONDecoder().decode(GoTrueSession.self, from: data)
        let claims = Self.decodeJWT(decoded.access_token)
        let refreshed = SupabaseSession(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: Date().addingTimeInterval(Double(decoded.expires_in)),
            userID: decoded.user?.id ?? claims["sub"] as? String ?? "",
            email: decoded.user?.email ?? claims["email"] as? String
        )
        persist(refreshed)
        return refreshed
    }

    func signOut() {
        keychain.delete(.supabaseSession)
        session = nil
        displayName = nil
    }

    private func store(_ new: SupabaseSession) {
        persist(new)
        session = new
        displayName = new.email
    }

    private func persist(_ new: SupabaseSession) {
        if let data = try? JSONEncoder().encode(new), let json = String(data: data, encoding: .utf8) {
            keychain.save(.supabaseSession, json)
        }
    }

    // MARK: - Transport

    private func post(_ path: String, body: Data) async throws -> Data {
        var request = URLRequest(url: URL(string: Supabase.baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Supabase.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Supabase.SupabaseError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw Supabase.SupabaseError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return (json["msg"] ?? json["error_description"] ?? json["message"] ?? json["error"]) as? String ?? ""
    }

    /// Reads the payload of a JWT without verifying it — the token came straight
    /// from Supabase over TLS, and it's only used to read our own user id.
    private static func decodeJWT(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return [:] }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }
}

private final class AuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthAnchor()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return ASPresentationAnchor() }
        return scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first ?? UIWindow(windowScene: scene)
    }
}
