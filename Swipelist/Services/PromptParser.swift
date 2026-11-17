import Foundation

// MARK: - Parser

/// Turns the listener's free-text brief into a list of real songs by asking Claude.
///
/// Decoding is deliberately forgiving: the model is told to return a bare JSON
/// array, but fences, preamble and stray prose are all stripped before parsing.
enum PromptParser {
    /// Keep the existing raw-array response contract and defensive decoder.
    /// The pinned model is verified by the live PromptParserCheck harness.
    private static let model = "claude-sonnet-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Asks the model to name real songs outright.
    ///
    /// This is the primary path. Going via search terms and a tag database loses a
    /// lot: Last.fm has all of 2 tracks tagged "turkish hip hop", while the model
    /// can name fifteen real ones. Tag databases are crowd-sourced and skew
    /// English; the model already knows the catalogue.
    private static func suggestionSystemPrompt(count: Int) -> String {
        """
        You are a music curator. Suggest real, existing songs that match exactly what \
        the listener describes.

        RULES — follow these without exception:
        1. Respect the genre, language and style requested. If they say "Turkish \
        hip-hop", every suggestion must be Turkish hip-hop. Never substitute a \
        neighbouring genre because it is better known.
        2. If they name an artist as a reference ("Motive type beats"), treat it as a \
        style guide: include that artist and closely similar artists.
        2b. Do not favor recent releases or older hits by default. Respect an era only \
        when the listener explicitly requests one; the reference artist describes style.
        3. If a language or region is implied, the songs must be in that language.
        4. Return exactly \(count) suggestions.
        5. Do not repeat an artist more than 2 times, except an artist explicitly named \
        in the request may appear up to 5 times. Use at least \(max(8, count * 2 / 3)) \
        different artists where the brief permits; mix familiar names and lesser-known \
        artists, and include album tracks alongside singles.
        6. Give the pure track title and the pure primary artist only. No "(feat. …)", \
        "(Remastered)", "- Live", "Radio Edit" or other version suffixes — they break \
        catalogue lookups.
        7. Every song must be real and widely available on streaming services. Do not \
        invent titles.
        8. Return ONLY a raw JSON array. No markdown fences, no preamble, no commentary \
        — your entire response must be parseable by a JSON decoder.

        Format: [{"artist": "Artist Name", "track": "Track Name"}]
        """
    }

    // MARK: Public API — song suggestions

