import Foundation

/// A song the model named, known only by artist + title. Turning it into a
/// playable Track is ITunesService's job.
struct TrackCandidate: Hashable {
    let artist: String
    let title: String
    /// For swipe-history entries only: how many seconds of the preview played
    /// before the verdict. An instant skip and a skip at second 25 are different
    /// signals, and the model is told which one it was.
    var listenSeconds: Int?

    /// Key for deduplication across batches.
    var dedupeKey: String {
        "\(artist.folded)|\(title.folded)"
    }
}

// MARK: - Matching helpers

extension String {
    /// Lowercased, diacritic-stripped, punctuation-free form used for matching the
    /// model's spelling of a name against the iTunes catalogue's.
    ///
    /// Turkish dotless ı and dotted İ are separate letters rather than diacritic
    /// variants, so `.diacriticInsensitive` leaves them alone — they're mapped
    /// explicitly first, otherwise "Şanışer" folds to "sanıser" and never matches.
    var folded: String {
        replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Splits a credit into its individual artists: "VIZE, Joker Bra & Leony"
    /// becomes ["vize", "joker bra", "leony"].
    ///
    /// Matching against these parts separately is what stops a search for "Joker"
    /// from accepting "Joker Bra" — a substring check would let that through, and
    /// did, putting a German EDM track in a Turkish rap deck.
    var artistComponents: [String] {
        var parts = [self]
        for separator in [" & ", ",", " feat. ", " feat ", " ft. ", " ft ", " featuring ", " x ", " with ", " vs. ", " vs "] {
            parts = parts.flatMap {
                $0.components(separatedBy: separator.trimmingCharacters(in: .whitespaces) == ","
                    ? ","
                    : separator)
            }
        }
        return parts.map(\.folded).filter { !$0.isEmpty }
    }

    /// The lead artist, with collaborators dropped: "Murda & Ezhel" reduces to
    /// "murda". Used to spread the deck so two cards by the same lead artist don't
    /// land next to each other.
    var primaryArtistKey: String {
        artistComponents.first ?? folded
    }
}

// MARK: - Sequence helper

extension Sequence {
    /// Removes duplicates by a derived key, preserving order.
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}

// MARK: - Preview matching

/// Decides whether a fallback catalogue's track is really the song we asked for.
///
/// Preview audio comes from iTunes or Deezer when Spotify has none, and those
/// searches are loose: asking for "SICKO MODE" by Travis Scott returns
/// "SICKO MODE (Eater Remix) [Mixed]", "Mask Off" returns a remix, "Trance"
/// returns the instrumental. Each is credited to the right artist and has a
/// similar title, but the audio is not the song on the card.
enum PreviewMatch {
    /// Markers that mean the recording differs from the original.
    private static let variantMarkers = [
        "remix", "instrumental", "chopped", "screwed", "sped up", "slowed",
        "live", "karaoke", "cover version", "tribute", "mixed", "acoustic",
        "radio edit", "reprise", "demo", "a cappella", "acapella",
    ]

    /// True when `candidate` is the same recording as `wanted`.
    static func isSameRecording(candidate: String, wanted: String) -> Bool {
        let candidateKey = candidate.folded
        let wantedKey = wanted.folded
        guard !candidateKey.isEmpty, !wantedKey.isEmpty else { return false }

        // A marker is only disqualifying if the requested title didn't ask for it —
        // someone searching for a track actually titled "… (Live)" should get it.
        let wantedIsVariant = variantMarkers.contains { wantedKey.contains($0) }
        if !wantedIsVariant, variantMarkers.contains(where: { candidateKey.contains($0) }) {
            return false
        }

        // Otherwise the titles must genuinely correspond, not merely share a prefix
        // with extra material appended.
        if candidateKey == wantedKey { return true }
        let longer = candidateKey.count >= wantedKey.count ? candidateKey : wantedKey
        let shorter = candidateKey.count >= wantedKey.count ? wantedKey : candidateKey
        // Allow "(feat. X)" style suffixes, but not a wholly different title.
        return longer.hasPrefix(shorter) && longer.count - shorter.count <= 24
    }
}
