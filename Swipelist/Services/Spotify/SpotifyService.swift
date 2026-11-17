import CryptoKit
import Foundation

/// Spotify client: PKCE auth, track search, playlist writes.
/// Ported from the earlier Swipelist, which resolved songs far more reliably than
/// the iTunes catalogue could.
final class SpotifyService: @unchecked Sendable {
    static let shared = SpotifyService()

    private let keychain = KeychainService.shared
    private let session = URLSession.shared
    private let decoder = JSONDecoder()
    private let requestBudget = SpotifyRequestBudget()

    var isAuthenticated: Bool { keychain.hasValidToken }
    private var accessToken: String? { keychain.load(.accessToken) }

    // MARK: - PKCE

    static func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64URLEncoded
    }

    static func generateCodeChallenge(from verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    func buildAuthorizationURL(codeChallenge: String, state: String, readAccess: Bool = false) -> URL? {
        guard !SpotifyConfig.clientID.isEmpty else { return nil }
        var components = URLComponents(string: SpotifyConfig.authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "scope", value: (SpotifyConfig.scopes + (readAccess ? SpotifyConfig.readScopes : [])).joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            // Always show consent, so a stale grant missing playlist scopes is re-granted.
            URLQueryItem(name: "show_dialog", value: "true"),
        ]
        return components?.url
    }

    // MARK: - Tokens

    func exchangeCode(_ code: String, codeVerifier: String) async throws {
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": codeVerifier,
        ])
    }

    @discardableResult
    func refreshAccessToken() async throws -> String {
        guard let refresh = keychain.load(.refreshToken) else { throw APIError.tokenRefreshFailed }
        return try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": SpotifyConfig.clientID,
        ])
    }

    @discardableResult
    private func requestToken(_ fields: [String: String]) async throws -> String {
        guard let url = URL(string: SpotifyConfig.tokenURL) else { throw APIError.invalidURL }
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            NSLog("SWSPOTIFY token request failed: HTTP %d — %@", http.statusCode, body)
            throw APIError.tokenExchangeFailed(status: http.statusCode, body: body)
        }
        let token = try decoder.decode(TokenResponse.self, from: data)
        keychain.store(token)
        // A token that can't be read back means the store failed — surface it here
        // rather than as a confusing "unauthorized" on the next request.
        guard keychain.load(.accessToken) != nil else {
            NSLog("SWSPOTIFY token stored but could not be read back")
            throw APIError.tokenRefreshFailed
        }
        return token.access_token
    }

    func logout() { keychain.clearAll() }

    // MARK: - Requests

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(path: path, method: "GET", query: query, body: nil)
    }

    @discardableResult
    private func send<T: Decodable>(
        path: String, method: String, query: [URLQueryItem] = [], body: Data?
    ) async throws -> T {
        guard var components = URLComponents(string: SpotifyConfig.apiBaseURL + path) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }
        guard var token = accessToken else { throw APIError.unauthorized }

        func perform(_ token: String) async throws -> (Data, HTTPURLResponse) {
            try await requestBudget.check()
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, http)
        }

        var (data, http) = try await perform(token)
        if http.statusCode == 401 {
            // Access tokens last an hour; refresh once and retry before giving up.
            token = try await refreshAccessToken()
            (data, http) = try await perform(token)
        }

        switch http.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            do { return try decoder.decode(T.self, from: data) }
            catch { throw APIError.decodingError(underlying: error) }
        case 401: throw APIError.unauthorized
        case 403:
            let detail = Self.message(from: data)
            NSLog("SWSPOTIFY 403 on %@ %@ — %@ | granted scopes: %@",
                  method, path, detail,
                  KeychainService.shared.load(.grantedScopes) ?? "NONE")
            throw APIError.spotifyRefused(detail)
        case 429:
            await requestBudget.block(seconds: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
            throw APIError.rateLimitExceeded
        default: throw APIError.serverError(statusCode: http.statusCode)
        }
    }

    /// Spotify puts the useful explanation in `error.message`.
    private static func message(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(decoding: data, as: UTF8.self).prefix(160).description
        }
        return message
    }

    // MARK: - User

    func currentUser() async throws -> SpotifyUser {
        try await get("/me")
    }

    // MARK: - Listening history

    /// Fetch fresh data for this deck only; no account data is cached on disk or
    /// sent to the suggestion model. Partial responses remain usable and visible.
    func legacyListeningHistory() async throws -> ListeningHistoryResult {
        guard keychain.hasListeningHistoryScopes else {
            throw ListeningHistoryError.permissionRequired
        }
        return try await ListeningHistoryLoader.load { source in
            var history = ListeningHistory()
            switch source {
            case .shortTermTracks, .mediumTermTracks:
                let page: ListeningTrackPage = try await self.get("/me/top/tracks", query: [
                    URLQueryItem(name: "time_range", value: source == .shortTermTracks ? "short_term" : "medium_term"),
                    URLQueryItem(name: "limit", value: "50")
                ])
                for track in page.items { track.include(in: &history) }
            case .topArtists:
                let page: ListeningArtistPage = try await self.get("/me/top/artists", query: [
                    URLQueryItem(name: "time_range", value: "medium_term"),
                    URLQueryItem(name: "limit", value: "50")
                ])
                for artist in page.items { history.include(artist: artist.name) }
            case .recentTracks:
                let page: RecentListeningPage = try await self.get("/me/player/recently-played", query: [
                    URLQueryItem(name: "limit", value: "50")
                ])
                for item in page.items { item.track?.include(in: &history) }
            }
            return history
        }
    }

    // MARK: - Search

    /// Finds the song the model named.
    ///
    /// This is the earlier app's cascade, and it is why its decks looked right:
    /// Spotify's search is forgiving enough that a misremembered title still lands
    /// on a real song by the right artist — a hallucinated title is rescued by the
    /// artist match, a reworded artist credit by the title match.
    ///
    /// What it no longer does is fall through to `results.first` when *neither*
    /// field matches. That result is just Spotify's popularity winner for a query
    /// that matched nothing asked for — the wrong song by the wrong artist, and
    /// being popularity-ranked it also skewed the deck old. Returning nil is
    /// honest: the caller's funnel counts it, refills replace it, and a named
    /// artist's slot gets refilled from their real catalogue instead.
    func searchTrack(artist: String, title: String) async throws -> Track? {
        let cleanTitle = clean(title)
        let cleanArtist = clean(artist)

        // 1. Strict field-scoped query.
        var results = try await searchTracks(query: "track:\"\(cleanTitle)\" artist:\"\(cleanArtist)\"")
        // 2. Broad query.
        if results.isEmpty {
            results = try await searchTracks(query: "\(cleanTitle) \(cleanArtist)")
        }
        // 3. Original strings, in case cleaning was too aggressive.
        if results.isEmpty {
            results = try await searchTracks(query: "\(title) \(artist)")
        }
        guard !results.isEmpty else { return nil }

        return results.first {
            RecordingIdentity.matches(artist: $0.artist, title: $0.title, wantedArtist: artist, wantedTitle: title)
        }
    }

    private func searchTracks(query: String, limit: Int = 10) async throws -> [Track] {
        let response: TrackSearchResponse = try await get("/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        return response.tracks.items.map(Track.init(spotify:))
    }

    // MARK: - Artist catalogue

    /// Songs from an artist's own albums and singles, drawn from the live
    /// catalogue rather than from anything a model remembers.
    ///
    /// This exists because the suggestion model's knowledge ends at its training
    /// cutoff: an album released after it can never be *named*, so it could never
    /// reach the deck. The catalogue has no such horizon — a release from
    /// yesterday and one from 2015 are the same kind of row here. Deliberately
    /// date-blind throughout: releases are sampled uniformly, never sorted or
    /// filtered by date, so new songs become exactly as eligible as old ones and
    /// no more. (Popularity ranking is avoided for the same reason — it
    /// accumulates with age, which would quietly re-bury new releases.)
    ///
    /// Requests are bounded to one release listing plus up to 20 album reads.
    /// Callers cache the resulting catalogue per deck.
    func artistCatalog(artistID: String, artistName: String) async throws -> [Track] {
        // Every release in one page; 50 covers all but career-spanning catalogues.
        let releases: AlbumListResponse = try await get("/artists/\(artistID)/albums", query: [
            URLQueryItem(name: "include_groups", value: "album,single"),
            URLQueryItem(name: "limit", value: "50"),
        ])
        // Deluxe and anniversary editions duplicate the base album's tracks under
        // a near-identical name; keep one of each.
        let distinct = releases.items.uniqued(by: { $0.name.folded })
        // Sample up to 20 releases, not most-recent-20,
        // to keep the pool date-blind for artists with more releases than that.
        let chosen = distinct.shuffled().prefix(20)
        guard !chosen.isEmpty else { return [] }

        // Development Mode no longer supports GET /albums?ids=.
        // Read sequentially to avoid a burst of concurrent catalogue requests.
        var albums: [AlbumsBatchResponse.Album] = []
        for release in chosen {
            try Task.checkCancellation()
            do {
                let album: AlbumsBatchResponse.Album = try await get("/albums/\(release.id)")
                albums.append(album)
            } catch APIError.serverError(let status) where status == 404 {
                continue
            }
        }

        let wantedArtist = artistName.folded
        var out: [Track] = []
        for album in albums {
            let year = album.release_date.map { String($0.prefix(4)) }
            let meta = [album.name, year].compactMap { $0 }.joined(separator: " · ")
            let artworkURL = album.images?.first.flatMap { URL(string: $0.url) }
            for item in album.tracks.items {
                // Only songs this artist leads — their albums can carry tracks
                // fronted by a guest, which belong to that artist's cap instead.
                guard let lead = item.artists.first, lead.name.folded == wantedArtist else { continue }
                out.append(Track(
                    title: item.name,
                    artist: lead.name,
                    meta: meta.isEmpty ? "Single" : meta,
                    art: .remotePlaceholder,
                    artworkURL: artworkURL,
                    previewURL: item.preview_url.flatMap { URL(string: $0) },
                    spotifyURI: item.uri,
                    spotifyArtistID: lead.id
                ))
            }
        }
        return out
    }

    /// Strips punctuation the search index handles badly.
    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Playlists

    /// Dev probe: exercises the whole export path against the live account.
    func probeFullExport() async {
        do {
            guard let track = try await searchTrack(artist: "Travis Scott", title: "SICKO MODE"),
                  let uri = track.spotifyURI else {
                NSLog("SWPROBE2 search failed"); return
            }
            NSLog("SWPROBE2 resolved %@ - %@", track.artist, track.title)

            let id = try await createPlaylist(name: "Swipelist probe", description: "delete me")
            NSLog("SWPROBE2 createPlaylist OK id=%@", id)

            try await addTracks(playlistID: id, uris: [uri])
            NSLog("SWPROBE2 addTracks OK — full export path works")
        } catch {
            NSLog("SWPROBE2 FAILED: %@", error.localizedDescription)
        }
    }

    /// Creates a private playlist on the signed-in account.
    ///
    /// Uses `/me/playlists`, not the `/users/{id}/playlists` form the docs lead with:
    /// probed side by side with the same token and scopes, the `/users/` variant
    /// returns 403 Forbidden while `/me/` succeeds. The earlier Swipelist used
    /// `/me/` too.
    func createPlaylist(name: String, description: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name, "description": description, "public": false,
        ])
        let playlist: SpotifyPlaylist = try await send(
            path: "/me/playlists", method: "POST", body: body
        )
        return playlist.id
    }

    /// Adds tracks to a playlist.
    ///
    /// Uses `/items`, not the `/tracks` path the docs describe. Probed against the
    /// live account with identical token and scopes: `/tracks` returns 403 Forbidden,
    /// `/items` succeeds. Same story as createPlaylist — the earlier Swipelist used
    /// both of these and was right on both counts.
    func addTracks(playlistID: String, uris: [String]) async throws {
        guard !uris.isEmpty else { return }
        // Spotify caps additions at 100 per request.
        for chunk in stride(from: 0, to: uris.count, by: 100).map({ Array(uris[$0..<min($0 + 100, uris.count)]) }) {
            let body = try JSONSerialization.data(withJSONObject: ["uris": chunk])
            let _: EmptyResponse = try await send(
                path: "/playlists/\(playlistID)/items", method: "POST", body: body
            )
        }
    }
}

