import Foundation

/// Owns the brief → deck chain end to end: the model names real songs, each one is
/// resolved to a playable track, and the deck extends itself as the listener swipes.
///
/// Songs come from the model rather than from a tag database. Tag lookups sound
/// like the safer route but lose badly on anything outside mainstream Western
/// genres — Last.fm has two tracks tagged "turkish hip hop" — and the songs they
/// return were never the ones curated for the brief.
@MainActor
final class DeckBuilder: ObservableObject {
    enum Failure: Equatable {
        case network
        case suggestion(String)
        /// The chain completed but produced too few playable songs.
        case notEnoughSongs(found: Int)
    }

    enum Phase: Equatable {
        case loading
        case ready
        case historyUnavailable(String)
        case failed(Failure)
    }

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var phase: Phase = .loading
    /// What the chain is doing right now, surfaced on the loading screen.
    @Published private(set) var status = "Reading your brief"
    @Published private(set) var personalizationNote: String?
    @Published private(set) var reasons: [UUID: String] = [:]
    private var assessments: [String: AssessedCandidate] = [:]
    private var candidateIDs: [UUID: String] = [:]
    private var candidateKeys: [UUID: String] = [:]
    private var sessionFeedback: [RecommendationSession.Entry] = []
    private var generatedCandidates: [AssessedCandidate] = []
    private var profile = PreferenceProfile()
    private var familiarShare = 0.25
    private var known = Set<String>()
    private var blocked = Set<String>()
    private var trace = RecommendationTrace()
    private var cooldownUntil = Date.distantPast
    private var failedRefills = 0
    private var constraintSummary = "your musical requirements"
    private var listeningHistory: ListeningHistory?
    private var recommendationMode: RecommendationMode = .balanced

    /// Reveal the deck once this many are playable; the rest keep loading behind it.
    private let revealThreshold = 8
    /// Publish only once a pending run spans this many *artists*.
    ///
    /// The spread algorithm can only be as varied as the batch it's given: two
    /// buckets can only ping-pong, and three produce a sliding A→B→A→B→C→B→C→D
    /// pattern. Waiting for a wider batch is what makes the deck feel shuffled.
    private let minArtistsPerFlush = 6
    /// Cap per artist. At 3 a 26-song deck spans only ~9 artists, which reads as
    /// "the same five people over and over" however well it's shuffled.
    private let maxTracksPerArtist = 2
    /// Artists the listener named get a bigger share. Asking for "Travis Scott type
    /// songs" and receiving two Travis Scott tracks out of 26 is not what was asked
    /// for — the named artist is the point of the brief, not an incidental result.
    private let maxTracksPerNamedArtist = 5
    /// Refill when fewer than this many unswiped cards remain.
    private let refillThreshold = 6

    /// Asked for well above the target: Spotify finds nearly everything, but around
    /// a third of tracks have no 30-second preview from Spotify or iTunes, and a
    /// deck card with no audio isn't worth swiping on.
    private let initialSuggestionCount = 26
    private let refillSuggestionCount = 18
    /// How many songs to resolve concurrently. Sequential lookups made a 26-song
    /// deck take almost half a minute.
    private let resolveConcurrency = 6

    /// Claude Sonnet is the default curator; Gemini remains available for comparisons.
    enum SuggestionProvider { case gemini, claude }
    static var provider: SuggestionProvider = .claude

    private static func suggestSongs(
        text: String, refinements: [String], count: Int,
        liked: [TrackCandidate] = [], skipped: [TrackCandidate] = [],
        excludeArtists: [String] = []
    ) async throws -> [TrackCandidate] {
        switch provider {
        case .gemini:
            return try await GeminiService.suggestSongs(
                text: text, refinements: refinements,
                count: count, liked: liked, skipped: skipped, excludeArtists: excludeArtists)
        case .claude:
            return try await SongSuggestionService.suggestSongs(
                text: text, refinements: refinements,
                count: count, liked: liked, skipped: skipped, excludeArtists: excludeArtists)
        }
    }

