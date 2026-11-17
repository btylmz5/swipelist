import Foundation

/// Spotify API configuration.
///
/// The app must be registered at https://developer.spotify.com/dashboard with
/// `swipelist://callback` listed as a redirect URI, and the URL scheme declared in
/// Info.plist, or the OAuth callback never reaches the app.
enum SpotifyConfig {
    static var clientID: String { Secrets.spotifyClientID }

    static let redirectURI = "swipelist://callback"
    static let callbackScheme = "swipelist"

    /// `playlist-modify-*` is what lets the app write the finished playlist back.
    static let scopes = [
        "user-read-private",
        "user-read-email",
        "playlist-modify-public",
        "playlist-modify-private",
    ]

    static let readScopes = ["user-top-read", "user-read-recently-played", "user-library-read", "playlist-read-private", "playlist-read-collaborative"]

    static let authBaseURL = "https://accounts.spotify.com"
    static let apiBaseURL = "https://api.spotify.com/v1"
    static let tokenURL = "\(authBaseURL)/api/token"
    static let authorizeURL = "\(authBaseURL)/authorize"
}

/// Typed errors for the Spotify layer.
enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case spotifyRefused(String)
    case rateLimitExceeded
    case serverError(statusCode: Int)
    case decodingError(underlying: Error)
    case invalidResponse
    case tokenRefreshFailed
    case tokenExchangeFailed(status: Int, body: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .unauthorized: return "Session expired. Please sign in again."
        case .forbidden: return "Spotify refused the request."
        case .spotifyRefused(let detail):
            return detail.isEmpty ? "Spotify refused the request." : "Spotify: \(detail)"
        case .rateLimitExceeded: return "Too many requests. Please wait a moment."
        case .serverError(let code): return "Spotify server error (\(code))."
        case .decodingError(let error): return "Couldn't read Spotify's response: \(error.localizedDescription)"
        case .invalidResponse: return "Invalid response from Spotify."
        case .tokenRefreshFailed: return "Couldn't refresh the Spotify session."
        case .tokenExchangeFailed(let status, let body):
            return "Spotify rejected the sign-in (HTTP \(status)). \(body)"
        case .notConfigured: return "No Spotify client ID configured."
        }
    }
}