// MARK: - Wire types

struct EmptyResponse: Decodable {}

struct SpotifyUser: Decodable {
    let id: String
    let display_name: String?
}

private struct SpotifyPlaylist: Decodable {
    let id: String
}

struct SpotifyPlaylistProbe: Decodable {
    let id: String
}

private struct TrackSearchResponse: Decodable {
    struct Items: Decodable { let items: [SpotifyTrack] }
    let tracks: Items
}

struct SpotifyTrack: Decodable {
    struct Artist: Decodable { let id: String?; let name: String }
    struct Album: Decodable {
        struct Image: Decodable { let url: String; let height: Int? }
        let name: String
        let images: [Image]?
        let release_date: String?
    }
    let id: String
    let name: String
    let artists: [Artist]
    let album: Album
    let preview_url: String?
    let uri: String
}

/// `/artists/{id}/albums` returns simplified albums: no tracklist.
private struct AlbumListResponse: Decodable {
    struct Item: Decodable { let id: String; let name: String }
    let items: [Item]
}

/// `/albums/{id}` returns a full album, whose tracks are *simplified* track
/// objects — no `album` field, so they can't reuse `Track.init(spotify:)` and
/// carry their artwork and release date down from the parent album instead.
private struct AlbumsBatchResponse: Decodable {
    struct Album: Decodable {
        struct TrackList: Decodable { let items: [Item] }
        struct Item: Decodable {
            let name: String
            let artists: [SpotifyTrack.Artist]
            let preview_url: String?
            let uri: String
        }
        let name: String
        let release_date: String?
        let images: [SpotifyTrack.Album.Image]?
        let tracks: TrackList
    }
    /// Spotify returns `null` entries for ids it can't serve; a strict `[Album]`
    /// would fail the whole decode over one of them.
    let albums: [Album?]
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}


