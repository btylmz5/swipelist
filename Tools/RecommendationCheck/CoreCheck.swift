import Foundation
@main struct Check {
 static func main() {
  let constraints=BriefConstraints(conditions:[.init(id:"energy",dimension:"energy",value:"chill",explicit:true)])
  func song(_ id: String, _ relevance: Double, _ taste: Double, verdict: String = "match") -> AssessedCandidate {
    .init(id:id,artist:"Artist \(id)",track:"Song \(id)",assessment:.init(checks:[.init(conditionID:"energy",verdict:verdict)],relevance:relevance,taste:taste,reason:"Fixture reasoning"))
  }
  let profile=PreferenceProfile(artists:["Example"])
  let a=song("a",1,0),b=song("b",0.7,0.8),c=song("c",0.4,1)
  let pool=[a,b,c,song("bad",1,1,verdict:"conflict"),song("uncertain",1,1,verdict:"uncertain")]
  func rank(_ mode:RecommendationMode, share:Double=0, known:Set<String>=[]) -> [AssessedCandidate] {
   PreferenceRanking.rank(pool,constraints:constraints,mode:mode,profile:profile,known:known,familiarShare:share,limit:3)
  }
  precondition(rank(.discovery).first?.id=="a")
  precondition(rank(.balanced).first?.id=="b")
  precondition(rank(.personal).first?.id=="c")
  for mode in RecommendationMode.allCases { precondition(rank(mode).count==3) }
  precondition(rank(.personal,share:1,known:[a.candidate.dedupeKey]).first?.id=="a")
  precondition(rank(.personal,share:0,known:[a.candidate.dedupeKey]).first?.id=="c")
  precondition(!RecordingIdentity.matches(artist:"Travis Scott",title:"SICKO MODE",wantedArtist:"Travis Scott",wantedTitle:"Another song"))
  precondition(!RecordingIdentity.matches(artist:"Wrong artist",title:"Song",wantedArtist:"Artist",wantedTitle:"Song"))
  precondition(RecordingIdentity.matches(artist:"Artist",title:"Song - 2011 Remaster",wantedArtist:"Artist",wantedTitle:"Song"))
  precondition(!RecordingIdentity.matches(artist:"Artist",title:"Song (Live)",wantedArtist:"Artist",wantedTitle:"Song"))
  var snapshot = ListeningHistory()
  let signal = ListeningHistory.Signal(source:"topTracks",window:"short_term",rank:1,artistKey:c.artist.primaryArtistKey,trackKey:c.candidate.dedupeKey,playedAt:nil,contextURI:nil,strength:1)
  snapshot.signals = [signal]
  let local = PreferenceRanking.rank(pool,constraints:constraints,mode:.personal,profile:PreferenceProfile(),known:[],familiarShare:0,limit:3,history:snapshot)
  precondition(local.first?.id == "c")
  precondition(!local.contains { $0.id == "bad" || $0.id == "uncertain" })
  let before = snapshot.affinity(c.candidate)
  snapshot.signals = Array(repeating:signal,count:500)
  precondition(snapshot.affinity(c.candidate)==before)
  precondition(!snapshot.knows(c.candidate)) // Affinity isn't evidence of having heard a track.
  let withExamples=PreferenceProfile(examples:["Artist a — Song a", "Artist b - Song b"])
  precondition(withExamples.exampleKeys == Set([a.candidate.dedupeKey,b.candidate.dedupeKey]))
  // If the preceding playable batch missed its familiar target, the next batch
  // catches up rather than resetting its ratio to zero.
  let catchup=PreferenceRanking.rank([a,b,c],constraints:constraints,mode:.personal,profile:profile,known:[a.candidate.dedupeKey,b.candidate.dedupeKey],familiarShare:0.5,limit:2,previousCount:10,previousFamiliar:0)
  precondition(catchup.allSatisfy { $0.id != "c" })
  precondition(!RecommendationFeatures.spotifyAnalysisApproved)
  print("PASS mode ordering, independent familiarity, uniform quality gate, exact recording identity, Spotify gate")
 }
}
