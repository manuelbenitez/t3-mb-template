#!/usr/bin/env bash
# PostToolUse hook: flag newly-written secrets in source code.
# Tier 1: silent unless a pattern hits.
set -u
. "$(dirname "$0")/lib.sh"

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[ -z "$f" ] && exit 0
[ -f "$f" ] || exit 0

# The exemption list is shared with the commit gate (secret_exempt_path, B19).
secret_exempt_path "$f" && exit 0

hits=""
# Password literals: password: "xxxxxxxx" or password="xxxxxxxx"
h=$(grep -nE "(password|api_key|apikey|secret|token)\s*[:=]\s*[\"'][^\"']{8,}[\"']" "$f" 2>/dev/null | grep -viE "(process\.env|config\.|\\\$\{)" || true)
[ -n "$h" ] && hits+=$'\n'"credential literal:"$'\n'"$h"

# Private keys
h=$(grep -nE "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY" "$f" 2>/dev/null || true)
[ -n "$h" ] && hits+=$'\n'"private key:"$'\n'"$h"

# JWT-shaped tokens in source (not .env)
case "$f" in
  *.ts|*.tsx|*.js|*.jsx)
    h=$(grep -nE "eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}" "$f" 2>/dev/null || true)
    [ -n "$h" ] && hits+=$'\n'"JWT literal in source:"$'\n'"$h"
    ;;
esac

[ -z "$hits" ] && exit 0

jq -n --arg file "$f" --arg hits "$hits" \
  '{systemMessage: ("🔒 Possible secret in " + $file + ". Move to env var or .env.local:" + $hits)}'
