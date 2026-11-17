import Foundation
import Combine
typealias ObservableObject = Combine.ObservableObject
typealias Published<Value> = Combine.Published<Value>
struct Track: Sendable { let id=UUID(); let title:String; let artist:String; var previewURL:URL?; var spotifyArtistID:String?=nil }
protocol MusicProvider: Sendable { func resolve(artist:String,title:String) async throws -> Track?; func listeningHistory() async throws -> ListeningHistoryResult }
final class FakeProvider: MusicProvider,@unchecked Sendable {
 var snapshot: ListeningHistory?; var sparse=false; var historyCalls=0; var mismatch=false; var silent=false
 func listeningHistory() async throws -> ListeningHistoryResult { historyCalls+=1;if let snapshot {return ListeningHistoryResult(history:snapshot,isPartial:false)};throw ListeningHistoryError.unavailable }
 func resolve(artist:String,title:String) async throws -> Track? { if sparse && !artist.hasSuffix("-1") { return nil }; return Track(title:mismatch ? "Wrong recording":title,artist:artist,previewURL:silent ? nil:URL(string:"https://example.invalid/preview")) }
}
@MainActor final class MusicProviders { static let shared=MusicProviders(); var current=FakeProvider() }
@MainActor final class PreferenceStore {
 static let shared=PreferenceStore();var profile=PreferenceProfile(artists:["Example"])
 struct Feedback {let candidate_id:String;let brief:String;let verdict:String}
 var feedback:[Feedback]=[]
 func record(candidateID:String,brief:String,verdict:String) async {feedback.append(.init(candidate_id:candidateID,brief:brief,verdict:verdict))}
}
@MainActor enum SongSuggestionService {
 static var calls=0;static var delay=false;static var contexts: [RecommendationSession] = []
 static func assessed(text:String,refinements:[String],profile:PreferenceProfile,count:Int,mode:RecommendationMode = .balanced,context:RecommendationSession = RecommendationSession()) async throws -> RecommendationBatch {
  calls+=1; contexts.append(context)
  if delay { try await Task.sleep(for:.seconds(1)) }
  let conditions=BriefConstraints(conditions:[.init(id:"c1",dimension:"energy",value:"chill",explicit:true)])
  let songs=(0..<30).map { i in AssessedCandidate(id:"\(calls)-\(i)",artist:"Artist \(calls)-\(i)",track:"Song",assessment:.init(checks:[.init(conditionID:"c1",verdict:i==0 ? "conflict":"match")],relevance:0.8,taste:0.8,reason:"Fixture",tasteEvidence:[.init(referenceID:"artist:0",verdict:"match",detail:"Fixture comparison")])) }
  return RecommendationBatch(version:2,constraints:conditions,songs:songs,rejected:0)
 }
 static func suggestSongs(text:String,refinements:[String],count:Int,liked:[TrackCandidate]=[],skipped:[TrackCandidate]=[],excludeArtists:[String]=[]) async throws -> [TrackCandidate] { fatalError("Unexpected legacy request") }
}
typealias GeminiService=SongSuggestionService
struct ITunesService:Sendable {static let shared=ITunesService();func previewURL(artist:String,title:String) async -> URL? {nil}}
enum DeezerService {static func previewURL(artist:String,title:String) async -> URL? {nil}}
@main struct DeckCheck {
 @MainActor static func wait(_ condition:()->Bool) async {for _ in 0..<300 {if condition(){return};try? await Task.sleep(for:.milliseconds(10))};fatalError("Timed out")}
 @MainActor static func main() async {
  UserDefaults.standard.removeObject(forKey:"disableRecommendationV2")
  let builder=DeckBuilder()
  builder.build(text:"chill",refinements:[],mode:.personal)
  await wait {builder.phase != .loading}
  precondition(builder.phase == .ready && builder.tracks.count == 26)
  precondition(!builder.tracks.contains{$0.artist.hasSuffix("-0")})
  precondition(builder.reasons.count==builder.tracks.count)
  precondition(MusicProviders.shared.current.historyCalls==0)
  let first=builder.tracks[0];builder.record(first,liked:true,listenedFraction:0)
  builder.refillIfNeeded(remaining:5)
  await wait {builder.tracks.count>26}
  precondition(!builder.tracks.contains{$0.artist.hasSuffix("-0")})
  precondition(SongSuggestionService.contexts.last?.feedback.first?.verdict == "keep")
  precondition(SongSuggestionService.contexts.last?.excluded.count == 30)
  precondition(SongSuggestionService.contexts.last?.feedback.first?.artist == first.artist)
  builder.cancel()
  MusicProviders.shared.current.mismatch=true;SongSuggestionService.calls=0
  builder.build(text:"chill",refinements:[])
  await wait {builder.phase != .loading}
  precondition(builder.tracks.isEmpty && SongSuggestionService.calls==2)
  MusicProviders.shared.current.mismatch=false;MusicProviders.shared.current.silent=true;SongSuggestionService.calls=0
  builder.build(text:"chill",refinements:[])
  await wait {builder.phase != .loading}
  precondition(builder.tracks.isEmpty && SongSuggestionService.calls==2)
  MusicProviders.shared.current.silent=false;SongSuggestionService.delay=true
  builder.build(text:"chill",refinements:[])
  try? await Task.sleep(for:.milliseconds(40));builder.cancel()
  try? await Task.sleep(for:.milliseconds(50));precondition(builder.tracks.isEmpty)
  SongSuggestionService.delay=false
  let beforeCalls=SongSuggestionService.calls
  builder.build(text:"chill",refinements:[],useListeningHistory:true)
  await wait { builder.phase != .loading }
  if case .historyUnavailable = builder.phase {} else { fatalError("Expected explicit fallback decision") }
  precondition(SongSuggestionService.calls==beforeCalls)
  var snapshot=ListeningHistory()
  snapshot.signals=[.init(source:"topTracks",window:"short_term",rank:1,artistKey:"artist 1 1",trackKey:"artist 1 1|song",playedAt:nil,contextURI:nil,strength:1)]
  MusicProviders.shared.current.snapshot=snapshot
  SongSuggestionService.calls=0
  builder.build(text:"chill",refinements:[],mode:.personal,useListeningHistory:true)
  await wait {builder.phase != .loading}
  precondition(builder.phase == .ready)
  precondition(builder.personalizationNote?.contains("Spotify snapshot") == true)
  precondition(builder.tracks.first?.artist == "Artist 1-1", "Personal ranking must survive resolution")
  builder.cancel()
  PreferenceStore.shared.profile = PreferenceProfile()
  snapshot.signals = (1...8).map { (i: Int) in .init(source:"topTracks",window:"short_term",rank:i,artistKey:"artist 1 \(i)",trackKey:nil,playedAt:nil,contextURI:nil,strength:1) }
  MusicProviders.shared.current.snapshot=snapshot
  SongSuggestionService.calls=0
  builder.build(text:"chill",refinements:[],mode:.personal,useListeningHistory:true)
  await wait {builder.phase != .loading}
  precondition(builder.tracks.count==8, "Spotify-only personal mode must not fill with unrelated artists")
  let personalCount=builder.tracks.count
  let personalCalls=SongSuggestionService.calls
  builder.refillIfNeeded(remaining:5)
  await wait {builder.personalizationNote?.contains("No more verified matches") == true}
  precondition(builder.tracks.count==personalCount)
  builder.refillIfNeeded(remaining:5)
  try? await Task.sleep(for:.milliseconds(30))
  precondition(SongSuggestionService.calls==personalCalls+1)
  let ordered=["A", "A", "B", "C"].enumerated().map { Track(title:String($0.offset),artist:$0.element,previewURL:nil) }
  precondition(DeckBuilder.preserveRankWithArtistSpacing(ordered).map(\.title)==["0","2","1","3"])
  precondition(DeckBuilder.preserveRankWithArtistSpacing(Array(ordered.suffix(2)),after:"B").map(\.title)==["3","2"])
  print("PASS personal rank survives resolution; unmatched personal refill stops; artist spacing stays stable")
  builder.cancel()
  MusicProviders.shared.current.sparse=true
  SongSuggestionService.calls=0
  builder.build(text:"chill recent",refinements:[])
  await wait {builder.phase != .loading}
  precondition(builder.tracks.count==2)
  if case .failed = builder.phase {} else { fatalError("Small selection should need an explicit choice") }
  builder.continueWithSmallDeck()
  precondition(builder.phase == .ready)
  let calls=SongSuggestionService.calls
  builder.refillIfNeeded(remaining:1)
  try? await Task.sleep(for:.milliseconds(30))
  precondition(SongSuggestionService.calls==calls)
  print("PASS explicit small-deck choice retains valid cards without another refill")
  print("PASS production deck: assessment gate on initial/refill, reasons, no history calls, no wrong recordings, no silent cards, bounded supplements, cancellation")
 }
}
