import Foundation

/// Reads and writes the account's data through PostgREST.
///
/// Every request carries the signed-in user's JWT, so row level security decides
/// what's visible — the app never filters by user id itself, and a bug here can't
/// leak another account's rows.
@MainActor
final class SupabaseRepository {
    static let shared = SupabaseRepository()

    private let auth = SupabaseAuth.shared
    private init() {}

    var isAvailable: Bool { Supabase.isConfigured && auth.isSignedIn }

    func resetPreferenceFeedback() async throws {
        guard let userID = auth.userID else { throw Supabase.SupabaseError.notSignedIn }
        _ = try await request("sw2_feedback", method: "DELETE", query: [URLQueryItem(name: "user_id", value: "eq." + userID)], body: nil, prefer: nil)
    }
    func loadPreferenceFeedback() async throws -> [PreferenceStore.Feedback] {
        try await get("sw2_feedback", query: [URLQueryItem(name:"select",value:"candidate_id,brief,verdict"), URLQueryItem(name:"order",value:"created_at.desc"), URLQueryItem(name:"limit",value:"500")])
    }
    func loadPreferences() async throws -> PreferenceProfile? {
        struct Row: Decodable { let profile: PreferenceProfile }
        let rows: [Row] = try await get("sw2_preferences", query: [URLQueryItem(name: "select", value: "profile")])
        return rows.first?.profile
    }
    func savePreferences(_ profile: PreferenceProfile) async throws {
        guard let userID = auth.userID, profile.isEligible else { throw Supabase.SupabaseError.notSignedIn }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
        let _: [Empty] = try await post("sw2_preferences", bodyArray: [["user_id": userID, "profile": object]], returning: false, prefer: "resolution=merge-duplicates")
    }
    func savePreferenceFeedback(candidateID: String, brief: String, verdict: String) async throws {
        guard let userID = auth.userID else { throw Supabase.SupabaseError.notSignedIn }
        let _: [Empty] = try await post("sw2_feedback", body: ["user_id": userID, "candidate_id": candidateID, "brief": brief, "verdict": verdict], returning: false)
    }

    // MARK: - Playlists

    func loadPlaylists() async throws -> [Playlist] {
        let columns = "id,name,created_at,exported_provider,external_playlist_id,"
            + "playlist_tracks(position,title,artist,album,artwork_url,preview_url,provider_uri)"
        let rows: [PlaylistRow] = try await get(
            "playlists",
            query: [URLQueryItem(name: "select", value: columns),
                    URLQueryItem(name: "order", value: "created_at.desc")]
        )
        return rows.map(\.playlist)
    }

    /// Saves a finished playlist and its tracks.
    @discardableResult
    func savePlaylist(
        name: String,
        brief: PlaylistBrief,
        tracks: [Track],
        exportedProvider: MusicProviderID? = nil,
        externalID: String? = nil
    ) async throws -> String {
        // `playlists.user_id` is NOT NULL with no default — the row has to name its
        // owner, and RLS then checks it matches the JWT.
        guard let userID = auth.userID else { throw Supabase.SupabaseError.notSignedIn }
        let inserted: [InsertedID] = try await post("playlists", body: [
            "user_id": userID,
            "name": name,
            "brief_text": brief.text,
            "brief_energy": brief.energy as Any,
            "brief_occasion": brief.occasion as Any,
            "exported_provider": exportedProvider?.rawValue as Any,
            "external_playlist_id": externalID as Any,
        ], returning: true)
        guard let playlistID = inserted.first?.id else { throw Supabase.SupabaseError.invalidResponse }

        let rows: [[String: Any]] = tracks.enumerated().map { index, track in
            [
                "playlist_id": playlistID,
                "position": index,
                "title": track.title,
                "artist": track.artist,
                "album": track.meta,
                "artwork_url": track.artworkURL?.absoluteString as Any,
                "preview_url": track.previewURL?.absoluteString as Any,
                "provider": MusicProviders.shared.active.rawValue,
                "provider_uri": track.spotifyURI as Any,
            ]
        }
        if !rows.isEmpty {
            let _: [Empty] = try await post("playlist_tracks", bodyArray: rows, returning: false)
        }
        return playlistID
    }

    // MARK: - Taste

    /// Kept/skipped counts per artist, accumulated across every session.
    func loadTaste() async throws -> (kept: [TrackCandidate], skipped: [TrackCandidate]) {
        let rows: [TasteRow] = try await get("taste_artists", query: [
            URLQueryItem(name: "select", value: "artist_name,kept_count,skipped_count"),
            URLQueryItem(name: "order", value: "updated_at.desc"),
            URLQueryItem(name: "limit", value: "40"),
        ])
        var kept: [TrackCandidate] = []
        var skipped: [TrackCandidate] = []
        for row in rows {
            // Represented as repeated candidates so the existing ranking logic,
            // which counts occurrences, works unchanged.
            kept += Array(repeating: TrackCandidate(artist: row.artist_name, title: ""), count: min(row.kept_count, 5))
            skipped += Array(repeating: TrackCandidate(artist: row.artist_name, title: ""), count: min(row.skipped_count, 5))
        }
        return (kept, skipped)
    }