    private var buildTask: Task<Void, Never>?
    private var refillTask: Task<Void, Never>?

    /// The brief this deck was built from, kept for adaptive refills.
    private var brief: (text: String, refinements: [String])?
    /// Everything already placed in the deck or already tried, so refills never
    /// repeat a song or waste a request re-resolving one.
    private var seenTrackKeys = Set<String>()
    private var attemptedCandidates = Set<String>()
    /// Songs placed per lead artist, so the cap holds across flushes and refills
    /// rather than resetting each batch.
    private var artistTrackCount: [String: Int] = [:]
    // MARK: - Initial build

    func build(text: String, refinements: [String], mode: RecommendationMode = .balanced,
               useListeningHistory: Bool = false, familiarShare: Double = 0.25) {
        buildTask?.cancel()
        refillTask?.cancel()
        refillTask = nil
        tracks = []
        reasons = [:]; assessments = [:]; candidateIDs = [:]; candidateKeys = [:]; sessionFeedback = []; generatedCandidates = []
        profile = PreferenceStore.shared.profile
        self.familiarShare = familiarShare
        known = []; blocked = []; trace = RecommendationTrace(); failedRefills = 0
        listeningHistory = nil
        recommendationMode = mode
        personalizationNote = !RecommendationFeatures.v2 || profile.isEmpty
            ? "Brief only · Add explicit preferences in Profile to personalize"
            : "Using your stated preferences · Spotify listening analysis is off"
        // Songs skipped in past sessions start out excluded, so a rebuilt or
        // similar brief deals fresh cards instead of re-asking settled questions.
        seenTrackKeys = [] // A skip in another brief is not a permanent dislike.
        attemptedCandidates = []
        artistTrackCount = [:]
        brief = (text, refinements)
        phase = .loading
        status = "Reading your brief"

        buildTask = Task { [weak self] in
            guard let self else { return }
            if useListeningHistory && RecommendationFeatures.spotifyLocalExperiment {
                self.status = "Reading your listening history"
                do {
                    let result = try await MusicProviders.shared.current.listeningHistory()
                    guard !Task.isCancelled else { return }
                    self.listeningHistory = result.history
                    self.personalizationNote = result.isPartial
                        ? "\(mode.title) · Using partial listening history"
                        : "\(mode.title) · Using your available listening history"
                } catch {
                    guard !Task.isCancelled else { return }
                    self.phase = .historyUnavailable(error.localizedDescription)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            self.status = "Reading your brief"
            await self.runInitialBuild(text: text, refinements: refinements)
        }
    }

    private func runInitialBuild(text: String, refinements: [String]) async {
        do {
            if RecommendationFeatures.v2 {
                for round in 0..<2 {
                    status = round == 0 ? "Checking songs against your brief" : "Finding more songs that pass your brief"
                    try await buildAssessed(count: 60, limit: max(0, initialSuggestionCount - tracks.count))
                    if tracks.count >= initialSuggestionCount { break }
                }
            } else {
                let suggestions = try await Self.suggestSongs(text: text, refinements: refinements, count: initialSuggestionCount)
                await resolveSuggestions(suggestions, limit: initialSuggestionCount)
            }

        } catch {
            guard !Task.isCancelled else { return }
            if tracks.count >= revealThreshold {
                phase = .ready
                personalizationNote = "A smaller checked deck is ready. Additional songs couldn't load; your brief wasn't relaxed."
            } else {
                phase = .failed(Self.isNetworkError(error) ? .network : .suggestion(error.localizedDescription))
            }
            return
        }
        guard !Task.isCancelled else { return }

        logDeck()
        if tracks.count >= revealThreshold {
            phase = .ready
        } else {
            phase = .failed(.suggestion("Only \(tracks.count) playable songs could be verified for \(constraintSummary). Nothing was relaxed automatically. \(tracks.isEmpty ? "Try editing a requirement." : "You can listen to this smaller selection or edit your brief.")"))
        }
    }

    /// Small checked decks require an explicit user choice; never weaken admission.
    func continueWithSmallDeck() {
        guard case .failed = phase, !tracks.isEmpty else { return }
        failedRefills = 2 // Do not immediately spend another round on the same scarce pool.
        personalizationNote = "Small verified selection · \(tracks.count) songs · Your requirements are unchanged"
        phase = .ready
    }

    // Feedback about fit belongs to the complete brief, including refinements.
    private var feedbackContext: String {
        guard let brief, let data = try? JSONEncoder().encode([brief.text] + brief.refinements) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Adaptive refill

    /// Store contextual intent using only the independent model candidate ID.
    func record(_ track: Track, liked wasLiked: Bool, listenedFraction: Double = 0) {
        // A normal skip is session-scoped, and preview duration never means dislike.
        if let id = candidateIDs[track.id], let _ = brief?.text {
            let text = feedbackContext
            if wasLiked { recordModelFeedback(track, verdict: "keep") }
            Task { await PreferenceStore.shared.record(candidateID: id, brief: text, verdict: wasLiked ? "keep" : "skip") }
        }
    }

    func explicitFeedback(_ track: Track, verdict: String) {
        guard let id = candidateIDs[track.id], brief != nil else { return }
        let text = feedbackContext
        let key = candidateKeys[track.id] ?? "\(track.artist.folded)|\(track.title.folded)"
        if verdict == "known" { known.insert(key) }
        if verdict == "dislike" || verdict == "off_brief" { recordModelFeedback(track, verdict: verdict) }
        if verdict == "dislike" || verdict == "off_brief" { blocked.insert(key) }
        Task { await PreferenceStore.shared.record(candidateID: id, brief: text, verdict: verdict) }
        personalizationNote = verdict == "off_brief" ? "Marked as off brief · This does not change your overall taste" : "Feedback recorded for this playlist"
    }

    private func recordModelFeedback(_ track: Track, verdict: String) {
        guard let key = candidateKeys[track.id], let original = assessments[key] else { return }
        // Only original model metadata crosses the AI boundary. Never resolved
        // Spotify titles, IDs, library signals, or listening duration.
        sessionFeedback.removeAll { $0.artist == original.artist && $0.track == original.track }
        sessionFeedback.append(.init(artist: original.artist, track: original.track, verdict: verdict))
        sessionFeedback = Array(sessionFeedback.suffix(10))
    }

    private func buildAssessed(count: Int, limit: Int, isRefill: Bool = false) async throws {
        guard let brief else { return }
        if cooldownUntil > Date() { throw SuggestionRateLimit(until: cooldownUntil) }
        let batch: RecommendationBatch
        do { batch = try await SongSuggestionService.assessed(text: brief.text, refinements: brief.refinements, profile: profile, count: count, mode: recommendationMode,
            context: RecommendationSession(excluded: generatedCandidates.suffix(80).map { .init(artist: $0.artist, track: $0.track) }, feedback: sessionFeedback)) }
        catch let error as SuggestionRateLimit { cooldownUntil = error.until; throw error }
        try Task.checkCancellation()
        constraintSummary = batch.constraints.conditions.filter(\.explicit).map(\.value).joined(separator: ", ")
        trace.generated += batch.songs.count + batch.rejected
        trace.rejected += batch.rejected + batch.songs.filter { !$0.assessment.accepts(batch.constraints) }.count
        generatedCandidates += batch.songs
        let feedback = PreferenceStore.shared.feedback
        let dislikes = Set(feedback.filter { $0.verdict == "dislike" || ($0.verdict == "off_brief" && $0.brief == feedbackContext) }.map(\.candidate_id))
        let knownIDs = Set(feedback.filter { $0.verdict == "known" }.map(\.candidate_id))
        for song in batch.songs where knownIDs.contains(song.id) { known.insert(song.candidate.dedupeKey) }
        let eligible = batch.songs.filter { $0.assessment.accepts(batch.constraints) && !dislikes.contains($0.id) && !blocked.contains($0.candidate.dedupeKey) && !attemptedCandidates.contains($0.candidate.dedupeKey) }
        // Explicit example tracks are the only pre-session evidence of familiarity.
        for song in eligible where profile.exampleKeys.contains(song.candidate.dedupeKey) { known.insert(song.candidate.dedupeKey) }
        if let history = listeningHistory {
            for song in eligible where history.knows(song.candidate) { known.insert(song.candidate.dedupeKey) }
        }
        let personalCandidates = eligible.filter { song in
            guard recommendationMode == .personal else { return true }
            if profile.hasPositiveReferences || sessionFeedback.contains(where: { $0.verdict == "keep" }) {
                return song.assessment.hasPersonalEvidence
            }
            if let history = listeningHistory { return history.affinity(song.candidate) > 0 }
            return true // Brief-only cold start is explicitly labelled below.
        }
        trace.rejected += eligible.count - personalCandidates.count
        let ranked = PreferenceRanking.rank(personalCandidates, constraints: batch.constraints, mode: recommendationMode, profile: profile, known: known, familiarShare: familiarShare, limit: eligible.count, history: listeningHistory)
        // Do not silently extend a Spotify-personalized deck with an entirely
        // unmatched batch. Explicit preferences can still provide separate evidence.
        if isRefill, recommendationMode == .personal, profile.isEmpty,
           let history = listeningHistory,
           !ranked.contains(where: { history.affinity($0.candidate) > 0 }) {
            failedRefills = 2
            personalizationNote = "No more verified matches to your available Spotify taste. Your existing cards remain available. Try Balanced for broader discovery."
            return
        }
        for song in ranked { assessments[song.candidate.dedupeKey] = song }
        // Resolve the bounded pool first. Select familiarity proportions only
        // among actually playable recordings, including preview failures.
        let playable = await resolve(ranked.map(\.candidate), maxTotal: ranked.count)
        try Task.checkCancellation()
        let playableKeys = Set(playable.compactMap { candidateKeys[$0.id] })
        let selected = PreferenceRanking.rank(ranked.filter { playableKeys.contains($0.candidate.dedupeKey) }, constraints: batch.constraints,
            mode: recommendationMode, profile: profile, known: known, familiarShare: familiarShare,
            limit: limit, history: listeningHistory, previousCount: tracks.count,
            previousFamiliar: tracks.filter { known.contains(candidateKeys[$0.id] ?? "") }.count)
        let byKey = Dictionary(playable.compactMap { track -> (String, Track)? in
            guard let key = candidateKeys[track.id] else { return nil }; return (key, track)
        }, uniquingKeysWith: { first, _ in first })
        let chosen = selected.compactMap { byKey[$0.candidate.dedupeKey] }
        let chosenIDs = Set(chosen.map(\.id))
        for track in playable where !chosenIDs.contains(track.id) {
            reasons.removeValue(forKey: track.id); candidateKeys.removeValue(forKey: track.id); candidateIDs.removeValue(forKey: track.id)
        }
        tracks += Self.preserveRankWithArtistSpacing(chosen, after: tracks.last?.artist)
        for track in chosen { artistTrackCount[track.artist.primaryArtistKey, default: 0] += 1 }
        try Task.checkCancellation()
        trace.accepted = tracks.count; trace.log()
        let familiar = tracks.filter { known.contains(candidateKeys[$0.id] ?? "") }.count
        let target = Int((Double(tracks.count) * familiarShare).rounded())
        let personal = tracks.filter { track in
            candidateKeys[track.id].flatMap { assessments[$0] }?.assessment.hasPersonalEvidence == true
        }.count
        var parts = [profile.hasPositiveReferences || listeningHistory != nil || !sessionFeedback.isEmpty ? recommendationMode.title : "Brief only"]
        if listeningHistory != nil && !profile.hasPositiveReferences && recommendationMode == .personal {
            parts.append("Limited to Spotify matches; add favorite songs for discoveries beyond those artists")
        }
        if profile.hasPositiveReferences || !sessionFeedback.isEmpty {
            parts.append("\(personal)/\(tracks.count) songs linked to your preferences by musical comparison")
        }
        if let history = listeningHistory {
            let matches = tracks.filter { track in candidateKeys[track.id].flatMap { assessments[$0] }.map { history.affinity($0.candidate) > 0 } ?? false }.count
            parts.append("Spotify snapshot\(history.unavailableSources.isEmpty ? "" : " (partial)"): \(matches)/\(tracks.count) songs match")
            if matches == 0 && !profile.hasPositiveReferences { parts.append("No personal matches; these are brief-only discoveries") }
        }
        parts.append("\(familiar)/\(tracks.count) confirmed familiar · target \(Int(familiarShare*100))%")
        if familiar < target { parts.append("Not enough verified familiar songs to meet your target") }
        parts.append("Unknown does not mean unheard")
        personalizationNote = parts.joined(separator: ". ")
    }

    /// Refill with the same brief and preference snapshot. Feedback exclusions
    /// stay local; explicit feedback uses only original model-generated identities.
    func refillIfNeeded(remaining: Int) {
        guard phase == .ready, remaining <= refillThreshold else { return }
        guard refillTask == nil, let brief, failedRefills < 2, cooldownUntil <= Date() else { return }

        refillTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refillTask = nil }
            do {
                if RecommendationFeatures.v2 {
                    let before = tracks.count
                    try await buildAssessed(count: 40, limit: refillSuggestionCount, isRefill: true)
                    if tracks.count == before { failedRefills += 1 }
                } else {
                    let suggestions = try await Self.suggestSongs(text: brief.text, refinements: brief.refinements, count: refillSuggestionCount)
                    await resolveSuggestions(suggestions, limit: refillSuggestionCount)
                }
                self.logDeck()
            } catch {
                failedRefills += 1
                personalizationNote = "More songs couldn't pass or load. Your existing cards are still available; your brief wasn't relaxed."
            }
        }
    }

    private func resolveSuggestions(_ suggestions: [TrackCandidate], limit: Int) async {
        let ranked = selectCandidates(suggestions, limit: suggestions.count)
        let before = tracks.count
        let resolved = await resolve(Array(ranked.prefix(limit)), maxTotal: limit)
        tracks += resolved
        for track in resolved { artistTrackCount[track.artist.primaryArtistKey, default: 0] += 1 }
        guard !Task.isCancelled else { return }
        // Preferred candidates may lack previews. Try the remaining brief-matching
        // pool before failing or leaving a refill empty; never inject unrelated songs.
        if tracks.count - before < limit, ranked.count > limit {
            let extra = await resolve(Array(ranked.dropFirst(limit)), maxTotal: limit - (tracks.count - before))
            tracks += extra
            for track in extra { artistTrackCount[track.artist.primaryArtistKey, default: 0] += 1 }
        }
    }

    private func selectCandidates(_ candidates: [TrackCandidate], limit: Int) -> [TrackCandidate] {
        Array(candidates.filter { !attemptedCandidates.contains($0.dedupeKey) && !blocked.contains($0.dedupeKey) }.uniqued(by: \.dedupeKey).prefix(limit))
    }

    /// Whether the listener actually named this artist in their brief.
    ///
    /// Matched on whole words against the folded brief text, so "Travis Scott type
    /// songs" marks Travis Scott but a brief mentioning "the future" doesn't
    /// accidentally promote the artist Future. Naming several artists works without
    /// any extra handling — each is matched independently.
    private func isNamedInBrief(_ artist: String) -> Bool {
        guard let text = brief?.text else { return false }
        let needle = artist.primaryArtistKey
        guard needle.count >= 3 else { return false }
        return " \(text.folded) ".contains(" \(needle) ")
    }

    /// Lead artists already on the deck, so a refill is asked for different ones.
    private func artistsInDeck() -> [String] {
        var seen = Set<String>()
        return tracks.compactMap { track in
            let key = track.artist.primaryArtistKey
            guard seen.insert(key).inserted else { return nil }
            // A named artist that still has room shouldn't be excluded — the brief
            // asked for them, so refills may keep returning them until they're full.
            let cap = isNamedInBrief(track.artist) ? maxTracksPerNamedArtist : maxTracksPerArtist
            guard artistTrackCount[key, default: 0] >= cap else { return nil }
            return track.artist
        }
    }

    func cancel() {
        buildTask?.cancel()
        refillTask?.cancel()
        buildTask = nil
        refillTask = nil
        listeningHistory = nil
    }

    // MARK: - Resolution

    /// Resolve only admitted candidates; exact identity and playable preview
    /// checks cannot be bypassed by catalogue expansion or refills.
    private func resolve(_ candidates: [TrackCandidate], maxTotal: Int) async -> [Track] {
        var result: [Track] = []
        var resolvingArtistCount = artistTrackCount
        // Captured once so the concurrent tasks below don't touch the main actor.
        let provider = MusicProviders.shared.current
        /// One bucket per artist, awaiting interleave.
        var pending: [String: [Track]] = [:]
        var pendingInRankOrder: [Track] = []
        var lostNotFound = 0, lostVersion = 0, lostDuplicate = 0, lostNoPreview = 0

        func flush() {
            guard !pending.isEmpty else { return }
            if RecommendationFeatures.v2 {
                result += Self.preserveRankWithArtistSpacing(pendingInRankOrder, after: result.last?.artist ?? tracks.last?.artist)
            } else {
                result += Self.interleave(Array(pending.values), after: result.last?.artist ?? tracks.last?.artist)
            }
            pendingInRankOrder = []
            pending = [:]

        }

        // Resolve in parallel chunks, preserving the order the model gave.
        let fresh = candidates.filter { attemptedCandidates.insert($0.dedupeKey).inserted }

        for chunk in stride(from: 0, to: fresh.count, by: resolveConcurrency)
            .map({ Array(fresh[$0..<min($0 + resolveConcurrency, fresh.count)]) }) {
            if Task.isCancelled { return [] }
            if result.count + pending.values.reduce(0, { $0 + $1.count }) >= maxTotal { break }

            let resolved: [Track?] = await withTaskGroup(of: (Int, Track?).self) { group in
                for (offset, candidate) in chunk.enumerated() {
                    group.addTask {
                        guard var track = try? await provider.resolve(
                            artist: candidate.artist, title: candidate.title
                        ) else { return (offset, nil) }
                        guard RecordingIdentity.matches(artist: track.artist, title: track.title, wantedArtist: candidate.artist, wantedTitle: candidate.title) else { return (offset,nil) }
                        // Spotify omits preview audio for much of its catalogue now.
                        // Fall back through iTunes, then Deezer, whose catalogue
                        // covers non-English music far better than iTunes does.
                        if track.previewURL == nil {
                            track.previewURL = await ITunesService.shared.previewURL(
                                artist: track.artist, title: track.title
                            )
                        }
                        if track.previewURL == nil {
                            track.previewURL = await DeezerService.previewURL(
                                artist: track.artist, title: track.title
                            )
                        }
                        return (offset, track)
                    }
                }
                var out: [(Int, Track?)] = []
                for await result in group { out.append(result) }
                return out.sorted { $0.0 < $1.0 }.map(\.1)
            }

            for (index, item) in resolved.enumerated() {
                guard result.count + pending.values.reduce(0, { $0 + $1.count }) < maxTotal else { break }
                guard let track = item else { lostNotFound += 1; continue }
                guard !Self.isNonCanonicalVersion(track.title) else { lostVersion += 1; continue }

                let trackKey = "\(track.artist.folded)|\(track.title.folded)"
                guard seenTrackKeys.insert(trackKey).inserted else { lostDuplicate += 1; continue }
                guard track.previewURL != nil else { lostNoPreview += 1; continue }

                let artistKey = track.artist.primaryArtistKey
                let cap = isNamedInBrief(track.artist) ? maxTracksPerNamedArtist : maxTracksPerArtist
                guard resolvingArtistCount[artistKey, default: 0] < cap else { continue }
                resolvingArtistCount[artistKey, default: 0] += 1

                if let assessment = assessments[chunk[index].dedupeKey] {
                    let localReason = (listeningHistory?.affinity(assessment.candidate) ?? 0) > 0
                        ? "Matches your available Spotify listening/library snapshot. " : ""
                    reasons[track.id] = localReason + "Model-reviewed musical fit: " + assessment.assessment.reason
                    candidateIDs[track.id] = assessment.id
                    candidateKeys[track.id] = assessment.candidate.dedupeKey
                    if let evidence = assessment.assessment.tasteEvidence?.first(where: { $0.verdict == "match" }) {
                        reasons[track.id] = assessment.assessment.reason + " Your taste: " + evidence.detail
                    }
                }
                pending[artistKey, default: []].append(track)
                pendingInRankOrder.append(track)
                }

            if pending.count >= minArtistsPerFlush { flush() }
        }

        if Task.isCancelled { return [] }
        // No unassessed catalogue top-ups. Provider metadata cannot be sent to AI
        // to manufacture an assessment; only independently assessed candidates enter.


        if Task.isCancelled { return [] }
        flush()
        trace.resolved += fresh.count - lostNotFound
        trace.unresolved += lostNotFound
        trace.noPreview += lostNoPreview
        #if DEBUG
        NSLog("SWFUNNEL asked=%d kept=%d | notFound=%d badVersion=%d duplicate=%d noPreview=%d",
              candidates.count, candidates.count - lostNotFound - lostVersion - lostDuplicate - lostNoPreview,
              lostNotFound, lostVersion, lostDuplicate, lostNoPreview)
        #endif
        return result
    }

    // MARK: - Ordering

    /// Spreads per-artist buckets into one run.
    ///
    /// Each step takes from whichever artist has the most tracks left, skipping the
    /// one just played. Draining the largest bucket first stops a heavily-stocked
    /// artist bunching at the tail; skipping the previous artist prevents
    /// back-to-back repeats. Ties break randomly, so the order isn't a fixed cycle
    /// like the A/B/A/B a plain round-robin produces.
    ///
    /// `after` is the artist already on the end of the deck, so runs appended one
    /// after another don't collide at the seam.
    /// Move only an adjacent repeated artist; preserve personal/familiarity rank
    /// instead of replacing it with random bucket order after resolution.
    static func preserveRankWithArtistSpacing(_ ranked: [Track], after previousArtist: String? = nil) -> [Track] {
        var remaining = ranked
        var result: [Track] = []
        var last = previousArtist?.primaryArtistKey
        while !remaining.isEmpty {
            let index = remaining.firstIndex { $0.artist.primaryArtistKey != last } ?? 0
            let track = remaining.remove(at: index)
            result.append(track)
            last = track.artist.primaryArtistKey
        }
        return result
    }

    private static func interleave(_ buckets: [[Track]], after previousArtist: String? = nil) -> [Track] {
        var remaining = buckets.filter { !$0.isEmpty }
        var merged: [Track] = []
        var lastArtist = previousArtist?.primaryArtistKey

        while !remaining.isEmpty {
            let ranked = remaining.indices.shuffled().sorted { remaining[$0].count > remaining[$1].count }
            // Falls back to the fullest bucket when only one artist is left.
            let pick = ranked.first { remaining[$0].first?.artist.primaryArtistKey != lastArtist } ?? ranked[0]

            let track = remaining[pick].removeFirst()
            merged.append(track)
            lastArtist = track.artist.primaryArtistKey
            if remaining[pick].isEmpty { remaining.remove(at: pick) }
        }
        return merged
    }

    // MARK: - Helpers

    /// Versions that shouldn't stand in for a real song: instrumentals, karaoke,
    /// tribute-act covers, and remixes credited to another act.
    private static func isNonCanonicalVersion(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return ["instrumental", "karaoke", "tribute", "made famous", "originally performed",
                "cover version", "commentary", "interlude", "skit"]
            .contains { lowered.contains($0) }
    }

    private func logDeck() { trace.accepted = tracks.count; trace.log() }

    private static func isNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .timedOut, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}
