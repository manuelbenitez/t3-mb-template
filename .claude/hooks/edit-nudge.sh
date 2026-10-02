#!/usr/bin/env bash
# PostToolUse hook (Edit|Write), B12: one systemMessage per edited file per
# session naming what the review map attaches to it: the skills to run before
# the PR, the internal-docs page and the user-docs area. Once per file per
# session via
# <state>/nudged/<session_id>/<sha1 of path> (pruned after 7 days at
# SessionStart). A nudge, not a gate: anything unreadable exits 0 in silence.
# Tests: scripts/hooks.test.d/50-evidence.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
hook_read_payload
[ "$HOOK_RAW" = no ] && [ -n "$HOOK_FILE" ] || exit 0
SESSION=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id? | strings' 2>/dev/null)
SESSION=$(hook_slug "${SESSION:-no-session}")

DIR=$(dirname "$HOOK_FILE")
[ -d "$DIR" ] || exit 0
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
is_project_repo "$TOP" || exit 0
ABS="$(cd "$DIR" && pwd -P)/$(basename "$HOOK_FILE")"
REL=${ABS#"$TOP"/}
[ "$REL" != "$ABS" ] || exit 0

MATCH=$(map_query match "$REL" 2>/dev/null) || exit 0
[ "$(printf '%s' "$MATCH" | jq -r '.paths[] | .rules | length')" -gt 0 ] || exit 0

STATE=$(state_dir "$TOP") || exit 0
MARK="$STATE/nudged/$SESSION/$(printf '%s' "$REL" | sha1sum | cut -d' ' -f1)"
[ ! -f "$MARK" ] || exit 0
mkdir -p "$(dirname "$MARK")" && : >"$MARK"

SKILLS=$(printf '%s' "$MATCH" | jq -r '.skills as $s | .paths[] | .skills | map(select($s[.].trigger_only | not)) | map("/" + .) | join(", ")')
TRIGGER=$(printf '%s' "$MATCH" | jq -r '.skills as $s | .paths[] | .skills | map(select($s[.].trigger_only)) | map("/" + .) | join(", ")')
IDOCS=$(printf '%s' "$MATCH" | jq -r --arg r "$HOOK_CFG_INTERNAL_DOCS_ROOT/" '.paths[] | .internal_docs | map($r + .) | join(", ")')
UDOCS=$(printf '%s' "$MATCH" | jq -r --arg r "$HOOK_CFG_USER_DOCS_ROOT/" '.paths[] | .user_docs | map($r + .) | join(", ")')

MSG="$REL:"
[ -z "$SKILLS" ] || MSG="$MSG skills before the PR: $SKILLS."
[ -z "$TRIGGER" ] || MSG="$MSG Trigger-only (run when their When applies): $TRIGGER."
[ -z "$IDOCS" ] || MSG="$MSG Internal-docs page for the same commit: $IDOCS."
[ -z "$UDOCS" ] || MSG="$MSG User docs: $UDOCS (or a 'User-Docs: none' trailer)."
jq -n --arg m "$MSG" '{systemMessage: $m}'
