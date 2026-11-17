import Foundation
import Security

/// Keychain wrapper for Spotify tokens. Ported from the earlier Swipelist.
final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()

    private let serviceName = "com.batuyilmaz.Swipelist"

    enum Key: String {
        case accessToken = "spotify_access_token"
        case refreshToken = "spotify_refresh_token"
        case tokenExpiry = "spotify_token_expiry"
        case grantedScopes = "spotify_granted_scopes"
        case supabaseSession = "supabase_session"
    }

    private init() {}

    // MARK: - Tokens

    /// An access token exists and hasn't expired.
    var hasValidToken: Bool {
        guard load(.accessToken) != nil else { return false }
        guard let expiry = load(.tokenExpiry).flatMap(Double.init) else { return false }
        return Date().timeIntervalSince1970 < expiry
    }

    /// The stored grant includes playlist write access. Without it, saving a
    /// playlist fails at the very end of the flow — better to re-authorize first.
    var hasPlaylistScopes: Bool {
        guard let scopes = load(.grantedScopes) else { return false }
        let granted = Set(scopes.split(separator: " ").map(String.init))
        return granted.contains("playlist-modify-private") || granted.contains("playlist-modify-public")
    }

    var hasListeningHistoryScopes: Bool {
        let scopes = Set((load(.grantedScopes) ?? "").split(separator: " ").map(String.init))
        return scopes.isSuperset(of: ["user-top-read", "user-read-recently-played"])
    }

    func store(_ response: TokenResponse) {
        save(.accessToken, response.access_token)
        if let refresh = response.refresh_token {
            save(.refreshToken, refresh)
        }
        save(.tokenExpiry, String(Date().timeIntervalSince1970 + Double(response.expires_in)))
        if let scope = response.scope {
            save(.grantedScopes, scope)
        }
    }

    func clearAll() {
        // Deliberately not the Supabase session — signing out of Spotify
        // shouldn't sign you out of your Swipelist account.
        [Key.accessToken, .refreshToken, .tokenExpiry, .grantedScopes].forEach { delete($0) }
    }

    // MARK: - Primitives

    /// Set when the Keychain is unavailable — unsigned simulator builds have no
    /// `application-identifier` entitlement, so SecItemAdd fails with -34018 and
    /// every token write is silently lost. Falling back keeps development builds
    /// working; the Keychain is still used whenever it's actually available.
    private var memoryFallback: [String: String] = [:]
    private var useMemoryFallback = false

    @discardableResult
    func save(_ key: Key, _ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess {
            memoryFallback[key.rawValue] = value
            return true
        }

        NSLog("SWKEYCHAIN save failed for %@ — OSStatus %d; using in-memory store", key.rawValue, Int(status))
        useMemoryFallback = true
        memoryFallback[key.rawValue] = value
        return true
    }

    func load(_ key: Key) -> String? {
        if useMemoryFallback, let value = memoryFallback[key.rawValue] { return value }
        return loadFromKeychain(key) ?? memoryFallback[key.rawValue]
    }

    private func loadFromKeychain(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(_ key: Key) -> Bool {
        memoryFallback[key.rawValue] = nil
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Round-trips a value to report whether the Keychain is usable at all.
    func selfTest() -> String {
        let probe = "probe-\(UUID().uuidString.prefix(8))"
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "swipelist_selftest",
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(probe.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        SecItemDelete(base as CFDictionary)
        return status == errSecSuccess ? "OK" : "FAILED OSStatus \(status)"
    }
}

struct TokenResponse: Decodable, Sendable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String?
    let scope: String?
}