    /// Asks the model for concrete songs matching the brief.
    ///
    /// `liked` and `skipped` carry recent swipe history so refills steer toward what
    /// the listener is keeping and away from what they're rejecting.
    static func suggestSongs(
        text: String,
        refinements: [String] = [],
        count: Int = 15,
        liked: [TrackCandidate] = [],
        skipped: [TrackCandidate] = [],
        excludeArtists: [String] = []
    ) async throws -> [TrackCandidate] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.emptyInput }
        guard let apiKey, !apiKey.isEmpty else { throw ParseError.missingAPIKey }

        var message = """
        LISTENER'S REQUEST: "\(trimmed)"

        Work out from that request:
        - Which genre did they specify? Stay strictly inside it.
        - Which language or region is implied? Only suggest songs from it.
        - What energy level do they want?
        - Did they name an artist as a style reference? Include them and close matches.
        """
        if !refinements.isEmpty {
            let list = refinements.map { "- \($0)" }.joined(separator: "\n")
            message += "\n\nThey also pinned these down — every one of them applies:\n\(list)"
        }

        if !liked.isEmpty {
            let list = liked.map { "• \($0.artist) - \($0.title)" }.joined(separator: "\n")
            message += "\n\nSongs they KEPT — suggest more in this direction:\n\(list)"
        }
        if !skipped.isEmpty {
            // Same timing annotation as GeminiService, so a provider switch
            // doesn't quietly lose the signal.
            let list = skipped.map { entry -> String in
                let line = "• \(entry.artist) - \(entry.title)"
                guard let s = entry.listenSeconds else { return line }
                return line + " (skipped after \(s)s)"
            }.joined(separator: "\n")
            message += "\n\nSongs they SKIPPED — avoid this direction:\n\(list)" +
                "\nSkip timing matters: a skip in the first few seconds strongly rejects " +
                "that sound; a skip after 20s+ was a near-miss."
        }
        if !liked.isEmpty || !skipped.isEmpty {
            message += "\n\nDo not suggest any song already listed above."
        }
        if !excludeArtists.isEmpty {
            message += "\n\nAlready in the deck — do not suggest these artists again:\n" +
                excludeArtists.prefix(40).joined(separator: ", ")
        }
        message += "\n\nNow return exactly \(count) suggestions as a raw JSON array."

        let raw = try await complete(
            system: suggestionSystemPrompt(count: count),
            message: message,
            maxTokens: max(2048, count * 100),
            apiKey: apiKey
        )
        return try decodeSuggestions(from: raw)
    }

    /// Decodes the suggestion array, tolerating fences and surrounding prose.
    /// Exposed for tests.
    static func decodeSuggestions(from raw: String) throws -> [TrackCandidate] {
        guard let json = extractJSONArray(from: raw) else { throw ParseError.noJSONFound }
        let payload = try JSONDecoder().decode([SuggestionPayload].self, from: Data(json.utf8))

        let suggestions = payload.compactMap { item -> TrackCandidate? in
            guard let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let track = item.track?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !artist.isEmpty, !track.isEmpty else { return nil }
            return TrackCandidate(artist: artist, title: Self.stripVersionSuffixes(track))
        }
        .uniqued(by: \.dedupeKey)

        guard !suggestions.isEmpty else { throw ParseError.emptyBrief }
        return suggestions
    }

    /// Belt-and-braces for rule 6 — the model mostly complies, but a stray
    /// "(feat. X)" or "- Live" wrecks the catalogue lookup.
    static func stripVersionSuffixes(_ title: String) -> String {
        var cleaned = title
        let patterns = [
            #"\s*[\(\[][^\)\]]*(feat\.?|ft\.?|featuring|remaster|remastered|live|radio edit|single version|album version|explicit|deluxe|mono|stereo)[^\)\]]*[\)\]]"#,
            #"\s*-\s*(feat\.?|ft\.?|featuring|remaster|remastered|live|radio edit|single version|album version).*$"#,
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern, with: "", options: [.regularExpression, .caseInsensitive]
            )
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Request

    private static func complete(
        system: String,
        message: String,
        maxTokens: Int,
        apiKey: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            // Sonnet 5.5 uses between_tools for responses without upfront thinking.
            "thinking": ["type": "between_tools"],
            "output_config": ["effort": "low"],
            "messages": [["role": "user", "content": message]],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ParseError.transport }
        guard http.statusCode == 200 else {
            throw ParseError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        // A refusal returns HTTP 200 with no usable text — treat it as a parse failure
        // so the caller falls back to the chips.
        guard decoded.stopReason != "refusal" else { throw ParseError.refused }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else { throw ParseError.emptyResponse }
        return text
    }

    // MARK: Defensive decoding

    /// Strips ``` fences and any preamble, returning the outermost `[...]` span.
    private static func extractJSONArray(from raw: String) -> String? {
        extractJSON(from: raw, open: "[", close: "]")
    }

    private static func extractJSON(from raw: String, open: Character, close: Character) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            // Drop the opening fence line (```, ```json, …) and the closing fence.
            var lines = text.components(separatedBy: .newlines)
            lines.removeFirst()
            if let last = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) {
                lines.removeSubrange(last...)
            }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = text.firstIndex(of: open), let end = text.lastIndex(of: close), start < end else {
            return nil
        }
        return String(text[start...end])
    }

    // MARK: Credentials

    // TODO: This call MUST move server-side before TestFlight. An API key shipped in
    // an app binary is extractable by anyone who downloads it — route the request
    // through a backend that holds the key and forwards the response.
    private static var apiKey: String? {
        #if DEBUG
        return Secrets.anthropicAPIKey
        #else
        return nil
        #endif
    }

    // MARK: Errors

    enum ParseError: Error {
        case emptyInput
        case missingAPIKey
        case transport
        case http(status: Int, body: String)
        case refused
        case emptyResponse
        case noJSONFound
        case emptyBrief
    }
}

// MARK: - Wire types

private struct MessagesResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

private struct SuggestionPayload: Decodable {
    let artist: String?
    let track: String?
}

