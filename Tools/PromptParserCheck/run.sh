#!/bin/bash
# Compiles the real PromptParser.swift against a small harness and runs it.
#
#   ./Tools/PromptParserCheck/run.sh
#
# Uses Swipelist/Config.swift for credentials when it exists (the same file the
# app uses). Otherwise falls back to a temporary shim reading ANTHROPIC_API_KEY
# from the environment, so the offline fixture checks still run on a fresh clone.
#
# Lives outside Swipelist/ on purpose: that folder is a filesystem-synchronized
# Xcode group, so a main.swift in there would be compiled into the app target.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

if [ -f "$root/Swipelist/Config.swift" ]; then
  config="$root/Swipelist/Config.swift"
  echo "Credentials: Swipelist/Config.swift"
else
  config="$out/Config.swift"
  cat > "$config" <<'EOF'
import Foundation
enum Secrets {
    static let anthropicAPIKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    static let lastFMAPIKey = ProcessInfo.processInfo.environment["LASTFM_API_KEY"] ?? ""
}
EOF
  echo "Credentials: environment (Swipelist/Config.swift not found)"
fi
echo

swiftc -D DEBUG \
  "$config" \
  "$root/Swipelist/Services/TrackCandidate.swift" \
  "$root/Swipelist/Services/PromptParser.swift" \
  "$root/Tools/PromptParserCheck/main.swift" \
  -o "$out/promptparsercheck"

"$out/promptparsercheck"
