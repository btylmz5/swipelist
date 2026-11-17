import Foundation

/// Client for the iTunes Search API. Results are cached in memory per search
/// term, and requests are throttled to stay under the API's ~20 requests/minute
/// allowance.
actor ITunesService {
    static let shared = ITunesService()

    private var cache: [String: [Track]] = [:]
    private var requestTimes: [Date] = []
    /// Keep optional preview lookups within Apple's documented allowance.
    private let requestLimit = 20
    private let requestWindow: TimeInterval = 60

    /// Finds 30-second preview audio for a track Spotify returned without one.
    ///
    /// Spotify now omits `preview_url` for a large share of its catalogue, so the
    /// earlier app fell back to iTunes for playback while still using Spotify for
    /// the song itself. Returns nil rather than a wrong artist's audio.
    func previewURL(artist: String, title: String) async -> URL? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let results = try? await searchSongs(matching: "\(cleanTitle) \(artist)", limit: 5, waitForCapacity: false) else {
            return nil
        }
        return results.first { track in
            RecordingIdentity.matches(artist: track.artist, title: track.title, wantedArtist: artist, wantedTitle: cleanTitle)
        }?.previewURL
    }

    func searchSongs(matching term: String, limit: Int = 25, waitForCapacity: Bool = true) async throws -> [Track] {
        let key = "\(limit)|\(term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        if let cached = cache[key] { return cached }

        // An optional preview must not hold up the deck for a minute: return
        // promptly so its caller can try Deezer. Cached hits still work above.
        requestTimes.removeAll { Date().timeIntervalSince($0) > requestWindow }
        if !waitForCapacity && requestTimes.count >= requestLimit {
            throw URLError(.resourceUnavailable)
        }
        try await waitForRequestSlot()

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: "DE"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let tracks = decoded.results.compactMap(Self.track(from:))
        cache[key] = tracks
        return tracks
    }

    /// Blocks until a request slot is free within the sliding rate-limit window.
    private func waitForRequestSlot() async throws {
        while true {
            let now = Date()
            requestTimes.removeAll { now.timeIntervalSince($0) > requestWindow }
            if requestTimes.count < requestLimit { break }
            let wait = requestWindow - now.timeIntervalSince(requestTimes[0]) + 0.1
            try await Task.sleep(nanoseconds: UInt64(max(wait, 0.1) * 1_000_000_000))
        }
        requestTimes.append(Date())
    }

    private static func track(from result: SearchResult) -> Track? {
        // Songs without a preview can't be swiped on meaningfully — skip them.
        guard let preview = result.previewUrl, let previewURL = URL(string: preview) else {
            return nil
        }
        let year = result.releaseDate.map { String($0.prefix(4)) }
        let meta = [result.collectionName, year].compactMap { $0 }.joined(separator: " · ")
        let artworkURL = result.artworkUrl100
            .map { $0.replacingOccurrences(of: "100x100", with: "600x600") }
            .flatMap(URL.init(string:))
        return Track(
            title: result.trackName ?? "Unknown Title",
            artist: result.artistName ?? "Unknown Artist",
            meta: meta.isEmpty ? "Single" : meta,
            art: .remotePlaceholder,
            artworkURL: artworkURL,
            previewURL: previewURL
        )
    }
}

private struct SearchResponse: Decodable {
    let results: [SearchResult]
}

private struct SearchResult: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let releaseDate: String?
    let previewUrl: String?
    let artworkUrl100: String?
}
