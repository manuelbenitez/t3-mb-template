#!/usr/bin/env bash
# Commit stage (cheap tier, B19): block a commit whose staged diff ADDS a
# credential literal, a private key or a JWT. Narrower than the on-edit nudge
# (secret-scan.sh): a value of 12+ characters with no whitespace, lines that
# read config or are documented examples are skipped, and the exemption list
# is shared through secret_exempt_path in lib.sh. Silent on pass. Cost <1 s.
# Standalone: bash .claude/hooks/gates/secret-block.sh < payload.json
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload
is_git_commit_command || exit 0
[ "$HOOK_RAW" = yes ] && {
  echo "❌ Secret gate: the hook payload is unreadable (jq missing or malformed JSON), so the tree this commit is for is unknown. Fix that and retry." >&2
  exit 2
}
[ -n "${TOP:-}" ] || TOP=$(repo_top) || {
  echo "❌ Secret gate: cannot resolve the repository this commit runs in (${HOOK_GIT_DIR:-${HOOK_CWD:-?}}). Use a plain absolute path, or run the commit from inside the repo." >&2
  exit 2
}
is_project_repo "$TOP" || exit 0
cd "$TOP" || exit 2
hook_remedy 'git diff --cached -U0 --diff-filter=ACMR | grep -nE "password|secret|token|PRIVATE KEY"'

staged_paths "$TOP" ACMR
scan=()
for f in "${STAGED[@]}"; do secret_exempt_path "$f" || scan+=("$f"); done
[ ${#scan[@]} -eq 0 ] && exit 0

# Added lines only, as "path<TAB>line<TAB>text" rows.
rows=$(git -c diff.noprefix=false -c diff.mnemonicPrefix=false diff --cached -U0 --no-color --no-ext-diff --diff-filter=ACMR -- "${scan[@]}" |
  awk '
    /^\+\+\+ "?b\// { p = substr($0, 5); sub(/^"/, "", p); sub(/"$/, "", p); sub(/^b\//, "", p); next }
    /^--- / || /^-/ { next }
    /^@@ / { match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
    /^\+/ { printf "%s\t%d\t%s\n", p, n, substr($0, 2); n++; next }
    /^ / { n++ }')
[ -n "$rows" ] || exit 0

TEXT=$'^[^\t]*\t[0-9]+\t.*' # the text field of a row
CRED="(password|passwd|api_key|apikey|secret|client_secret|token|private_key)[[:space:]]*[:=][[:space:]]*[\"'][^\"'[:space:]]{12,}[\"']"
# Read from config, documented as an example, or a truncated Swagger example.
CRED_SKIP="process\\.env|config\\.|\\$\\{|example|@ApiProperty|placeholder|\\.\\.\\.[\"']|…[\"']"
hits=''
h=$(printf '%s\n' "$rows" | grep -iE "$TEXT$CRED" | grep -viE "$CRED_SKIP" || true)
[ -n "$h" ] && hits+="credential literal:"$'\n'"$h"$'\n'
h=$(printf '%s\n' "$rows" | grep -E "${TEXT}BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY" || true)
[ -n "$h" ] && hits+="private key:"$'\n'"$h"$'\n'
h=$(printf '%s\n' "$rows" | grep -E $'^[^\t]*\\.(ts|tsx|js|jsx)\t' |
  grep -E "${TEXT}eyJ[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{20,}" || true)
[ -n "$h" ] && hits+="JWT literal in source:"$'\n'"$h"$'\n'
[ -z "$hits" ] && exit 0

{
  echo "❌ Secret gate: the staged diff adds what looks like a secret. Move it to an env var (.env, never committed; add the name to .env.example), restage, then retry:"
  printf '%s' "$hits" | awk -F'\t' 'NF < 3 { print; next } { printf "  %s:%s  %s\n", $1, $2, $3 }'
} >&2
exit 2
