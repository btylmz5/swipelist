# Recommendation v2 — 31 October 2026

## Current rollout

Debug builds enable v2. Release builds remain explicitly labelled brief-only;
human brief-fit and blind-personalization acceptance gates have not passed.
`RecommendationFeatures.v2` reads `disableRecommendationV2` in Debug for rollback.
`spotifyAnalysisApproved` is independently false. No history-based preferences,
playlist analysis, or Spotify-derived metadata are sent to the model. Legacy
request shapes remain accepted by the dedicated function, but their feedback and
excluded-artist fields are dropped before calling the model.

## Inputs and profile

The mandatory brief controls admission. An optional first-use sheet collects up
to five artists and five Artist — Song examples plus liked/avoided qualities.
Profile allows editing, retrying sync, and resetting preferences/feedback. Data
is scoped to the Supabase user; no device-global preference persistence is used.
Account changes recreate the root view and clear/reload in-memory preferences.

`sw2_preferences` and `sw2_feedback` are separate from Spotify-derived and
Swipelist3 tables, with owner-only RLS. They contain explicit user preferences,
independent model candidate IDs and context-specific verdicts, never copied
Spotify listening history. Known/dislike/off-brief feedback affects future
candidate selection; ordinary skip is not permanent dislike and listen time is
not treated as negative evidence. Keep/skip events are retained for evaluation;
they do not currently train a general sonic taste model.

## Pipeline

The v2 request allowlists text, refinements, count and explicit preferences only.
Claude generates a structured set of brief constraints and at most 60 real-song
candidates. A separate review checks track-level fit, uncertainty and taste.
Reviews run in bounded batches of 15 (at most four parallel calls). Missing,
conflicting, uncertain explicit conditions, malformed output, or upstream errors
never bypass admission. Model judgments are not measured audio features.

The client defensively rechecks assessments. It ranks eligible candidates using
20/50/80% personal-score weight (Discover/Balanced/Your taste), independently of
the familiar-song target (default 25%). Familiarity comes from explicitly entered
examples and explicit known verdicts. No confirmed evidence means unknown, not
unheard. Targets can be missed because of availability; the UI shows coverage.

Spotify resolution must match both artist and recording. Optional previews use
iTunes then Deezer. Unassessed artist-catalogue top-ups are disabled: provider
metadata cannot be uploaded to AI merely to obtain an assessment. Artist caps
and interleaving apply. There is one supplemental initial round, up to 26 total
initial cards, and at least eight playable cards are required. Refills use the
same gate; repeated failed/empty refills stop. Retry-After cooldowns prevent
request storms. If a supplement fails after eight accepted cards, the smaller
deck remains usable.

Each admitted card exposes model-reviewed reasoning and explicit feedback. All
recommendation logs are aggregate counts, not titles, prompts, profiles or tokens.

## Server and database

Function: `supabase/functions/swipelist2-suggest-songs/` (index.ts + quality.ts).
Keep `verify_jwt=true`; Auth `/user` independently verifies signed-in accounts.
Secret: `SWIPELIST2_ANTHROPIC_API_KEY`. Never ship it in Release.
Apply migrations 0004 and 0005 in order, once, before enabling the client.
Existing `swipelist3-suggest-songs` and its tables are unchanged.

v2 JSON request: `version:2`, `text`, `refinements`, `count:1...60`,
`preferences:{source:"user_explicit",artists,examples,likes,avoids}`.
Response: `version:2`, `constraints:{conditions}`, `songs` containing stable
candidate id, artist, track, assessment, plus aggregate `rejected`.
Unknown request fields/provenance are rejected. v1 is the compatibility path.

## Verification and remaining gates

- `bash Tools/PersonalizationCheck/run.sh`: legacy source-decoding fixtures plus
  production v2 ranking and DeckBuilder integration tests.
- `bash Tools/SuggestionFunctionCheck/run.sh`: authenticated legacy handler and
  Swift transport tests.
- `bash Tools/RecommendationCheck/run.sh`: independent reviewer, provenance,
  quality gate, mode ordering, familiar target, exact identity, initial/refill,
  missing preview, bounded supplement, cancellation, policy-disabled history.
- `Tools/RecommendationCheck/briefs.json`: 30 briefs; human-ratings.csv has 300
  unrated positions. `score.py` reports pending until humans actually review.
- Blind preference comparison requires at least three independent participants
  and a majority favoring v2. No results have been fabricated or inferred from
  model self-scores.

