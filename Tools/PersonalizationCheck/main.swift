import Foundation

var failures = 0
var checks = 0
func check(_ label: String, _ condition: Bool) {
    checks += 1
    print("\(condition ? "PASS" : "FAIL") \(label)")
    if !condition { failures += 1 }
}
func song(_ artist: String, _ title: String) -> TrackCandidate {
    TrackCandidate(artist: artist, title: title)
}
var history = ListeningHistory()
let familiar = (1...12).map { song("Known \($0)", "Unheard \($0)") }
let new = (1...12).map { song("New \($0)", "Discovery \($0)") }
for track in familiar { history.include(artist: track.artist, title: "Old favourite") }
let pool = familiar + new
for (mode, expected) in [(RecommendationMode.discovery, 2), (.balanced, 5), (.personal, 8)] {
    let selected = PersonalizedSelection.select(pool, history: history, mode: mode, limit: 10)
    check("\(mode) selects \(expected)/10 familiar artists from the same pool",
          selected.filter { history.artistKeys.contains($0.artist.primaryArtistKey) }.count == expected)
    check("\(mode) fills the requested count", selected.count == 10)
    check("\(mode) never injects out-of-brief history songs", Set(selected).isSubset(of: Set(pool)))
    check("\(mode) does not repeat songs", Set(selected.map(\.dedupeKey)).count == selected.count)
}
let empty = PersonalizedSelection.select(pool, history: ListeningHistory(), mode: .personal, limit: 8)
check("empty history preserves brief ordering", empty == Array(pool.prefix(8)))
check("zero limit is empty", PersonalizedSelection.select(pool, history: history, mode: .personal, limit: 0).isEmpty)
check("negative limit is empty", PersonalizedSelection.select(pool, history: history, mode: .balanced, limit: -1).isEmpty)
check("empty candidates remain empty", PersonalizedSelection.select([], history: history, mode: .personal, limit: 10).isEmpty)
check("unfamiliar-only pool does not pull unrelated favorites", PersonalizedSelection.select(new, history: history, mode: .personal, limit: 10).count == 10)
check("familiar-only pool remains usable for discovery", PersonalizedSelection.select(familiar, history: history, mode: .discovery, limit: 10).count == 10)
let duplicatePool = [song("Şanışer", "Susamam"), song("Saniser", "Susamam"), song("Ceza", "Suspus")]
check("Turkish normalization deduplicates", PersonalizedSelection.select(duplicatePool, history: history, mode: .balanced, limit: 10).count == 2)
var turkish = ListeningHistory()
turkish.include(artist: "Şanışer", title: "Susamam")
check("history recognizes Turkish spelling", turkish.knows(song("Saniser", "Susamam")))
let novelty = PersonalizedSelection.select([song("Şanışer", "Susamam"), song("Şanışer", "Other")], history: turkish, mode: .personal, limit: 1)
check("personal mode prefers unheard songs by familiar artist", novelty.first?.title == "Other")
var joker = ListeningHistory()
joker.include(artist: "Joker Bra")
check("near-miss artist names stay distinct", !joker.artistKeys.contains("Joker".primaryArtistKey))

do {
    let fixture = Data(#"{"items":[{"track":{"name":"Susamam","artists":[{"name":"Şanışer"},{"name":"Fuat"}]}},{"track":null}]}"#.utf8)
    let decoded = try JSONDecoder().decode(RecentListeningPage.self, from: fixture)
    var parsed = ListeningHistory()
    for item in decoded.items { item.track?.include(in: &parsed) }
    check("recent listening ignores null tracks", parsed.trackKeys.count == 2)
    check("collaborating artists are recognized", parsed.artistKeys.contains("fuat"))
    let top = try JSONDecoder().decode(ListeningTrackPage.self, from: Data(#"{"items":[{"name":"Song","artists":[{"name":"Artist"}]}]}"#.utf8))
    check("top track decoder needs no preview or deprecated fields", top.items.count == 1)
    let artists = try JSONDecoder().decode(ListeningArtistPage.self, from: Data(#"{"items":[{"name":"Artist"}]}"#.utf8))
    check("top artist decoder needs no genres or popularity", artists.items.count == 1)
} catch { check("history fixtures decode", false) }

let complete = try await ListeningHistoryLoader.load { _ in history }
check("all successful sources are complete", !complete.isPartial)
check("repeated sources are deduplicated", complete.history.trackKeys.count == history.trackKeys.count)
let partial = try await ListeningHistoryLoader.load { source in
    if source == .recentTracks { throw URLError(.timedOut) }
    return history
}
check("one source failing is explicitly partial", partial.isPartial && !partial.history.isEmpty)
do {
    _ = try await ListeningHistoryLoader.load { _ in throw URLError(.notConnectedToInternet) }
    check("total failure must not be treated as empty history", false)
} catch ListeningHistoryError.unavailable { check("total failure reported", true) }
do {
    _ = try await ListeningHistoryLoader.load { _ in ListeningHistory() }
    check("empty account must not claim personalization", false)
} catch ListeningHistoryError.empty { check("empty account reported", true) }
do {
    _ = try await ListeningHistoryLoader.load { _ in throw CancellationError() }
    check("cancellation must not become fallback", false)
} catch is CancellationError { check("cancellation propagates", true) }
print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
