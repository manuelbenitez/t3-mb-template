#!/usr/bin/env bash
# SessionStart hook (every source: startup, resume, clear, compact): inject the
# branch's obligations (scripts/obligations.sh, B10) as additionalContext when
# the checkout is this project and the branch is not main. First it prunes
# the state markers that have gone stale (B17): nudged/<session> older than
# 7 days and pr-open/<slug> for a branch that no longer exists.
# Tests: scripts/hooks.test.d/50-evidence.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
hook_read_payload

TOP=$(repo_top) || exit 0
[ -n "$TOP" ] && is_project_repo "$TOP" || exit 0

if STATE=$(state_dir "$TOP") && [ -d "$STATE" ]; then
  [ ! -d "$STATE/nudged" ] || find "$STATE/nudged" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
  if [ -d "$STATE/pr-open" ]; then
    LIVE=$(git -C "$TOP" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | while IFS= read -r b; do hook_slug "$b"; echo; done)
    for f in "$STATE/pr-open"/*; do
      [ -f "$f" ] || continue
      printf '%s\n' "$LIVE" | grep -qxF -- "$(basename "$f")" || rm -f "$f"
    done
  fi
fi

OUT=$(cd "$TOP" && timeout 20 bash "$HERE/../../scripts/obligations.sh" 2>/dev/null) || OUT=''
[ -n "$OUT" ] || exit 0
CTX="Obligations for this branch (computed from .claude/review-map.yml and gstack's review log; re-run any time: bash scripts/obligations.sh):
$OUT"
jq -n --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
