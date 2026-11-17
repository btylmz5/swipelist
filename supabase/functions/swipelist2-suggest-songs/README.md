# Swipelist2 Claude suggestions

Entrypoint: `index.ts`; model: `claude-sonnet-5-5`.

The default iOS curator calls this function in Debug and Release. Keep the slug
separate from `swipelist3-suggest-songs` and the legacy `suggest-songs` function.

Server configuration:
- Supabase supplies `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- Set `SWIPELIST2_ANTHROPIC_API_KEY` using Supabase project secrets, never source.
- Deploy this directory under slug `swipelist2-suggest-songs` with `verify_jwt=true`.
- The handler also checks the bearer token with Auth `/user` and rejects
  anonymous accounts before making an Anthropic request.

The body contains mandatory `text`, `count` (1–60), optional `refinements`,
`liked`, `skipped`, and `excludeArtists`. Feedback is limited to ten items per
list; no Spotify listening-history snapshot is sent. Successful responses are
`{ "model": "claude-sonnet-5-5", "songs": [{"artist":"…","track":"…"}] }`.

Run offline checks from the project root:

```sh
bash Tools/SuggestionFunctionCheck/run.sh
```

Live verified 2026-10-30: authenticated request returned 52 unique suggestions;
anonymous/invalid tokens rejected, malformed count rejected. Deployment is not
proof of catalogue accuracy or Spotify access. Per-user quotas and spending
controls remain required before a wider release.

## v2

Deploy BOTH index.ts and quality.ts. The v2 client allowlists user-entered
preferences; history, resolved provider metadata and audio are not request fields.
Generation extracts constraints; a second phase independently evaluates candidates
in batches of 15. There is no unfiltered fallback. Model judgments are qualitative,
not measured audio features. A 60-candidate batch can make five Anthropic calls;
account-level spending controls are still required before broad release.

Database migrations 0004 and 0005 add user-scoped preference/feedback storage.
See PERSONALIZATION.md and Tools/RecommendationCheck/README.md for rollout gates.
