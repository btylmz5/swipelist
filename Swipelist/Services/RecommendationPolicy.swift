import Foundation

enum RecommendationFeatures {
    // Public rollout remains off until the human quality and blind preference gates pass.
    static var v2: Bool {
#if DEBUG
        !UserDefaults.standard.bool(forKey: "disableRecommendationV2")
#else
        false
#endif
    }
    static let spotifyAnalysisApproved = false // Written approval is NOT implied by this experiment.
    static var spotifyLocalExperiment: Bool {
#if DEBUG
        v2 && !UserDefaults.standard.bool(forKey: "disableSpotifyLocalExperiment")
#else
        false
#endif
    }
}

struct BriefConstraints: Codable, Equatable {
    struct Condition: Codable, Equatable {
        let id: String
        let dimension: String
        let value: String
        let explicit: Bool
    }
    let conditions: [Condition]
}
struct PreferenceProfile: Codable, Equatable {
    var artists: [String] = []
    var examples: [String] = [] // User-entered Artist — Song, never imported metadata.
    var likes: [String] = []
    var avoids: [String] = []
    var completed = false
    var source = "user_explicit"
    var isEmpty: Bool { artists.isEmpty && examples.isEmpty && likes.isEmpty && avoids.isEmpty }
    var isEligible: Bool { source == "user_explicit" }
    var hasPositiveReferences: Bool { !artists.isEmpty || !examples.isEmpty || !likes.isEmpty }
    var exampleKeys: Set<String> {
        Set(examples.compactMap { value in
            let parts = value.components(separatedBy: " — ")
            let fallback = value.components(separatedBy: " - ")
            let segments = parts.count == 2 ? parts : fallback
            guard segments.count == 2 else { return nil }
            return TrackCandidate(artist: segments[0], title: segments[1]).dedupeKey
        })
    }
}
struct RecommendationSession: Encodable {
    struct Entry: Encodable { let artist: String; let track: String; var verdict: String? = nil }
    let source = "swipelist_model"
    var excluded: [Entry] = []
    var feedback: [Entry] = []
}

struct CandidateAssessment: Codable, Equatable {
    struct TasteEvidence: Codable, Equatable {
        let referenceID: String
        let verdict: String
        let detail: String
    }

    struct Check: Codable, Equatable {
        let conditionID: String
        let verdict: String // match, conflict, uncertain
    }
    let checks: [Check]
    let relevance: Double
    let taste: Double
    let reason: String
    var tasteEvidence: [TasteEvidence]? = nil
    var hasPersonalEvidence: Bool {
        taste >= 0.6 && tasteEvidence?.contains(where: { $0.verdict == "match" }) == true &&
        tasteEvidence?.contains(where: { $0.verdict == "conflict" }) != true
    }
    func accepts(_ brief: BriefConstraints) -> Bool {
        guard !brief.conditions.isEmpty, relevance.isFinite, taste.isFinite,
              (0...1).contains(relevance), (0...1).contains(taste), !reason.isEmpty else { return false }
        return brief.conditions.allSatisfy { condition in
            let entries = checks.filter { $0.conditionID == condition.id }
            guard entries.count == 1 else { return false }
            return condition.explicit ? entries[0].verdict == "match" : ["match", "uncertain"].contains(entries[0].verdict)
        }
    }
}
struct AssessedCandidate: Codable {
    let id: String
    let artist: String
    let track: String
    let assessment: CandidateAssessment
    var candidate: TrackCandidate { TrackCandidate(artist: artist, title: track) }
}
struct RecommendationBatch: Decodable {
    let version: Int
    let constraints: BriefConstraints
    let songs: [AssessedCandidate]
    let rejected: Int
}
struct RecommendationTrace {
    var generated = 0
    var rejected = 0
    var resolved = 0
    var noPreview = 0
    var unresolved = 0
    var accepted = 0
    func log() {
        NSLog("SWTRACE generated=%d rejected=%d resolved=%d noPreview=%d unresolved=%d accepted=%d", generated, rejected, resolved, noPreview, unresolved, accepted)
    }
}

enum PreferenceRanking {
    static func rank(_ songs: [AssessedCandidate], constraints: BriefConstraints,
                     mode: RecommendationMode, profile: PreferenceProfile,
                     known: Set<String>, familiarShare: Double, limit: Int, history: ListeningHistory? = nil, previousCount: Int = 0, previousFamiliar: Int = 0) -> [AssessedCandidate] {
        let hasProfile = !profile.isEmpty && profile.isEligible
        let hasHistory = history?.signals.isEmpty == false
        let weight = hasProfile || hasHistory ? mode.tasteWeight : 0
        func taste(_ song: AssessedCandidate) -> Double {
            guard hasHistory else { return hasProfile ? song.assessment.taste : 0 }
            let local = history?.affinity(song.candidate) ?? 0
            return hasProfile ? 0.25 * local + 0.75 * song.assessment.taste : local
        }
        let eligible = songs.filter { $0.assessment.accepts(constraints) }.uniqued { $0.candidate.dedupeKey }
        let sorted = eligible.sorted {
            let a = (1-weight) * $0.assessment.relevance + weight * taste($0)
            let b = (1-weight) * $1.assessment.relevance + weight * taste($1)
            return a == b ? $0.id < $1.id : a > b
        }
        var familiar = sorted.filter { known.contains($0.candidate.dedupeKey) }
        var other = sorted.filter { !known.contains($0.candidate.dedupeKey) }
        var result: [AssessedCandidate] = []; var count = previousFamiliar
        let share = min(1, max(0, familiarShare))
        while result.count < max(0,limit) && (!familiar.isEmpty || !other.isEmpty) {
            if other.isEmpty || (!familiar.isEmpty && count < Int((Double(previousCount+result.count+1)*share).rounded())) {
                result.append(familiar.removeFirst()); count += 1
            } else { result.append(other.removeFirst()) }
        }
        return result
    }
}
extension RecommendationMode {
    var tasteWeight: Double { switch self { case .discovery: 0.2; case .balanced: 0.5; case .personal: 0.8 } }
}

enum RecordingIdentity {
    static func matches(artist: String, title: String, wantedArtist: String, wantedTitle: String) -> Bool {
        // Only strip known edition labels, never arbitrary parenthetical titles.
        func key(_ value: String) -> String {
            value.replacingOccurrences(of: #"(?i)\s*[\(\[][^\)\]]*(?:remaster(?:ed)?|feat\.|featuring)[^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\s+-\s+(?:\d{4}\s+)?remaster(?:ed)?.*$"#, with: "", options: .regularExpression).folded
        }
        return artist.artistComponents.contains(wantedArtist.primaryArtistKey) && key(title) == key(wantedTitle)
    }
}

// Future Spotify adapter contract. Transport remains disabled pending approval.
struct MusicEvidence: Sendable {
    enum Source: String, Sendable { case topTracks, topArtists, recent, saved, playlist }
    enum Window: String, Sendable { case shortTerm, mediumTerm, longTerm, recent, unspecified }
    let providerID: String
    let source: Source
    let window: Window
    let rank: Int?
    let occurredAt: Date?
    let contextURI: String?
}
struct SourceAvailability: Sendable {
    enum Status: Sendable { case available, partial, permissionRequired, unavailable, policyDisabled }
    let source: MusicEvidence.Source
    let status: Status
    let lastSuccess: Date?
}

struct SuggestionRateLimit: LocalizedError {
    let until: Date
    var errorDescription: String? { "Suggestions are busy. Please wait before trying again." }
}
