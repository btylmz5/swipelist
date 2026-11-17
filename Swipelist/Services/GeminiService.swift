import Foundation

/// Song suggestions from Gemini Flash Lite.
///
/// Ported from the earlier Swipelist, prompt included, because that combination —
/// these instructions plus Spotify's forgiving search — is what produced its decks.
enum GeminiService {
    /// Google retires these faster than an app ships. The earlier Swipelist pinned
    /// "gemini-2.0-flash-lite", which now 404s with "no longer available", and
    /// "gemini-2.5-flash-lite" answers "no longer available to new users" for this
    /// key. So try current models in order and keep the first that answers.
    private static let modelCandidates = [
        "gemini-3-flash-preview",
        "gemini-flash-latest",
        "gemini-2.5-flash",
        "gemini-2.0-flash",
        "gemini-2.5-flash-lite",
    ]
    private nonisolated(unsafe) static var workingModel: String?

    private static func endpoint(for model: String) -> URL? {
        guard !Secrets.geminiAPIKey.isEmpty else { return nil }
        return URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(Secrets.geminiAPIKey)")
    }

    // The earlier app's system instruction, kept verbatim. "Available on Spotify"
    // is now literally true again, since Spotify resolves the deck.
    private static func systemInstruction(count: Int) -> String {
        """
        You are a music curator AI. Your ONLY job is to suggest real, existing songs that match exactly what the user describes.

        CRITICAL RULES — you MUST follow these without exception:
        1. You MUST respect the genre, language, and style the user specifies. If they say "Turkish hip-hop", ALL suggestions must be Turkish hip-hop songs. Never substitute a different genre.
        2. If the user mentions an artist name as a reference (e.g. "Motive type"), treat that artist as a style guide and suggest songs from that artist OR artists with a very similar style.
        3. If a specific language is implied (e.g. "Turkish", "Spanish", "French"), the songs MUST be in that language unless the user said otherwise.
        4. You MUST return exactly \(count) suggestions.
        5. Return ONLY a raw JSON array — no markdown, no explanation, no code fences.
        6. Format: [{"artist": "Artist Name", "track": "Track Name"}, ...]
        7. All suggested songs must be real and available on Spotify.
        8. Do NOT repeat the same artist more than 2 times — WITH ONE EXCEPTION: any \
        artist the listener named in their request may appear up to 5 times. If they \
        ask for "Travis Scott type songs" they want a good number of actual Travis \
        Scott songs, alongside similar artists. If they name several artists, spread \
        that allowance across all of them.
        9. CRITICAL: Provide ONLY the pure track name and pure primary artist name. Do NOT include "(feat...)", "(Remastered...)", or "- Live" in the track name.
        10. BREADTH IS CRITICAL. Use at least \(max(8, count * 2 / 3)) DIFFERENT artists. Do not fill the list with the four or five most obvious names in the genre — that makes the result feel repetitive. Mix the well-known artists with genuinely lesser-known ones from the same scene, and include deeper album cuts, not only the biggest singles.
        """
    }

    /// Asks Gemini for songs matching the brief, steered by recent swipes.
    static func suggestSongs(
        text: String,
        refinements: [String] = [],
        count: Int = 15,
        liked: [TrackCandidate] = [],
        skipped: [TrackCandidate] = [],
        excludeArtists: [String] = []
    ) async throws -> [TrackCandidate] {
        guard !Secrets.geminiAPIKey.isEmpty else { throw SuggestionError.missingAPIKey }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SuggestionError.emptyInput }

        var userMessage = """
        USER VIBE REQUEST: "\(trimmed)"

        Analyze this request carefully:
        - What genre did they specify? Stick strictly to that genre.
        - What language/region did they imply? Only suggest songs from that region/language.
        - What energy level? (hype, chill, sad, aggressive, etc.)
        - Did they name an artist as a style reference? Include that artist's songs and very similar artists.

        """
        if !refinements.isEmpty {
            let list = refinements.map { "- \($0)" }.joined(separator: "\n")
            userMessage += "\nThe user also pinned these down — every one of them applies:\n\(list)\n"
        }

        if !liked.isEmpty {
            let list = liked.map { "• \($0.artist) - \($0.title)" }.joined(separator: "\n")
            userMessage += "\n\nSongs the user LIKED — suggest MORE like these (same genre, energy, vibe):\n\(list)\n"
        }
        if !skipped.isEmpty {
            // The timing is the strength of the signal: a bail within seconds is a
            // rejection of the sound itself, a skip near the end was a near-miss.
            let list = skipped.map { entry -> String in
                let line = "• \(entry.artist) - \(entry.title)"
                guard let s = entry.listenSeconds else { return line }
                return line + " (skipped after \(s)s)"
            }.joined(separator: "\n")
            userMessage += "\n\nSongs the user SKIPPED — do NOT suggest anything in this style:\n\(list)\n" +
                "Skip timing matters: a skip in the first few seconds strongly rejects that sound; " +
                "a skip after 20s+ was a near-miss, so its style is not entirely wrong.\n"
        }

