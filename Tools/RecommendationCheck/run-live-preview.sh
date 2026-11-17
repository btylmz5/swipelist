#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc "$root/Swipelist/Services/TrackCandidate.swift" "$root/Swipelist/Services/ListeningHistory.swift" "$root/Swipelist/Services/RecommendationPolicy.swift" "$root/Swipelist/Services/ITunesService.swift" "$root/Swipelist/Services/DeezerService.swift" "$root/Tools/RecommendationCheck/LivePreviewCheck.swift" -o "$out/preview"
"$out/preview" "$1"
