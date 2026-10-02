#!/usr/bin/env bash
# Stop hook (asyncRewake): run workspace typecheck if any TS files changed in working tree.
# Tier 2: exits 0 silently on pass; exits 2 with output on failure to wake the model.
set -u
. "$(dirname "$0")/lib.sh"
hook_read_payload

# The tree the session works in: the payload cwd — never the session root,
# which from a worktree is the wrong working tree.
TOP=$(repo_top) || exit 0
is_project_repo "$TOP" || exit 0
cd "$TOP" || exit 0

# Any TS/TSX files dirty (staged or unstaged) vs HEAD?
CHANGED=$(git diff --name-only HEAD 2>/dev/null | grep -E '\.(ts|tsx)$' || true)
[ -z "$CHANGED" ] && exit 0

# The affected workspaces (project.workspaces), so unaffected packages are skipped.
AFFECTED=()
while IFS=$'\t' read -r dir pkg; do
  [ -n "$dir" ] && echo "$CHANGED" | grep -q "^$dir/" && AFFECTED+=("$pkg")
done < <(cfg_lines WORKSPACES)

# Fallback: if the change is outside a known workspace, use full typecheck
if [ ${#AFFECTED[@]} -eq 0 ]; then
  OUT=$(pnpm typecheck 2>&1)
  RC=$?
else
  OUT=""
  RC=0
  for ws in "${AFFECTED[@]}"; do
    WS_OUT=$(pnpm --filter "$ws" typecheck 2>&1)
    WS_RC=$?
    if [ $WS_RC -ne 0 ]; then
      RC=$WS_RC
      OUT+=$'\n--- '$ws$' ---\n'"$WS_OUT"
    fi
  done
fi

[ $RC -eq 0 ] && exit 0

printf 'typecheck FAILED on working-tree changes\n\n%s\n' "$(echo "$OUT" | tail -80)"
exit 2
