#!/bin/bash
# Thin wrapper over the Supabase Management API.
#
#   ./Tools/supabase/sb.sh sql "select 1;"          # inline SQL
#   ./Tools/supabase/sb.sh file path/to.sql          # SQL from a file
#   ./Tools/supabase/sb.sh projects                  # sanity check the token
#
# Reads the token from .supabase-token (gitignored). A custom User-Agent is set
# because Cloudflare rejects the default python/urllib signature with error 1010.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
token="$(cat "$root/.supabase-token")"
ref="${SUPABASE_PROJECT_REF:-kvvqgptmdsjbpdysteks}"
api="https://api.supabase.com/v1"

case "${1:-}" in
  projects)
    curl -s -H "Authorization: Bearer $token" -H "User-Agent: curl/8.7.1" "$api/projects"
    ;;
  sql|file)
    if [ "$1" = "file" ]; then
      payload=$(python3 -c 'import json,sys; print(json.dumps({"query": open(sys.argv[1]).read()}))' "$2")
    else
      payload=$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$2")
    fi
    printf '%s' "$payload" > /tmp/sb_query.json
    curl -s -X POST "$api/projects/$ref/database/query" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -H "User-Agent: curl/8.7.1" \
      --data-binary @/tmp/sb_query.json
    ;;
  *)
    echo "usage: sb.sh {sql <query> | file <path> | projects}" >&2
    exit 1
    ;;
esac
