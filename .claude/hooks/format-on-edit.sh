#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): prettier --write and eslint --fix on the edited
# file, then feedback for Claude from that same eslint run
# (internal-docs/conventions/code-style.md):
#   - jsdoc/* errors left after the fix: {"decision":"block"} naming each one,
#     so the JSDoc is written in the same turn rather than at commit time;
#   - `//` comments the edit added: additionalContext asking to keep only a why.
# Silent otherwise. Fails open: the commit gate's eslint is the backstop.
# One script, not two hooks: matching PostToolUse hooks run in parallel, and a
# second eslint pass would race this one's --fix write.
# Tests: scripts/hooks.test.d/60-format-on-edit.sh.
set -u
command -v jq >/dev/null || exit 0

INPUT=$(cat)
f=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -n "$f" ] && [ -f "$f" ] || exit 0

PROJECT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
case "$f" in
  "$PROJECT"/*) ;;
  *) exit 0 ;;
esac
case "$f" in
  *node_modules/*|*/dist/*|*/.next/*|*/.turbo/*|*/.cache/*) exit 0 ;;
esac
cd "$PROJECT" || exit 0
rel="${f#"$PROJECT"/}"

case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.md|*.mdx|*.yaml|*.yml|*.css|*.scss|*.html)
    pnpm exec prettier --write --log-level warn "$f" >/dev/null 2>&1 || true
    ;;
esac

# ESLint runs from the file's own package: each package owns its config.
case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) ;;
  *) exit 0 ;;
esac
pkg=$(printf '%s' "$rel" | grep -oE '^(apps|packages|tooling)/[^/]+')
[ -n "$pkg" ] && ls "$pkg"/eslint.config.* >/dev/null 2>&1 || exit 0

REPORT=$(cd "$pkg" && pnpm exec eslint --fix --no-warn-ignored --format json "${rel#"$pkg"/}" 2>/dev/null)
JSDOC=$(printf '%s' "$REPORT" | jq -r '
  .[0].messages[]?
  | select(.severity == 2 and ((.ruleId // "") | startswith("jsdoc/")))
  | "  \(.line):\(.column) \(.message) (\(.ruleId))"' 2>/dev/null | head -20)

# A line comment or a trailing one; `///`, a URL's `://` and lint or type
# directives are not counted.
count_comments() {
  grep -E '(^|[[:space:]])//([[:space:]]|$)' | grep -vcE '//[[:space:]]*(eslint-|@ts-|prettier-ignore)' || true
}
NEW=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null | count_comments)
OLD=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null | count_comments)
ADDED=$((${NEW:-0} - ${OLD:-0}))

NOTE=""
if [ "$ADDED" -gt 0 ]; then
  NOTE="$rel: this edit adds $ADDED \`//\` comment(s). Keep one only for a why the code cannot say (an ordering, an outside constraint, a workaround); what the code does belongs in its names and its JSDoc (internal-docs/conventions/code-style.md)."
fi

if [ -n "$JSDOC" ]; then
  REASON="$rel: JSDoc missing or incomplete. Add it now (internal-docs/conventions/code-style.md):"$'\n'"$JSDOC"
  [ -z "$NOTE" ] || REASON="$REASON"$'\n'"$NOTE"
  jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
elif [ -n "$NOTE" ]; then
  jq -n --arg c "$NOTE" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
fi
exit 0
