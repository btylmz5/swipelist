import Foundation

/// Remembers which songs the listener has already judged, across app launches.
///
/// Without this every deck starts amnesiac: rebuild a similar brief next week and
/// the same songs come back to be swiped again. The store closes that loop —
/// songs skipped before are excluded from future decks, so each deck spends its
/// cards on music the listener hasn't ruled on yet.
///
/// Only *skips* are excluded. A song they kept is a song they like, and it may
/// belong in the next playlist too — excluding it would punish them for their own
/// taste. Skips also expire: a rejection in one context ("too chill for my gym
/// deck") shouldn't ban a song forever, so old entries age out.
///
/// Likes are recorded too, not for exclusion but so the data exists the day a
/// cross-deck taste profile wants it.
@MainActor
final class SwipeHistory {
    static let shared = SwipeHistory()

    private struct Entry: Codable {
        let key: String
        let liked: Bool
        let date: Date
    }

    /// A skip only counts against future decks for this long.
    private let skipLifetime: TimeInterval = 180 * 24 * 3600
    /// Rolling cap; oldest entries fall off. Generous enough for months of heavy
    /// swiping, small enough that the file stays trivial to load.
    private let maxEntries = 1200

    private var entries: [Entry]
    private let fileURL: URL

    /// Track keys (`artist|title`, folded) skipped recently enough to stay banned.
    var recentSkipKeys: Set<String> {
        let cutoff = Date().addingTimeInterval(-skipLifetime)
        return Set(entries.filter { !$0.liked && $0.date > cutoff }.map(\.key))
    }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("swipe-history.json")
        entries = (try? JSONDecoder().decode(
            [Entry].self, from: Data(contentsOf: fileURL)
        )) ?? []
    }

    /// Records a judgment. The newest verdict on a song wins — re-judging a track
    /// (it can resurface once a skip expires) replaces the old entry.
    func record(key: String, liked: Bool) {
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, liked: liked, date: Date()))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
