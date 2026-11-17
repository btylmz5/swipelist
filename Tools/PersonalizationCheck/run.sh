#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc "$root/Swipelist/Services/TrackCandidate.swift" \
  "$root/Swipelist/Services/ListeningHistory.swift" \
  "$root/Tools/PersonalizationCheck/main.swift" -o "$out/check"
"$out/check"
# The old history-based DeckHarness is superseded by the v2 production-deck checks.
bash "$root/Tools/RecommendationCheck/run.sh"