/// Do not issue a retry storm while Spotify's Retry-After window is active.
private actor SpotifyRequestBudget {
    private var blockedUntil = Date.distantPast
    func check() throws { if Date() < blockedUntil { throw APIError.rateLimitExceeded } }
    func block(seconds: Double) { blockedUntil = max(blockedUntil, Date().addingTimeInterval(max(1, seconds))) }
}

struct SpotifyAccessResult: Identifiable, Sendable {
    let id = UUID()
    let source: String
    let detail: String
}

extension SpotifyService {
    /// Bounded read-only access diagnostic. Never feeds a model or taste profile.
    /// Only sample counts/status leave this method; payloads stay transient.
    func checkReadAccess() async -> [SpotifyAccessResult] {
        struct Page: Decodable {
            struct Item: Decodable {
                struct Owner: Decodable { let id: String? }
                let id: String?
                let owner: Owner?
                let collaborative: Bool?
            }
            let items: [Item?]
        }
        var checks: [(String,String,[URLQueryItem])] = []
        for range in ["short_term", "medium_term", "long_term"] {
            for kind in ["tracks", "artists"] {
                checks.append(("Top \(kind) · \(range)", "/me/top/\(kind)", [URLQueryItem(name:"time_range", value:range)]))
            }
        }
        checks += [("Recent listening", "/me/player/recently-played", []), ("Liked songs", "/me/tracks", []), ("Playlists", "/me/playlists", [])]
        var results: [SpotifyAccessResult] = []
        var playlists: [Page.Item] = []
        for (label,path,query) in checks {
            if Task.isCancelled { return results }
            do {
                let page: Page = try await get(path,query:query + [URLQueryItem(name:"limit",value:"10")])
                results.append(.init(source:label,detail:"Accessible · \(page.items.compactMap { $0 }.count) sample entries (up to 10)"))
                if path == "/me/playlists" { playlists = page.items.compactMap { $0 } }
            } catch {
                results.append(.init(source:label,detail:error.localizedDescription))
                if case APIError.rateLimitExceeded = error { break }
            }
        }
        if !Task.isCancelled {
            do {
                let user = try await currentUser()
                if let playlist = playlists.first(where: { $0.owner?.id == user.id || $0.collaborative == true }), let id = playlist.id {
                    let page: Page = try await get("/playlists/\(id)/items",query:[URLQueryItem(name:"limit",value:"10")])
                    results.append(.init(source:"Owned/shared playlist contents",detail:"Accessible · \(page.items.compactMap { $0 }.count) sample entries"))
                } else {
                    results.append(.init(source:"Owned/shared playlist contents",detail:"Not tested: none found in the first 10 playlists. This does not mean your library is empty."))
                }
            } catch { results.append(.init(source:"Playlist contents",detail:error.localizedDescription)) }
        }
        return results
    }
}