The Spotify evidence/source-availability types are an extension contract, not a
working automatic profiling feature. Live tests of additional library/playlist
scopes, extended sources and recent/general controls are deferred until written
policy approval. The active flow does not request those scopes. Spotify's scope
upgrade must remain cancellable without discarding an existing grant when that
feature is later approved.

Before broad release: finish human evaluation, inspect bias/coverage/cost, add
per-account server spending quotas, and complete live device/Spotify acceptance.

### Verified implementation run

Debug and Release simulator builds passed. The production Swift account-store
race test confirmed that an old account's delayed response cannot overwrite a
new account's preferences and sign-out clears memory. The setup sheet's fields,
Save and Skip controls were inspected in the simulator without saving synthetic
preferences to the real account.

A signed-in Supabase v2 request for “chill melodic US hiphop” with synthetic
explicit preferences returned 26 accepted, 34 rejected candidates; accepted
candidates did not include SICKO MODE. This is one live model response, not a
human quality score. Two temporary accounts verified preference/feedback RLS,
playlist ownership, invalid/anonymous token rejection and invalid-body rejection.
Cleanup query confirmed zero remaining synthetic users/playlists. Function v5
adds propagation of upstream Retry-After (covered by an offline regression).
Real-account UI end-to-end acceptance awaits sign-in; human evaluation remains
0/300 positions and blind preference results are pending.

### Read-only Spotify access diagnostic — 3 November 2026

Profile now offers `Allow read access & test`. This optional OAuth upgrade adds
user-top-read, user-read-recently-played, user-library-read,
playlist-read-private and playlist-read-collaborative. Normal sign-in does not
request these scopes. Cancelling an upgrade preserves the previous grant.

After consent, a bounded diagnostic requests up to ten items from each top-item
period/type, recent plays, liked tracks and playlists, then tests one owned or
collaborative playlist found in that first page. UI shows counts/status only;
response payloads are transient and are neither persisted nor supplied to AI or
the recommendation pipeline. A missing eligible playlist in this sample is
labelled untested, not empty. The automatic-analysis approval gate stays false.

### Local Spotify ranking experiment — 3 November 2026

At the user's explicit request, Debug now enables `spotifyLocalExperiment` after
OAuth read consent. This supersedes the earlier default-off development behavior;
`spotifyAnalysisApproved` remains false and no policy approval is claimed. Release
keeps the experiment off. `disableSpotifyLocalExperiment` disables it in Debug.

The snapshot is in memory for one deck and cleared on cancel/rebuild. It preserves
source/window/rank and available recent timestamp/context. Bounded reads: first
50 top tracks and artists for each of three periods, 50 recent plays, 50 saved
tracks, first 50 playlists and up to five owned/collaborative playlists with 50
items each. Recent playlist contexts prioritize those five. This is a sample, not
a complete history or complete playlist scan. Unsupported/failed sources are
marked partial; total failure requires an explicit retry or brief-only choice.

Local affinity uses rank-discounted short/medium/long signals (0.90/0.85/0.80),
recent plays (0.75), saved tracks (0.55) and playlist membership (0.35). A per-source
maximum prevents a large playlist from dominating. Track matches score more than
artist-only matches; cross-source support adds a bounded bonus. These are initial
heuristics, not learned/measured listening probabilities. Saved and playlist items
alone do not establish that a track was heard.

The existing quality gate stays first. Only accepted model candidates are ranked
locally; model inputs remain the brief and explicitly entered preferences. With
both sources, personal score is 80% local Spotify affinity and 20% explicit-profile
score; otherwise the available source is used. Familiar-track target remains a
separate control. Initial decks and refills use the same snapshot. No Spotify
payload or derived preference enters Claude or the preference database.

Important limitation: the app does not inject Spotify library tracks into the AI
candidate generator. A checked pool with no Spotify matches can still have no
personalization effect; the deck explicitly reports this. This is not yet a sonic
similarity model for unheard artists. Human quality gates remain pending.

Debug build and policy/ranking/deck/transport/account-isolation checks passed.
Additional checks cover local ranking without manual preferences, bounded source
contribution, no off-brief rescue, and explicit failure when history is unavailable.
Real-account end-to-end ranking verification awaits renewed app sign-in after
installing the updated simulator build; earlier read-only endpoint tests passed.

### November 3: recent-release diagnosis and small verified decks

