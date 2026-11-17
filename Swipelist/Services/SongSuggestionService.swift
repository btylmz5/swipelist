import Foundation

/// The app's Claude route in both Debug and Release. Only the Supabase session
/// token crosses this boundary; the Anthropic key exists on the server.
@MainActor
enum SongSuggestionService {
    static func suggestSongs(
        text: String, refinements: [String] = [], count: Int = 26,
        liked: [TrackCandidate] = [], skipped: [TrackCandidate] = [],
        excludeArtists: [String] = []
    ) async throws -> [TrackCandidate] {
        guard Supabase.isConfigured else { throw Supabase.SupabaseError.notConfigured }
        let token = try await SupabaseAuth.shared.validAccessToken()
        return try await SongSuggestionClient(baseURL: Supabase.baseURL, anonKey: Supabase.anonKey)
            .suggestSongs(text: text, refinements: refinements, count: count,
                          liked: liked, skipped: skipped, excludeArtists: excludeArtists, accessToken: token)
    }
}

struct SongSuggestionClient {
    let baseURL: String
    let anonKey: String
    var session: URLSession = .shared

    func suggestSongs(text: String, refinements: [String] = [], count: Int = 26,
                      liked: [TrackCandidate] = [], skipped: [TrackCandidate] = [],
                      excludeArtists: [String] = [], accessToken: String) async throws -> [TrackCandidate] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SuggestionFailure.message("Describe the playlist you want first.") }
        guard let url = URL(string: baseURL + "/functions/v1/swipelist2-suggest-songs") else {
            throw SuggestionFailure.message("The suggestion service isn't configured.")
        }
        let payload = RequestBody(text: trimmed, count: count, refinements: refinements,
                                  liked: liked.suffix(10).map(Feedback.init),
                                  skipped: skipped.suffix(10).map(Feedback.init),
                                  excludeArtists: Array(excludeArtists.prefix(100)))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 65
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SuggestionFailure.message("Unexpected suggestion response.") }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw SuggestionFailure.message("Your Swipelist session expired. Please sign in again.") }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw SuggestionFailure.message(message ?? "Suggestions couldn't be loaded. Please try again.")
        }
        let body = try JSONDecoder().decode(ResponseBody.self, from: data)
        let songs = body.songs.compactMap { song -> TrackCandidate? in
            let artist = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = song.track.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty, !title.isEmpty else { return nil }
            return TrackCandidate(artist: artist, title: title)
        }.uniqued(by: \.dedupeKey)
        guard !songs.isEmpty else { throw SuggestionFailure.message("The model returned no usable songs. Please try a different brief.") }
        return songs
    }
    private struct Feedback: Encodable {
        let artist: String
        let track: String
        let listen_seconds: Int?
        init(_ song: TrackCandidate) { artist = song.artist; track = song.title; listen_seconds = song.listenSeconds }
    }
    private struct RequestBody: Encodable {
        let text: String; let count: Int; let refinements: [String]
        let liked: [Feedback]; let skipped: [Feedback]; let excludeArtists: [String]
    }
    private struct ResponseBody: Decodable {
        struct Song: Decodable { let artist: String; let track: String }
        let songs: [Song]
    }
    private struct ErrorBody: Decodable { let error: String }
    enum SuggestionFailure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}

extension SongSuggestionService {
    static func assessed(text: String, refinements: [String], profile: PreferenceProfile, count: Int = 60, mode: RecommendationMode = .balanced, context: RecommendationSession = RecommendationSession(), transport: URLSession = .shared) async throws -> RecommendationBatch {
        guard profile.isEligible else { throw SongSuggestionClient.SuggestionFailure.message("Unsupported preference source.") }
        let token = try await SupabaseAuth.shared.validAccessToken()
        var request = URLRequest(url: URL(string: Supabase.baseURL + "/functions/v1/swipelist2-suggest-songs")!)
        request.httpMethod = "POST"; request.timeoutInterval = 160
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Supabase.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Explicit allowlist: never encode the profile wholesale or a resolved Track.
        let preferences: [String: Any] = ["source":"user_explicit", "artists":profile.artists,
            "examples":profile.examples, "likes":profile.likes, "avoids":profile.avoids]
        let session = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context))
        request.httpBody = try JSONSerialization.data(withJSONObject: ["version":2,"text":text,"refinements":refinements,"count":count,"preferences":preferences,"mode":mode.rawValue,"session":session])
        let (data,response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 { throw SuggestionRateLimit(until: Date().addingTimeInterval(Double(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)) }
            throw SongSuggestionClient.SuggestionFailure.message(http.statusCode == 401 ? "Please sign in to Swipelist again." : "Quality checks couldn't complete. Your brief hasn't been relaxed. Please retry.")
        }
        let result = try JSONDecoder().decode(RecommendationBatch.self, from: data)
        guard result.version == 2 else { throw URLError(.cannotParseResponse) }
        return result
    }
}
