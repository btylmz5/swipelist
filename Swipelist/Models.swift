import SwiftUI

// MARK: - Artwork

/// Stand-in album artwork: a radial gradient, matching the design's placeholder art.
struct Art: Hashable {
    struct Stop: Hashable {
        let color: Color
        let location: Double
    }

    let stops: [Stop]
    let center: UnitPoint

    init(_ pairs: [(UInt32, Double)], center: (Double, Double)) {
        stops = pairs.map { Stop(color: Color(hex: $0.0), location: $0.1) }
        self.center = UnitPoint(x: center.0 / 100, y: center.1 / 100)
    }

    /// Neutral placeholder shown while a remote track's artwork loads.
    static let remotePlaceholder = Art([(0x2E2E33, 0), (0x0B0B0D, 1)], center: (50, 40))

    var gradientStops: [Gradient.Stop] {
        stops.map { .init(color: $0.color, location: $0.location) }
    }
}

struct ArtworkView: View {
    let art: Art

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            Rectangle()
                .fill(RadialGradient(
                    stops: art.gradientStops,
                    center: art.center,
                    startRadius: 0,
                    endRadius: side * 0.75
                ))
        }
    }
}

/// Renders a track's artwork: the remote image when available, otherwise the
/// placeholder/mock gradient.
struct TrackArtView: View {
    let track: Track

    var body: some View {
        // Color.clear takes the size the parent offers; the image rides along as an
        // overlay so its intrinsic size never drives layout.
        Color.clear.overlay {
            if let url = track.artworkURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ArtworkView(art: track.art)
                    }
                }
            } else {
                ArtworkView(art: track.art)
            }
        }
        .clipped()
    }
}

// MARK: - Track

struct Track: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let meta: String
    let art: Art
    var artworkURL: URL?
    var previewURL: URL?
    /// Set for Spotify-sourced tracks; needed to write the finished playlist back.
    var spotifyURI: String?
    /// The lead artist's Spotify id, kept so a catalogue lookup for "more by this
    /// artist" targets the act already on the deck rather than re-resolving the
    /// name — several artists can share one name exactly.
    var spotifyArtistID: String?

    /// Maps a Spotify search result onto the deck's model.
    init(spotify: SpotifyTrack) {
        let year = spotify.album.release_date.map { String($0.prefix(4)) }
        let meta = [spotify.album.name, year].compactMap { $0 }.joined(separator: " · ")
        self.title = spotify.name
        self.artist = spotify.artists.first?.name ?? "Unknown Artist"
        self.meta = meta.isEmpty ? "Single" : meta
        self.art = .remotePlaceholder
        // Spotify serves several sizes largest-first; the first is ~640px.
        self.artworkURL = spotify.album.images?.first.flatMap { URL(string: $0.url) }
        self.previewURL = spotify.preview_url.flatMap { URL(string: $0) }
        self.spotifyURI = spotify.uri
        self.spotifyArtistID = spotify.artists.first?.id
    }

    init(title: String, artist: String, meta: String, art: Art,
         artworkURL: URL? = nil, previewURL: URL? = nil, spotifyURI: String? = nil,
         spotifyArtistID: String? = nil) {
        self.title = title
        self.artist = artist
        self.meta = meta
        self.art = art
        self.artworkURL = artworkURL
        self.previewURL = previewURL
        self.spotifyURI = spotifyURI
        self.spotifyArtistID = spotifyArtistID
    }

    static let deckSamples: [Track] = [
        Track(title: "Midnight Resonance", artist: "Neon Syndicate", meta: "Echoes · 2024",
              art: Art([(0x86D92A, 0), (0x3E6B12, 0.16), (0x14210A, 0.48), (0x070B04, 1)], center: (50, 46))),
        Track(title: "Glass Corridor", artist: "Vela Nine", meta: "Prism · 2023",
              art: Art([(0x6F9FE8, 0), (0x2B4D8F, 0.30), (0x101A30, 0.65), (0x07090F, 1)], center: (28, 22))),
        Track(title: "Static Bloom", artist: "Cassette Ghost", meta: "Rewind · 2022",
              art: Art([(0xD66FD0, 0), (0x6F2B7E, 0.30), (0x241031, 0.62), (0x0B060F, 1)], center: (68, 30))),
        Track(title: "Low Tide", artist: "Marrow", meta: "Saltwater · 2025",
              art: Art([(0x3FC9B8, 0), (0x1B5F5A, 0.32), (0x0C2321, 0.62), (0x050B0A, 1)], center: (40, 70))),
        Track(title: "Night Grid", artist: "Horizon Protocol", meta: "Night Grid Protocol · 2024",
              art: Art([(0xB06FF0, 0), (0x5230A0, 0.32), (0x1B1040, 0.64), (0x08061A, 1)], center: (50, 18))),
        Track(title: "Afterglow", artist: "Dead Languages", meta: "Embers · 2023",
              art: Art([(0xF0A952, 0), (0x96521C, 0.30), (0x2E1808, 0.62), (0x0D0703, 1)], center: (60, 55))),
    ]
}

