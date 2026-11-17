import Foundation

/// Minimal Supabase client over GoTrue (auth) and PostgREST (data).
///
/// Hand-rolled rather than pulling in the official SDK: this Xcode project has a
/// hand-written project file with no Swift Package Manager wiring, and the app
/// already contains an equivalent OAuth + Keychain + refresh flow for Spotify.
/// Reusing that shape keeps the dependency count at zero and the two auth paths
/// consistent.
enum Supabase {
    static var baseURL: String { Secrets.supabaseURL }
    static var anonKey: String { Secrets.supabaseAnonKey }
    static var isConfigured: Bool { !baseURL.isEmpty && !anonKey.isEmpty }

    static let redirectURI = "swipelist://auth-callback"
    static let callbackScheme = "swipelist"

    enum SupabaseError: LocalizedError {
        case notConfigured
        case notSignedIn
        case http(status: Int, message: String)
        case decoding(underlying: Error)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Supabase isn't configured."
            case .notSignedIn: return "You need to sign in first."
            case .http(let status, let message):
                return message.isEmpty ? "Server error (\(status))." : message
            case .decoding(let error): return "Couldn't read the response: \(error.localizedDescription)"
            case .invalidResponse: return "Unexpected response from the server."
            }
        }
    }
}

// MARK: - Session

/// A signed-in Supabase session. Stored in the Keychain alongside the Spotify one.
struct SupabaseSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String
    let email: String?

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

// MARK: - Token / user wire types

struct GoTrueSession: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let user: GoTrueUser?
}

struct GoTrueUser: Decodable {
    let id: String
    let email: String?
    let user_metadata: [String: AnyDecodable]?

    var displayName: String? {
        for key in ["full_name", "name", "preferred_username"] {
            if case let .string(value)? = user_metadata?[key]?.value { return value }
        }
        return nil
    }
}

/// Just enough dynamic decoding to read a display name out of provider metadata.
struct AnyDecodable: Decodable {
    enum Value { case string(String), other }
    let value: Value

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = .string(string)
        } else {
            value = .other
        }
    }
}
