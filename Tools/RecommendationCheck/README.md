# Recommendation v2 acceptance

Run `bash Tools/RecommendationCheck/run.sh` for deterministic production policy,
server handler and production DeckBuilder checks. No credentials required.
The SICKO MODE fixture tests rejection of an assessed energy conflict despite a
favorite artist. It does not claim a mock has measured musical quality.

`briefs.json` contains 30 real evaluation briefs. For each, capture the first ten
playable candidates from the v2 pipeline. A human must listen and label the
corresponding rows in `human-ratings.csv`: candidate_id, rater, fits_brief (yes/no),
violated_condition and notes. Missing judgments are never successes.

For blind comparison, use the same brief and explicit profile with baseline and
v2; randomize A/B presentation and hide the mapping from participants until they
have chosen. Record decoded choices (v2/baseline/tie) in `blind-preference.csv`.
Require at least three independent participants and a majority preferring v2.
Run `python3 Tools/RecommendationCheck/score.py` to report gate status.

Release remains brief-only until >=90% human fit and the preference gate pass.
Debug enables v2; set `disableRecommendationV2` in the app's UserDefaults to roll
back to the labelled brief-only route. Spotify analysis has a separate compile-
time approval gate, currently false. Do not enable it as a consequence of passing
these quality tests; it requires separate written policy approval and live API
capability tests.
