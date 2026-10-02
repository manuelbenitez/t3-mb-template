#!/usr/bin/env bash
# Commit stage (cheap tier): on `git commit`, block when
#   1. a staged path has a docs area (project.docs_pairs in the review map) and
#      nothing under that area is staged in the same commit, or
#   2. a staged path is user-visible (project.user_visible) and nothing under
#      project.user_docs_root is staged and the message carries no
#      `User-Docs: none — <reason>` trailer (a reused message, --amend
#      --no-edit or -C, is read from that commit).
# project.docs_exempt (tests, stories) needs neither. The pages it suggests are
# the rules' internal_docs for those paths. Silent on pass.
# Standalone: bash .claude/hooks/gates/docs-gate.sh < payload.json
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload
is_git_commit_command || exit 0
# Fail closed: with no readable payload there is no cwd, so the tree this
# commit is for is unknown; a clean session root must not stand in for it.
[ "$HOOK_RAW" = yes ] && {
  echo "❌ Docs commit gate: the hook payload is unreadable (jq missing or malformed JSON), so the tree this commit is for is unknown. Fix that and retry." >&2
  exit 2
}

# The tree the commit is for: `git -C` / `cd` in the command, else the payload
# cwd; never the session root, which from a worktree is the wrong index.
[ -n "${TOP:-}" ] || TOP=$(repo_top) || {
  echo "❌ Docs commit gate: cannot resolve the repository this commit runs in (${HOOK_GIT_DIR:-${HOOK_CWD:-?}}). Use a plain absolute path, or run the commit from inside the repo." >&2
  exit 2
}
is_project_repo "$TOP" || exit 0
cd "$TOP" || exit 2
hook_remedy 'bash scripts/obligations.sh'

staged_paths "$TOP" '' # every status: a deleted page or file counts here
[ ${#STAGED[@]} -eq 0 ] && exit 0

MATCH=$(map_query match "${STAGED[@]}" 2>/dev/null) || {
  echo "❌ Docs commit gate: cannot read the review map, so the docs each path needs are unknown: node scripts/review-map.mjs check" >&2
  exit 2
}

staged_under() { # staged_under <prefix>: 0 when a staged path starts with it
  local p
  for p in "${STAGED[@]}"; do case $p in "$1"*) return 0 ;; esac; done
  return 1
}

# The pages the map names for these paths, one bullet each, else FALLBACK.
suggest() { # suggest <internal_docs|user_docs> <prefix> <fallback> <newline-separated paths>
  local pages
  pages=$(printf '%s' "$MATCH" | jq -r --arg k "$1" --arg ps "$4" '
    ($ps | split("\n") | map(select(. != ""))) as $want
    | [.paths | to_entries[] | select(.key as $p | $want | index($p)) | .value[$k][]] | unique | .[]' 2>/dev/null)
  if [ -n "$pages" ]; then
    printf '%s\n' "$pages" | sed "s|^|  • $2|"
  else
    echo "  • $3"
  fi
}

problems=""
# 1. Each docs area a staged path needs, unless something under it is staged.
while IFS=$'\t' read -r area paths; do
  [ -n "$area" ] || continue
  staged_under "$area" && continue
  paths=${paths//$'\x1f'/$'\n'}
  problems+="Code is staged without a change under $area. Update and stage:"$'\n'
  problems+="$(suggest internal_docs "$HOOK_CFG_INTERNAL_DOCS_ROOT/" "${area}README.md (find the page for this area)" "$paths")"$'\n'
  problems+="  (for $(printf '%s\n' "$paths" | head -3 | paste -sd, - | sed 's/,/, /g'))"$'\n'$'\n'
done < <(printf '%s' "$MATCH" | jq -r '
  [.paths | to_entries[] | select(.value.docs_area != null) | {a: .value.docs_area, p: .key}]
  | group_by(.a)[] | "\(.[0].a)\t\(map(.p) | join("\u001f"))"')

# 2. User-visible paths, when the project keeps user docs.
UDOCS=$HOOK_CFG_USER_DOCS_ROOT
if [ -n "$UDOCS" ]; then
  USER_VISIBLE=$(printf '%s' "$MATCH" | jq -r '.paths | to_entries[] | select(.value.user_visible) | .key')
  if [ -n "$USER_VISIBLE" ] && ! staged_under "$UDOCS/"; then
    commit_message_from_command
    if ! printf '%s\n' "$MESSAGE" | grep -qiE 'User-Docs:[[:space:]]*none[[:space:]]*[^[:alnum:][:space:]"'"'"';&|)]+[[:space:]]*[[:alnum:]]'; then
      problems+="User-visible code is staged without a user docs change. Update and stage:"$'\n'
      problems+="$(suggest user_docs "$UDOCS/" "$UDOCS/ (find the page for this feature)" "$USER_VISIBLE")"$'\n'
      problems+="Or, if nothing a user sees or reads changed, say why in the commit message:"$'\n'"  User-Docs: none — <reason>"$'\n'$'\n'
    fi
  fi
fi

[ -z "$problems" ] && exit 0
{ echo "❌ Docs commit gate. Fix before committing:"; echo; printf '%s' "$problems"; } >&2
exit 2
