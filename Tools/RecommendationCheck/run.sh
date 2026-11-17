#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
node "$root/Tools/RecommendationCheck/server.mjs"
swiftc "$root/Swipelist/Services/TrackCandidate.swift" "$root/Swipelist/Services/ListeningHistory.swift" "$root/Swipelist/Services/RecommendationPolicy.swift" "$root/Tools/RecommendationCheck/CoreCheck.swift" -o "$out/core"
"$out/core"
swiftc -D DEBUG -parse-as-library "$root/Swipelist/Services/TrackCandidate.swift" "$root/Swipelist/Services/ListeningHistory.swift" "$root/Swipelist/Services/RecommendationPolicy.swift" "$root/Swipelist/Services/DeckBuilder.swift" "$root/Tools/RecommendationCheck/DeckCheck.swift" -o "$out/deck"
"$out/deck"
swiftc -parse-as-library "$root/Swipelist/Services/TrackCandidate.swift" "$root/Swipelist/Services/ListeningHistory.swift" "$root/Swipelist/Services/RecommendationPolicy.swift" "$root/Swipelist/Services/PreferenceStore.swift" "$root/Tools/RecommendationCheck/StoreCheck.swift" -o "$out/store"
"$out/store"
