// Copy to Swipelist/Config.swift. Keep actual credentials out of source control.
// This template lives outside the automatically compiled Swipelist directory.
import Foundation

enum Secrets {
    // Public client configuration; never put a Supabase service-role key here.
    static let spotifyClientID = ""
    static let supabaseURL = ""
    static let supabaseAnonKey = ""

    // Optional developer probes only. The app's default Claude path uses the
    // authenticated swipelist2-suggest-songs function in Debug and Release.
#if DEBUG
    static let anthropicAPIKey = ""
    static let geminiAPIKey = ""
    static let lastFMAPIKey = ""
#else
    static var anthropicAPIKey: String { "" }
    static var geminiAPIKey: String { "" }
    static var lastFMAPIKey: String { "" }
#endif
}
