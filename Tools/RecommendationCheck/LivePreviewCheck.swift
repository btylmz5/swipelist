import Foundation

// UI-free harness using the production catalog matching and preview services.
struct Track: Sendable {
    enum Art: Sendable { case remotePlaceholder }
    let title: String; let artist: String; let meta: String; let art: Art
    let artworkURL: URL?; let previewURL: URL?
}
@main struct LivePreviewCheck {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass a saved RecommendationBatch JSON file") }
        let batch = try JSONDecoder().decode(RecommendationBatch.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var playable = 0, firstURL: URL?
        for song in batch.songs.prefix(60) {
            guard song.assessment.accepts(batch.constraints) else { continue }
            var url = await ITunesService.shared.previewURL(artist: song.artist, title: song.track)
            if url == nil { url = await DeezerService.previewURL(artist: song.artist, title: song.track) }
            if let url { playable += 1; if firstURL == nil { firstURL = url } }
        }
        print("Live exact-identity preview matches: \(playable)/\(batch.songs.count)")
        guard let firstURL, playable >= 8 else { throw URLError(.resourceUnavailable) }
        var request = URLRequest(url: firstURL); request.timeoutInterval = 15
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        guard [200,206].contains(http.statusCode), !data.isEmpty,
              http.mimeType?.hasPrefix("audio/") == true else { throw URLError(.badServerResponse) }
        print("PASS first preview audio is reachable; no audio sent to AI. This does not test Spotify resolution or human musical fit.")
    }
}
