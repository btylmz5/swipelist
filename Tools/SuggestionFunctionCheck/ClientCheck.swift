import Foundation

enum Supabase {
    static let isConfigured = true
    static let baseURL = "https://example.invalid"
    static let anonKey = "public-key"
    enum SupabaseError: Error { case notConfigured }
}
@MainActor final class SupabaseAuth {
    static let shared = SupabaseAuth()
    func validAccessToken() async throws -> String { "session-token" }
}
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var capturedBody = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        if let body = request.httpBody { Self.capturedBody = body }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
            Self.capturedBody = data
        }
        precondition(request.url?.path == "/functions/v1/swipelist2-suggest-songs")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
        precondition(request.value(forHTTPHeaderField: "apikey") == "public-key")
        precondition(request.value(forHTTPHeaderField: "x-api-key") == nil)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Check {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let client = SongSuggestionClient(baseURL: Supabase.baseURL, anonKey: Supabase.anonKey, session: URLSession(configuration: config))
        StubProtocol.body = #"{"songs":[{"artist":" Artist ","track":"Song"},{"artist":"Artist","track":"Song"},{"artist":"","track":"Empty"}]}"#
        let songs = try await client.suggestSongs(text: "night drive", accessToken: "session-token")
        precondition(songs.count == 1 && songs[0].artist == "Artist")
        for (status, body, expected) in [(401, "{}", "session expired"), (429, #"{"error":"Suggestions are busy."}"#, "busy"), (200, #"{"songs":[]}"#, "no usable songs")] {
            StubProtocol.status = status; StubProtocol.body = body
            do { _ = try await client.suggestSongs(text: "test", accessToken: "session-token"); fatalError("Expected error") }
            catch { precondition(error.localizedDescription.contains(expected)) }
        }
        let before = StubProtocol.requestCount
        do { _ = try await client.suggestSongs(text: " ", accessToken: "session-token"); fatalError("Expected empty brief error") }
        catch { precondition(StubProtocol.requestCount == before) }
        StubProtocol.status = 200
        StubProtocol.body = #"{"version":2,"constraints":{"conditions":[{"id":"c1","dimension":"energy","value":"chill","explicit":true}]},"songs":[],"rejected":0}"#
        let safeContext = RecommendationSession(excluded:[.init(artist:"Original model artist",track:"Original model song")],feedback:[.init(artist:"Original model artist",track:"Original model song",verdict:"keep")])
        _ = try await SongSuggestionService.assessed(text:"chill",refinements:[],profile:PreferenceProfile(artists:["Explicit favorite"]),mode:.personal,context:safeContext,transport:client.session)
        let payload = try JSONSerialization.jsonObject(with: StubProtocol.capturedBody) as! [String:Any]
        precondition(Set(payload.keys) == Set(["version","text","refinements","count","preferences","mode","session"]))
        let preferences = payload["preferences"] as! [String:Any]
        precondition(Set(preferences.keys) == Set(["source","artists","examples","likes","avoids"]))
        let session = payload["session"] as! [String:Any]
        precondition(session["source"] as? String == "swipelist_model")
        precondition((session["excluded"] as! [[String:Any]]).first?["verdict"] == nil)
        precondition(payload["mode"] as? String == "personal")
        print("PASS v2 real transport serializes only explicit preferences and original model context")
        print("Swift client checks passed: authenticated route, response cleanup, expired session, provider errors, empty brief.")
    }
}
