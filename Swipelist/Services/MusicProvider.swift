import Foundation

/// A music service the app can resolve songs against and write playlists back to.
///
/// The deck talks to this rather than to Spotify directly, so a second service is a
/// new conformance rather than a rewrite. Apple Music is the intended next one; it
/// needs a paid Apple Developer account and MusicKit, so it's deliberately absent
/// rather than stubbed.
protocol MusicProvider: Sendable {
    /// Stable identifier, matching the `provider` column in `platform_connections`.
    var id: MusicProviderID { get }
    /// Shown in the UI: "Spotify", "Apple Music".
    var displayName: String { get }

    /// Whether a usable session exists right now.
    var isConnected: Bool { get async }

    func listeningHistory() async throws -> ListeningHistoryResult

    /// Resolves a named song to something playable. Returns nil when the service
    /// has nothing matching — the caller drops it rather than substituting.
    func resolve(artist: String, title: String) async throws -> Track?

    /// The artist's own songs, straight from the service's catalogue.
    ///
    /// This is how music released after the suggestion model's training cutoff
    /// reaches the deck: the model can only name songs it has seen, the catalogue
    /// knows everything the service streams today. Implementations must return the
    /// pool date-blind — unsorted and unfiltered by release date — so the caller's
    /// uniform sampling gives a new album exactly the share its track count earns.
    /// Optional; the default returns nothing.
    func artistCatalog(artistID: String, artistName: String) async throws -> [Track]

    /// Creates a playlist on the service and adds the tracks. Returns its external id.
    @discardableResult
    func export(name: String, description: String, tracks: [Track]) async throws -> String
}

extension MusicProvider {
    func listeningHistory() async throws -> ListeningHistoryResult {
        throw ListeningHistoryError.unsupported
    }
    func artistCatalog(artistID: String, artistName: String) async throws -> [Track] { [] }
}

enum MusicProviderID: String, CaseIterable, Sendable {
    case spotify
    case appleMusic = "apple_music"
    case deezer

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .deezer: return "Deezer"
        }
    }
}

// MARK: - Spotify conformance

/// Adapts the existing SpotifyService to the provider protocol. The service keeps
/// its own richer API; this is the slice the deck needs.
struct SpotifyProvider: MusicProvider {
    let id: MusicProviderID = .spotify
    let displayName = "Spotify"

    var isConnected: Bool {
        get async { SpotifyService.shared.isAuthenticated }
    }

    func listeningHistory() async throws -> ListeningHistoryResult {
        try await SpotifyService.shared.listeningHistory()
    }

    func resolve(artist: String, title: String) async throws -> Track? {
        try await SpotifyService.shared.searchTrack(artist: artist, title: title)
    }

    func artistCatalog(artistID: String, artistName: String) async throws -> [Track] {
        try await SpotifyService.shared.artistCatalog(artistID: artistID, artistName: artistName)
    }

    @discardableResult
    func export(name: String, description: String, tracks: [Track]) async throws -> String {
        let uris = tracks.compactMap(\.spotifyURI)
        guard !uris.isEmpty else { throw APIError.invalidResponse }
        let playlistID = try await SpotifyService.shared.createPlaylist(
            name: name, description: description
        )
        try await SpotifyService.shared.addTracks(playlistID: playlistID, uris: uris)
        return playlistID
    }
}

// MARK: - Registry

/// Which provider the deck currently builds against.
///
/// Sessions can differ — that's the point of the abstraction — so this is settable
/// rather than a constant.
@MainActor
final class MusicProviders: ObservableObject {
    static let shared = MusicProviders()

    @Published private(set) var active: MusicProviderID = .spotify

    /// Every provider the build actually supports. Apple Music joins this list when
    /// MusicKit is available.
    private let providers: [MusicProviderID: any MusicProvider] = [
        .spotify: SpotifyProvider(),
    ]

    var available: [MusicProviderID] { providers.keys.sorted { $0.rawValue < $1.rawValue } }

    var current: any MusicProvider {
        providers[active] ?? SpotifyProvider()
    }

    func provider(_ id: MusicProviderID) -> (any MusicProvider)? { providers[id] }

    func setActive(_ id: MusicProviderID) {
        guard providers[id] != nil else { return }
        active = id
    }
}
