// Compile the production DeckBuilder with deterministic service doubles. These
// types live outside the app target and never ship or touch real credentials.
import Foundation
import Combine

typealias ObservableObject = Combine.ObservableObject
typealias Published<Value> = Combine.Published<Value>
struct Track: Sendable {
    let title: String
    let artist: String
    var previewURL: URL?
    var spotifyArtistID: String? = nil
}
final class FakeProvider: MusicProvider, @unchecked Sendable {
    var failure: ListeningHistoryError?
    var partial = false
    var delay: UInt64 = 0
    var noAudioForKnown = false
    var historyCalls = 0
    func listeningHistory() async throws -> ListeningHistoryResult {
        historyCalls += 1
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if let failure { throw failure }
        var history = ListeningHistory()
        for i in 0..<26 { history.include(artist: "Known \(i)", title: "Past favourite") }
        return ListeningHistoryResult(history: history, isPartial: partial)
    }
    func resolve(artist: String, title: String) async throws -> Track? {
        Track(title: title, artist: artist,
              previewURL: noAudioForKnown && artist.hasPrefix("Known") ? nil : URL(string: "https://example.invalid/preview"))
    }
    func artistCatalog(artistID: String, artistName: String) async throws -> [Track] { [] }
}
protocol MusicProvider: Sendable {
    func listeningHistory() async throws -> ListeningHistoryResult
    func resolve(artist: String, title: String) async throws -> Track?
    func artistCatalog(artistID: String, artistName: String) async throws -> [Track]
}
@MainActor final class MusicProviders {
    static let shared = MusicProviders()
    var current = FakeProvider()
}
@MainActor final class SwipeHistory {
    static let shared = SwipeHistory()
    var recentSkipKeys: Set<String> = []
    func record(key: String, liked: Bool) {}
}
@MainActor enum GeminiService {
    static var calls = 0
    static var requestedCounts: [Int] = []
    static var observedRefinements: [[String]] = []
    static var feedbackCounts: [Int] = []
    static func suggestSongs(text: String, refinements: [String], count: Int,
                             liked: [TrackCandidate], skipped: [TrackCandidate],
                             excludeArtists: [String]) async throws -> [TrackCandidate] {
        calls += 1
        requestedCounts.append(count)
        observedRefinements.append(refinements)
        feedbackCounts.append(liked.count + skipped.count)
        let all = (0..<26).map { TrackCandidate(artist: "Known \($0)", title: "Song \(calls)") }
            + (0..<26).map { TrackCandidate(artist: "New \($0)", title: "Song \(calls)") }
        return Array(all.prefix(count))
    }
}
typealias PromptParser = GeminiService
typealias SongSuggestionService = GeminiService
struct ITunesService: Sendable {
    static let shared = ITunesService()
    func previewURL(artist: String, title: String) async -> URL? { nil }
}
enum DeezerService {
    static func previewURL(artist: String, title: String) async -> URL? { nil }
}

@main struct DeckHarness {
    @MainActor static func main() async {
        var failures = 0
        var checks = 0
        func check(_ name: String, _ ok: Bool) {
            checks += 1
            print("\(ok ? "PASS" : "FAIL") \(name)")
            if !ok { failures += 1 }
        }
        func until(_ condition: () -> Bool) async {
            for _ in 0..<200 {
                if condition() { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        func reset() {
            MusicProviders.shared.current = FakeProvider()
            GeminiService.calls = 0
            GeminiService.requestedCounts = []
            GeminiService.observedRefinements = []
            GeminiService.feedbackCounts = []
            SwipeHistory.shared.recentSkipKeys = []
        }
        for (mode, expected) in [(RecommendationMode.discovery, 5), (.balanced, 13), (.personal, 21)] {
            reset()
            let builder = DeckBuilder()
            builder.build(text: "A required brief", refinements: ["Chill"], mode: mode)
            await until { builder.tracks.count == 26 }
            check("\(mode) reaches ready with playable tracks", builder.phase == .ready && builder.tracks.count == 26)
            check("\(mode) survives resolution/interleaving with \(expected) familiar tracks", builder.tracks.filter { $0.artist.hasPrefix("Known") }.count == expected)
            check("model receives only user refinements", GeminiService.observedRefinements == [["Chill"]])
            check("personalization requests a wider pool", GeminiService.requestedCounts == [52])
            if let first = builder.tracks.first { builder.record(first, liked: true, listenedFraction: 0.5) }
            builder.refillIfNeeded(remaining: 6)
            await until { builder.tracks.count >= 44 }
            check("\(mode) adaptive refill grows the deck", builder.tracks.count >= 44)
            check("refill uses the existing session snapshot", MusicProviders.shared.current.historyCalls == 1)
            check("refill retains swipe feedback", GeminiService.feedbackCounts.last == 1)
            let counts = Dictionary(grouping: builder.tracks, by: { $0.artist }).values.map(\.count)
            check("artist caps survive refill", counts.allSatisfy { $0 <= 2 })
            builder.cancel()
        }
        reset()
        MusicProviders.shared.current.failure = .permissionRequired
        let missing = DeckBuilder()
        missing.build(text: "Jazz", refinements: [])
        await until { if case .historyUnavailable = missing.phase { return true }; return false }
        if case .historyUnavailable = missing.phase { check("missing permission prompts a decision", true) }
        else { check("missing permission prompts a decision", false) }
        check("no model request before user's fallback decision", GeminiService.calls == 0)
        missing.build(text: "Jazz", refinements: [], useListeningHistory: false)
        await until { missing.tracks.count == 26 }
        check("explicit brief-only fallback builds", missing.phase == .ready)
        check("fallback is labelled honestly", missing.personalizationNote?.contains("Brief only") == true)
        check("fallback does not refetch history", MusicProviders.shared.current.historyCalls == 1)
        missing.cancel()

        reset()
        MusicProviders.shared.current.partial = true
        let partial = DeckBuilder()
        partial.build(text: "Jazz", refinements: [])
        await until { partial.tracks.count == 26 }
        check("partial-history status survives build", partial.personalizationNote?.contains("partial") == true)
        partial.cancel()

        reset()
        MusicProviders.shared.current.noAudioForKnown = true
        let preview = DeckBuilder()
        preview.build(text: "Jazz", refinements: [], mode: .personal)
        await until { preview.tracks.count >= 8 }
        check("unplayable personal picks use remaining brief candidates", preview.phase == .ready && preview.tracks.count >= 8)
        check("no silent cards introduced", preview.tracks.allSatisfy { $0.previewURL != nil })
        preview.cancel()

        reset()
        MusicProviders.shared.current.delay = 500_000_000
        let cancelled = DeckBuilder()
        cancelled.build(text: "Jazz", refinements: [])
        await until { MusicProviders.shared.current.historyCalls > 0 }
        cancelled.cancel()
        try? await Task.sleep(nanoseconds: 30_000_000)
        check("cancel during history fetch prevents model work", GeminiService.calls == 0 && cancelled.tracks.isEmpty)
        print("\(checks) integration checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