    /// Increments the counters for one swipe. Uses a Postgres function so the
    /// read-modify-write happens server-side and concurrent swipes can't clobber
    /// each other.
    func recordTaste(artist: String, kept: Bool) async {
        let _: [Empty]? = try? await rpc("bump_taste", body: [
            "p_artist_key": artist.primaryArtistKey,
            "p_artist_name": artist,
            "p_kept": kept,
        ])
    }

    // MARK: - Shown tracks

    func loadShownTrackKeys() async throws -> Set<String> {
        let rows: [ShownRow] = try await get("shown_tracks", query: [
            URLQueryItem(name: "select", value: "track_key"),
            URLQueryItem(name: "order", value: "shown_at.desc"),
            URLQueryItem(name: "limit", value: "2000"),
        ])
        return Set(rows.map(\.track_key))
    }

    func markShown(_ tracks: [Track]) async {
        guard !tracks.isEmpty else { return }
        let rows = tracks.map { ["track_key": "\($0.artist.folded)|\($0.title.folded)"] }
        // Duplicates are expected; ignore them rather than failing the batch.
        let _: [Empty]? = try? await post("shown_tracks", bodyArray: rows, returning: false,
                                          prefer: "resolution=ignore-duplicates")
    }

    // MARK: - Transport

    private func request(
        _ path: String, method: String, query: [URLQueryItem], body: Data?, prefer: String?
    ) async throws -> Data {
        guard Supabase.isConfigured else { throw Supabase.SupabaseError.notConfigured }
        let token = try await auth.validAccessToken()

        var components = URLComponents(string: "\(Supabase.baseURL)/rest/v1/\(path)")!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw Supabase.SupabaseError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Supabase.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Supabase.SupabaseError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw Supabase.SupabaseError.http(status: http.statusCode, message: message ?? "")
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let data = try await request(path, method: "GET", query: query, body: nil, prefer: nil)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Supabase.SupabaseError.decoding(underlying: error) }
    }

    @discardableResult
    private func post<T: Decodable>(
        _ path: String, body: [String: Any], returning: Bool
    ) async throws -> [T] {
        try await post(path, bodyArray: [body], returning: returning)
    }

    @discardableResult
    private func post<T: Decodable>(
        _ path: String, bodyArray: [[String: Any]], returning: Bool, prefer: String? = nil
    ) async throws -> [T] {
        let cleaned = bodyArray.map { $0.compactMapValues { $0 is NSNull ? nil : $0 } }
        let data = try JSONSerialization.data(withJSONObject: cleaned)
        let header = [returning ? "return=representation" : "return=minimal", prefer]
            .compactMap { $0 }.joined(separator: ",")
        let result = try await request(path, method: "POST", query: [], body: data, prefer: header)
        guard returning else { return [] }
        do { return try JSONDecoder().decode([T].self, from: result) }
        catch { throw Supabase.SupabaseError.decoding(underlying: error) }
    }

    @discardableResult
    private func rpc<T: Decodable>(_ name: String, body: [String: Any]) async throws -> [T] {
        let data = try JSONSerialization.data(withJSONObject: body)
        let result = try await request("rpc/\(name)", method: "POST", query: [], body: data, prefer: nil)
        return (try? JSONDecoder().decode([T].self, from: result)) ?? []
    }
}

// MARK: - Row types

private struct Empty: Decodable {}
private struct InsertedID: Decodable { let id: String }
private struct TasteRow: Decodable { let artist_name: String; let kept_count: Int; let skipped_count: Int }
private struct ShownRow: Decodable { let track_key: String }

private struct PlaylistRow: Decodable {
    struct TrackRow: Decodable {
        let position: Int
        let title: String
        let artist: String
        let album: String?
        let artwork_url: String?
        let preview_url: String?
        let provider_uri: String?
    }
    let id: String
    let name: String
    let exported_provider: String?
    let external_playlist_id: String?
    let playlist_tracks: [TrackRow]?

    var playlist: Playlist {
        // PostgREST returns the embedded rows unordered; `position` is the order
        // the listener swiped them into.
        let tracks = (playlist_tracks ?? [])
            .sorted { $0.position < $1.position }
            .map { row in
                Track(
                    title: row.title,
                    artist: row.artist,
                    meta: row.album ?? "",
                    art: .remotePlaceholder,
                    artworkURL: row.artwork_url.flatMap(URL.init(string:)),
                    previewURL: row.preview_url.flatMap(URL.init(string:)),
                    spotifyURI: row.provider_uri
                )
            }
        return Playlist(
            id: id,
            name: name,
            tracks: tracks,
            exportedProvider: exported_provider.flatMap(MusicProviderID.init(rawValue:)),
            externalID: external_playlist_id
        )
    }
}