The server anchors relative release windows to today's UTC calendar date and
reports only aggregate rejection counts by dimension/verdict. A live 60-candidate
run for US hiphop + chill + releases in the last two years accepted only 2;
44 candidates had uncertain era evidence and 43 uncertain energy evidence
(counts overlap). Date anchoring does not solve missing current-release knowledge.
The user explicitly removed the Recent requirement for this test. A new live run
for US hiphop + chill accepted 43/60, rejecting 17. These are model assessments,
not human quality ratings or verified playable-card counts.

When fewer than eight playable cards survive, the app offers an explicit choice
to listen to the smaller verified selection. It never relaxes the brief, starts
that small deck automatically, or repeatedly refills it. Production deck tests
cover a two-card selection and verify that accepting it adds no refill request.
Recommendation tests and the Debug simulator build passed. Installed on iPhone
17 Pro; the app shows sign-in, so real-account playback/ranking still needs login.

### November 3: preserve personalized ordering

User reported unfamiliar artists dominating later cards. The resolver was
randomizing ranked candidates into artist buckets after personal ranking. V2 now
preserves rank, moving only adjacent same-artist repeats; legacy ordering remains
unchanged. A Spotify-only personal refill with zero matching candidates stops
further automatic refills and explains the shortage, instead of appending an
entirely unmatched batch. Explicit-profile recommendations remain independent.
Tests cover resolved first-card personal rank, stable artist spacing and seam,
and zero-match refill termination without repeated requests. The initial pool
can still contain unmatched discoveries: this change is not a similarity model
and does not achieve the requested familiar-track proportion by itself.

### November 3: reference-driven candidate retrieval and personal admission

The current v2 server parses the brief in a separate model call that never sees
preferences. Retrieval then combines explicit example songs, other songs by
reference artists and discoveries with track-level musical similarities to those
references. User-entered `Artist — Song` examples are inserted deterministically
into the bounded review pool; they receive exactly the same admission checks.
The independent reviewer compares production, delivery, melody and mood against
named reference IDs. Personal mode with positive references requires taste >=0.6,
a valid matching reference and no reported conflicting reference. Unsupported or
invented reference IDs cannot satisfy admission. This is a model judgment, not
measured audio similarity, and human evaluation remains mandatory.

V2 accepts optional `mode` and `session` fields, preserving old clients. Session
context contains only original model-generated artist/title pairs, bounded to 80
excluded entries and 10 explicit keep/dislike/off_brief feedback entries. Resolved
Spotify metadata, listening duration, library or history are never encoded in
this context. Skips do not produce negative preferences. Off-brief persistence
now includes refinements in the context key. Session feedback guides subsequent
retrieval; it is not a cross-session learned embedding or imported taste profile.

The client resolves the bounded pool before selecting the final playable deck.
Familiarity quotas are applied after preview failures and account for preceding
batches. Explicit example identities, known feedback and the sampled listening
history identify familiar tracks. Unknown remains unknown. Artist caps and stable
spacing remain enforced. Counts in the UI describe the actual deck, not just a
candidate pool. With both explicit references and the experimental Spotify
snapshot, explicit musical comparisons carry 75% of the taste component and
local snapshot matches 25%; the mode weight remains separate.

Spotify-only personal mode now admits only candidates with a snapshot match,
so it cannot silently fill its tail with unrelated artists. This restricted
experiment is not a discovery similarity model; the UI directs the user to add
references for recommendations beyond those artists. No new Spotify-derived data
is sent to AI, no policy approval is claimed, and Release rollout remains off.

Live deployed v7 test: synthetic profile (Isaiah Rashad — 4r Da Squaw, Mac Miller —
Small Worlds, Saba — Photosynthesis; warm mellow production) with chill US hiphop
returned 26 unique accepted songs and 31 rejected. All accepted entries had
passing explicit constraints and a valid personal comparison. The isolated brief
contained only the requested hiphop/chill/US scene and its interpretations.
Temporary-account authentication, RLS isolation and cleanup passed (0 test users,
0 test playlists left). This test is not the user's preference profile or proof
of perceived personalization. `personal-smoke-2026-11-03.csv` has blank human
rating columns for this synthetic test; no human pass is claimed.

Deterministic tests cover personal admission, invented references, seeded off-
brief rejection, session exclusions, source validation, actual client request
encoding, rank preservation, Spotify-only exhaustion, familiar quota continuity,
account isolation and cancellation. The opt-in `run-live-preview.sh <batch.json>`
harness exercises production iTunes/Deezer exact matching and preview reachability;
it does not substitute for Spotify resolution or human listening evaluation.
