#!/usr/bin/env bash
# B10: obligation memory, computed from the tree and the review log, never
# stored. For the checkout of $PWD it prints the branch, the changed paths vs
# the local origin/main, the review evidence each required name has (the same
# evaluation as `ai-review.sh verify`), the docs pages the review map expects,
# and the ai-review, lifecycle and deps marker status. Nothing on main.
# Network-free, < 1 s.
#
#   bash scripts/obligations.sh
#
# The SessionStart hook (.claude/hooks/obligations-context.sh) injects this as
# context; bash-gate.sh names it in a timeout remedy.
set -u
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../.claude/hooks/lib.sh
. "$SCRIPT_DIR/../.claude/hooks/lib.sh"

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$TOP" || exit 0
is_project_repo "$TOP" || exit 0
BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null) || BRANCH=''
[ "$BRANCH" != main ] || exit 0
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null) || exit 0
if ! git rev-parse -q --verify origin/main >/dev/null 2>&1; then
  echo "Branch: ${BRANCH:-(detached HEAD)} at ${HEAD_SHA:0:8}. No origin/main ref, so the obligations are unknown: git fetch origin main"
  exit 0
fi

list() { printf '%s\n' "$1" | head -"${2:-8}" | sed 's/^/  - /'; n=$(printf '%s\n' "$1" | grep -c .); [ "$n" -le "${2:-8}" ] || echo "  … +$((n - ${2:-8})) more"; }

echo "Branch: ${BRANCH:-(detached HEAD)} at ${HEAD_SHA:0:8} ($TOP)"
if P2=$(git rev-parse -q --verify HEAD^2 2>/dev/null) && git merge-base --is-ancestor "$P2" origin/main 2>/dev/null; then
  echo "HEAD merges main; the merged code is new to this branch: run /review on it (carry-over does not apply to merges)"
fi

changed_paths origin/main...HEAD
echo "Changed vs origin/main: ${#CHANGED[@]} path(s)"
MATCH='{"paths":{}}'
if [ ${#CHANGED[@]} -gt 0 ]; then
  list "$(printf '%s\n' "${CHANGED[@]}")"
  MATCH=$(map_query match "${CHANGED[@]}" 2>/dev/null) ||
    { echo "The review map cannot be read (node scripts/review-map.mjs check), so the skills and pages are unknown."; MATCH='{"paths":{}}'; }
fi

echo "Review evidence (bash scripts/ai-review.sh verify):"
if OUT=$(CLAUDE_PROJECT_DIR=$TOP bash "$SCRIPT_DIR/ai-review.sh" verify 2>&1); then :; fi
printf '%s\n' "$OUT" | grep -v '^   Run \|^   ✗ ' | sed 's/^/  /'

IDOCS=$(printf '%s' "$MATCH" | jq -r --arg r "$HOOK_CFG_INTERNAL_DOCS_ROOT/" '[.paths[].internal_docs[]] | unique | map($r + .) | join(", ")')
UDOCS=$(printf '%s' "$MATCH" | jq -r --arg r "$HOOK_CFG_USER_DOCS_ROOT/" '[.paths[].user_docs[]] | unique | map($r + .) | join(", ")')
[ -z "$IDOCS" ] || echo "Internal docs expected in the same change: $IDOCS"
[ -z "$UDOCS" ] || echo "User docs expected (or a 'User-Docs: none' trailer): $UDOCS"

STATE=$(state_dir "$TOP") || STATE=''
if [ -n "$STATE" ]; then
  [ -f "${STATE%/*}/ai-review/$HEAD_SHA" ] && M="✓ marked" || M="✗ not marked (bash scripts/ai-review.sh mark, after verify passes)"
  echo "ai-review mark for ${HEAD_SHA:0:8}: $M"
  if printf '%s' "$MATCH" | jq -e '[.paths[].lifecycle] | any' >/dev/null 2>&1; then
    [ -f "$STATE/lifecycle/$(lifecycle_key "$TOP" HEAD)" ] && M="✓ present for this tree" || M="✗ missing for this tree (bash scripts/lifecycle-suite.sh)"
    echo "lifecycle marker (a lifecycle path changed): $M"
  else
    echo "lifecycle marker: not needed (no lifecycle path changed)"
  fi
  NEEDS_DEPS=no
  for p in "${CHANGED[@]-}"; do
    case $p in pnpm-lock.yaml|pnpm-workspace.yaml|package.json|*/package.json) NEEDS_DEPS=yes ;; esac
  done
  if [ "$NEEDS_DEPS" = yes ]; then
    [ -f "$STATE/deps/$(deps_key "$TOP" HEAD)" ] && M="✓ present for these manifests" || M="✗ missing for these manifests (bash scripts/deps-smoke.sh)"
    echo "deps marker (a manifest changed): $M"
  else
    echo "deps marker: not needed (no manifest changed)"
  fi
fi
exit 0
