import Foundation

/// Deezer preview lookup, ported from the earlier Swipelist.
///
/// Third in the preview chain after Spotify and iTunes. Spotify omits `preview_url`
/// for much of its catalogue, and iTunes' coverage thins out badly outside
/// English-language music — which is exactly where the decks were losing songs.
/// Deezer needs no API key.
enum DeezerService {
    /// Finds 30-second preview audio, or nil rather than a wrong artist's track.
    static func previewURL(artist: String, title: String) async -> URL? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        var components = URLComponents(string: "https://api.deezer.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(cleanTitle) \(artist)"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)

            for result in decoded.data {
                guard let preview = result.preview, !preview.isEmpty,
                      let name = result.artist?.name else { continue }
                // Artist must be a whole component, so "Joker" never matches
                // "Joker Bra" — and the recording must be the same one, so a
                // remix or instrumental never plays under the original's card.
                let artistMatches = RecordingIdentity.matches(artist: name, title: result.title ?? "", wantedArtist: artist, wantedTitle: cleanTitle)
                guard artistMatches,
                      PreviewMatch.isSameRecording(candidate: result.title ?? "", wanted: cleanTitle)
                else { continue }
                return URL(string: preview)
            }
        } catch {
            return nil
        }
        return nil
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String? }
            let title: String?
            let preview: String?
            let artist: Artist?
        }
        let data: [Item]
    }
}
