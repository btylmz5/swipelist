import Foundation

/// Provider-neutral, session-only data. Never serialized or passed to a model.
struct ListeningHistory: Sendable {
    struct Signal: Sendable {
        let source: String
        let window: String
        let rank: Int?
        let artistKey: String
        let trackKey: String?
        let playedAt: Date?
        let contextURI: String?
        let strength: Double
    }
    var signals: [Signal] = []
    var unavailableSources: [String] = []
    var artistKeys: Set<String> = []
    var trackKeys: Set<String> = []
    var isEmpty: Bool { artistKeys.isEmpty && trackKeys.isEmpty }

    mutating func include(artist: String, title: String? = nil) {
        guard !artist.folded.isEmpty else { return }
        artistKeys.insert(artist.primaryArtistKey)
        if let title, !title.folded.isEmpty {
            trackKeys.insert("\(artist.primaryArtistKey)|\(title.folded)")
        }
    }

    func affinity(_ song: TrackCandidate) -> Double {
        let artist = song.artist.primaryArtistKey
        let track = "\(artist)|\(song.title.folded)"
        let matching = signals.filter { $0.artistKey == artist }
        // Cap each source so a large playlist cannot overwhelm actual listening.
        let scores = Dictionary(grouping: matching, by: { $0.source + "|" + $0.window }).values.map { rows in
            rows.map { $0.strength * ($0.trackKey == track ? 1 : 0.7) }.max() ?? 0
        }
        return min(1, (scores.max() ?? 0) + Double(max(0, scores.count - 1)) * 0.04)
    }

    func knows(_ song: TrackCandidate) -> Bool {
        trackKeys.contains("\(song.artist.primaryArtistKey)|\(song.title.folded)")
    }
}

struct ListeningHistoryResult: Sendable {
    let history: ListeningHistory
    let isPartial: Bool
}

enum ListeningHistoryError: LocalizedError {
    case permissionRequired, unavailable, empty, unsupported

    var errorDescription: String? {
        switch self {
        case .permissionRequired: return "Allow access to your top music and recent listening in Profile to personalize this deck."
        case .unavailable: return "Your listening history couldn't be loaded. Try again, or build from your brief only."
        case .empty: return "Your music service hasn't returned enough listening history yet. You can still build from your brief."
        case .unsupported: return "This music service doesn't support listening history yet. You can still build from your brief."
        }
    }
}

enum RecommendationMode: String, CaseIterable, Identifiable, Sendable {
    case discovery, balanced, personal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discovery: return "Discover"
        case .balanced: return "Balanced"
        case .personal: return "Your taste"
        }
    }
    var detail: String {
        switch self {
        case .discovery: return "Give the brief more weight while exploring beyond your stated favorites."
        case .balanced: return "Balance your stated preferences with the musical brief."
        case .personal: return "Give your stated musical preferences more weight. Every song must still fit your brief."
        }
    }
    /// A selection preference, not a promised final playlist ratio. Preview
    /// availability, diversity caps and the brief can constrain the final mix.
    var familiarShare: Double {
        switch self {
        case .discovery: return 0.2
        case .balanced: return 0.5
        case .personal: return 0.8
        }
    }
}

/// Selects only from the model's brief-matching pool. No songs from listening
/// history are injected, so unrelated past listening cannot override the brief.
/// Release dates and platform popularity never participate in the selection.
enum PersonalizedSelection {
    static func select(
        _ candidates: [TrackCandidate], history: ListeningHistory,
        mode: RecommendationMode, limit: Int
    ) -> [TrackCandidate] {
        guard limit > 0 else { return [] }
        let unique = candidates.uniqued(by: \.dedupeKey)
        guard !history.isEmpty else { return Array(unique.prefix(limit)) }
        var familiar = unique.filter { history.artistKeys.contains($0.artist.primaryArtistKey) }
        var discovery = unique.filter { !history.artistKeys.contains($0.artist.primaryArtistKey) }
        // Even in personal mode, unheard tracks by familiar artists come first.
        // Preserve the model's relevance ordering within each group.
        familiar = familiar.filter { !history.knows($0) } + familiar.filter { history.knows($0) }
        var selected: [TrackCandidate] = []
        var familiarCount = 0
        while selected.count < limit && (!familiar.isEmpty || !discovery.isEmpty) {
            let target = Int((Double(selected.count + 1) * mode.familiarShare).rounded())
            let useFamiliar = discovery.isEmpty || (!familiar.isEmpty && familiarCount < target)
            if useFamiliar {
                selected.append(familiar.removeFirst())
                familiarCount += 1
            } else {
                selected.append(discovery.removeFirst())
            }
        }
        return selected
    }
}

/// Separates transport from decoding/availability so providers and tests use the
/// same partial-data and cancellation rules.
enum ListeningHistorySource: CaseIterable, Sendable {
    case shortTermTracks, mediumTermTracks, topArtists, recentTracks
}

enum ListeningHistoryLoader {
    static func load(fetch: (ListeningHistorySource) async throws -> ListeningHistory) async throws -> ListeningHistoryResult {
        var history = ListeningHistory()
        var successes = 0
        for source in ListeningHistorySource.allCases {
            try Task.checkCancellation()
            do {
                let part = try await fetch(source)
                history.artistKeys.formUnion(part.artistKeys)
                history.trackKeys.formUnion(part.trackKeys)
                successes += 1
            } catch is CancellationError { throw CancellationError() }
            catch { }
        }
        try Task.checkCancellation()
        guard successes > 0 else { throw ListeningHistoryError.unavailable }
        guard !history.isEmpty else { throw ListeningHistoryError.empty }
        return ListeningHistoryResult(history: history, isPartial: successes < ListeningHistorySource.allCases.count)
    }
}

struct ListeningArtist: Decodable { let name: String }
struct ListeningTrack: Decodable {
    let name: String
    let artists: [ListeningArtist]
    func include(in history: inout ListeningHistory) {
        for artist in artists { history.include(artist: artist.name, title: name) }
    }
}
struct ListeningTrackPage: Decodable { let items: [ListeningTrack] }
struct ListeningArtistPage: Decodable { let items: [ListeningArtist] }
struct RecentListeningPage: Decodable {
    struct Item: Decodable { let track: ListeningTrack? }
    let items: [Item]
}