// MARK: - Playlist

struct Playlist: Identifiable, Hashable {
    /// The Supabase row id once saved. A playlist made offline starts with a local
    /// UUID and adopts the server's id when the insert comes back.
    var id: String
    var name: String
    var tracks: [Track]
    /// Set once the playlist has been written to a music service.
    var exportedProvider: MusicProviderID?
    var externalID: String?

    var count: Int { tracks.count }

    init(
        id: String = UUID().uuidString,
        name: String,
        tracks: [Track],
        exportedProvider: MusicProviderID? = nil,
        externalID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.exportedProvider = exportedProvider
        self.externalID = externalID
    }

    /// Up to four tracks with distinct artwork, for the library tile. Songs from the
    /// same album share a cover, so de-duplicating keeps the mosaic from looking like
    /// one image repeated four times.
    var covers: [Track] {
        var seen = Set<String>()
        var picked: [Track] = []
        for track in tracks {
            let key = track.artworkURL?.absoluteString ?? "\(track.artist)|\(track.title)"
            guard seen.insert(key).inserted else { continue }
            picked.append(track)
            if picked.count == 4 { break }
        }
        return picked
    }

    /// Deep link to the playlist on the service it was exported to.
    var externalURL: URL? {
        guard let externalID, exportedProvider == .spotify else { return nil }
        return URL(string: "https://open.spotify.com/playlist/\(externalID)")
    }

}

/// A playlist's artwork: a 2×2 mosaic of song covers, or the single cover when the
/// playlist doesn't have four distinct ones yet.
struct PlaylistCoverView: View {
    let playlist: Playlist
    var cornerRadius: CGFloat = 16

    var body: some View {
        let covers = playlist.covers
        Group {
            if covers.count >= 4 {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        tile(covers[0])
                        tile(covers[1])
                    }
                    HStack(spacing: 2) {
                        tile(covers[2])
                        tile(covers[3])
                    }
                }
            } else if let first = covers.first {
                TrackArtView(track: first)
            } else {
                Color.swSurfaceCard
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel("Artwork for \(playlist.name)")
    }

    private func tile(_ track: Track) -> some View {
        TrackArtView(track: track)
            .aspectRatio(1, contentMode: .fit)
    }
}

/// One song in a list: artwork, title, artist.
struct TrackListRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 14) {
            TrackArtView(track: track)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Artwork for \(track.title) by \(track.artist)")

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.swTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.swTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Session

/// A deck session started from the brief screen.
struct DeckSession: Identifiable {
    let id = UUID()
    var brief: PlaylistBrief
    var initialAdded: [Track] = []
    var startAtReview = false
    var showCheckpointOnAppear = false
    /// Debug shortcuts and previews run on the mock deck instead of the live API.
    var useMockTracks = false
}

// MARK: - Formatting

enum Format {
    /// The design estimates ~215 seconds per track (24 songs · 1h 26m).
    static let secondsPerTrack = 215

    /// "1h 26m" / "43m"
    static func shortDuration(_ count: Int) -> String {
        let s = count * secondsPerTrack
        let h = s / 3600
        let m = Int((Double(s - h * 3600) / 60).rounded())
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// "1 hour 12 minutes" / "43 minutes"
    static func longDuration(_ count: Int) -> String {
        let s = count * secondsPerTrack
        let h = s / 3600
        let m = Int((Double(s - h * 3600) / 60).rounded())
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        let minutes = "\(m) minutes"
        return h > 0 ? "\(hours) \(minutes)" : minutes
    }

    private static let stopwords: Set<String> = [
        "a", "an", "the", "for", "of", "with", "and", "but", "or", "to", "in", "on",
        "my", "me", "some", "something", "like", "less", "more", "that", "so", "very",
    ]

    /// The listener's own title if they gave one, otherwise a name derived from
    /// the brief, e.g. "melancholic indie for a rainy commute…" → "Melancholic Indie".
    static func suggestedName(for brief: PlaylistBrief) -> String {
        let title = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }

        let words = brief.text
            .lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty && !stopwords.contains($0) }
            .prefix(2)
        if words.isEmpty {
            return brief.occasion.map { "\($0) Mix" } ?? "New Mix"
        }
        return words.map(\.capitalized).joined(separator: " ")
    }
}