        // A bare list of titles buries the pattern. Naming the artists the listener
        // keeps and rejects, with counts, makes the signal explicit — and an artist
        // kept repeatedly is a much stronger steer than any single song.
        let keptArtists = Self.rank(liked)
        let skippedArtists = Self.rank(skipped).filter { entry in
            !keptArtists.contains { $0.name == entry.name }
        }
        if !keptArtists.isEmpty || !skippedArtists.isEmpty {
            userMessage += "\n\nTASTE SO FAR — personalize within the original genre, language, mood and era constraints; never override those constraints:"
            if !keptArtists.isEmpty {
                let summary = keptArtists.map { "\($0.name) (kept \($0.count))" }.joined(separator: ", ")
                userMessage += "\n• KEEPING: \(summary). Lean into these artists and ones that genuinely sound like them."
            }
            if !skippedArtists.isEmpty {
                let summary = skippedArtists.map { "\($0.name) (skipped \($0.count))" }.joined(separator: ", ")
                userMessage += "\n• REJECTING: \(summary). Do not suggest these artists again, and avoid that sound."
            }
        }
        if !excludeArtists.isEmpty {
            // Without this a refill happily returns the same obvious names again,
            // which is what makes a growing deck feel like five artists on loop.
            let list = excludeArtists.prefix(40).joined(separator: ", ")
            userMessage += "\n\nARTISTS ALREADY IN THE DECK — do NOT suggest any of these again. " +
                "Find different artists in the same style:\n\(list)"
        }
        userMessage += "\n\nNow return exactly \(count) song suggestions as a raw JSON array."

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction(count: count)]]],
            "contents": [["parts": [["text": userMessage]]]],
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: body)
        // A model that worked once is reused; otherwise walk the candidate list.
        let models = workingModel.map { [$0] } ?? modelCandidates
        var lastError: Error = SuggestionError.transport
        var success: Data?

        for model in models {
            guard let url = endpoint(for: model) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payloadData
            request.timeoutInterval = 30

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw SuggestionError.transport }
                if (200...299).contains(http.statusCode) {
                    if workingModel != model {
                        NSLog("SWGEMINI using model %@", model)
                        workingModel = model
                    }
                    success = data
                    break
                }
                let text = String(decoding: data, as: UTF8.self)
                NSLog("SWGEMINI %@ -> HTTP %d %@", model, http.statusCode, String(text.prefix(160)))
                lastError = SuggestionError.http(status: http.statusCode, body: text)
            } catch {
                lastError = error
            }
        }

        guard let data = success else { throw lastError }
        let envelope = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = envelope.candidates?
            .first?.content?.parts?
            .compactMap(\.text).joined() ?? ""
        guard !text.isEmpty else { throw SuggestionError.emptyResponse }
        return try decodeSuggestions(from: text)
    }

    /// Groups candidates by lead artist, most-swiped first.
    private static func rank(_ candidates: [TrackCandidate]) -> [(name: String, count: Int)] {
        var counts: [String: (name: String, count: Int)] = [:]
        for candidate in candidates {
            let key = candidate.artist.primaryArtistKey
            counts[key] = (counts[key]?.name ?? candidate.artist, (counts[key]?.count ?? 0) + 1)
        }
        return counts.values.sorted { $0.count > $1.count }.map { ($0.name, $0.count) }
    }

    /// Decodes the returned array, tolerating fences and surrounding prose.
    static func decodeSuggestions(from raw: String) throws -> [TrackCandidate] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end else {
            throw SuggestionError.noJSONFound
        }
        text = String(text[start...end])

        let payload = try JSONDecoder().decode([Suggestion].self, from: Data(text.utf8))
        let songs = payload.compactMap { item -> TrackCandidate? in
            guard let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let track = item.track?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !artist.isEmpty, !track.isEmpty else { return nil }
            return TrackCandidate(artist: artist, title: track)
        }
        .uniqued(by: \.dedupeKey)

        guard !songs.isEmpty else { throw SuggestionError.emptyResponse }
        return songs
    }

    enum SuggestionError: Error {
        case missingAPIKey
        case emptyInput
        case transport
        case http(status: Int, body: String)
        case emptyResponse
        case noJSONFound
    }
}

// MARK: - Wire types

private struct Suggestion: Decodable {
    let artist: String?
    let track: String?
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}
