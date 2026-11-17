#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
node "$root/Tools/SuggestionFunctionCheck/check.mjs"
swiftc "$root/Swipelist/Services/ListeningHistory.swift" "$root/Swipelist/Services/RecommendationPolicy.swift" "$root/Swipelist/Services/TrackCandidate.swift" "$root/Swipelist/Services/SongSuggestionService.swift" "$root/Tools/SuggestionFunctionCheck/ClientCheck.swift" -o "$out/client-check"
"$out/client-check"