extension SpotifyService {
    /// Session-only experiment. No model calls, no database writes, no background sync.
    func listeningHistory() async throws -> ListeningHistoryResult {
        guard keychain.hasListeningHistoryScopes else { throw ListeningHistoryError.permissionRequired }
        struct Artist: Decodable { let name: String }
        struct Song: Decodable { let name: String; let artists: [Artist] }
        struct TopSongs: Decodable { let items: [Song] }
        struct TopArtists: Decodable { let items: [Artist] }
        struct Wrapped: Decodable {
            struct Entry: Decodable {
                struct Context: Decodable { let uri: String? }
                let track: Song?; let item: Song?; let played_at: String?; let context: Context?
            }
            let items: [Entry?]
        }
        struct Lists: Decodable {
            struct Entry: Decodable {
                struct Owner: Decodable { let id: String }
                let id: String; let owner: Owner?; let collaborative: Bool?
            }
            let items: [Entry]
        }
        var snapshot = ListeningHistory()
        func add(_ artists: [Artist], title: String?, source: String, window: String, rank: Int?, weight: Double, played: Bool = false, date: Date? = nil, context: String? = nil) {
            for artist in artists {
                let key = artist.name.primaryArtistKey
                let trackKey = title.map { "\(key)|\($0.folded)" }
                snapshot.artistKeys.insert(key)
                if played, let trackKey { snapshot.trackKeys.insert(trackKey) }
                snapshot.signals.append(.init(source:source,window:window,rank:rank,artistKey:key,trackKey:trackKey,playedAt:date,contextURI:context,strength:weight))
            }
        }
        for (window, weight) in [("short_term",0.9),("medium_term",0.85),("long_term",0.8)] {
            for kind in ["tracks","artists"] {
                try Task.checkCancellation()
                do {
                    let query = [URLQueryItem(name:"time_range",value:window),URLQueryItem(name:"limit",value:"50")]
                    if kind == "tracks" {
                        let page: TopSongs = try await get("/me/top/tracks",query:query)
                        for (rank,song) in page.items.enumerated() { add(song.artists,title:song.name,source:"topTracks",window:window,rank:rank+1,weight:weight * (1 - Double(rank)/100),played:true) }
                    } else {
                        let page: TopArtists = try await get("/me/top/artists",query:query)
                        for (rank,artist) in page.items.enumerated() { add([artist],title:nil,source:"topArtists",window:window,rank:rank+1,weight:weight * (1 - Double(rank)/100)) }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { snapshot.unavailableSources.append("\(kind):\(window)") }
            }
        }
        for (source,path,weight) in [("recent","/me/player/recently-played",0.75),("saved","/me/tracks",0.55)] {
            try Task.checkCancellation()
            do {
                let page: Wrapped = try await get(path,query:[URLQueryItem(name:"limit",value:"50")])
                for entry in page.items.compactMap({$0}) {
                    guard let song = entry.track else { continue }
                    add(song.artists,title:song.name,source:source,window:source,rank:nil,weight:weight,played:source=="recent",date:entry.played_at.flatMap { ISO8601DateFormatter().date(from:$0) },context:entry.context?.uri)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { snapshot.unavailableSources.append(source) }
        }
        try Task.checkCancellation()
        do {
            let user = try await currentUser()
            let lists: Lists = try await get("/me/playlists",query:[URLQueryItem(name:"limit",value:"50")])
            let eligible = lists.items.filter { $0.owner?.id == user.id || $0.collaborative == true }
            let recentContexts = Set(snapshot.signals.compactMap(\.contextURI))
            let selected = eligible.sorted {
                let a = recentContexts.contains("spotify:playlist:\($0.id)")
                let b = recentContexts.contains("spotify:playlist:\($1.id)")
                return a == b ? $0.id < $1.id : a
            }.prefix(5)
            for playlist in selected {
                try Task.checkCancellation()
                do {
                    let page: Wrapped = try await get("/playlists/\(playlist.id)/items",query:[URLQueryItem(name:"limit",value:"50")])
                    for entry in page.items.compactMap({$0}) {
                        guard let song = entry.item ?? entry.track else { continue }
                        add(song.artists,title:song.name,source:"playlist",window:"library",rank:nil,weight:0.35,context:"spotify:playlist:\(playlist.id)")
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { snapshot.unavailableSources.append("playlistContents") }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { snapshot.unavailableSources.append("playlists") }
        try Task.checkCancellation()
        guard !snapshot.signals.isEmpty else { throw ListeningHistoryError.unavailable }
        return ListeningHistoryResult(history:snapshot,isPartial:!snapshot.unavailableSources.isEmpty)
    }
}
