#!/usr/bin/env bash
# Commit stage (cheap tier, B6): a staged user-docs page (under
# project.user_docs_root; nothing to do when it is empty) must carry a
# lastVerified date that is not older than the page's last landed change on
# origin/main and not later than tomorrow (UTC, the docs-lint clock). Keyed to
# the page's own history, not to today: a bump made yesterday holds, a page
# dated behind its landed history is exactly the page to re-verify. Pages under
# _stubs/, pages without the field, README/SUMMARY and pure renames are exempt.
# Silent on pass. Cost <1 s.
# Standalone: bash .claude/hooks/gates/user-docs-freshness.sh < payload.json
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload
is_git_commit_command || exit 0
[ "$HOOK_RAW" = yes ] && {
  echo "❌ User-docs freshness gate: the hook payload is unreadable (jq missing or malformed JSON), so the tree this commit is for is unknown. Fix that and retry." >&2
  exit 2
}
[ -n "${TOP:-}" ] || TOP=$(repo_top) || {
  echo "❌ User-docs freshness gate: cannot resolve the repository this commit runs in (${HOOK_GIT_DIR:-${HOOK_CWD:-?}}). Use a plain absolute path, or run the commit from inside the repo." >&2
  exit 2
}
is_project_repo "$TOP" || exit 0
cd "$TOP" || exit 2
ROOT=$HOOK_CFG_USER_DOCS_ROOT
[ -n "$ROOT" ] || exit 0

staged_paths "$TOP" ACMR
pages=()
for f in "${STAGED[@]}"; do
  case $f in "$ROOT"/_stubs/*) ;; "$ROOT"/*.md) pages+=("$f") ;; esac
done
[ ${#pages[@]} -eq 0 ] && exit 0
hook_remedy "git log -1 --format=%cs origin/main -- ${pages[*]}"

# A pure rename (100 % similar) carries its date unchanged.
renamed=$(git diff --cached -M100% --diff-filter=R --name-status -z | tr '\0' '\n' | awk 'NR % 3 == 0')

TODAY=$(date -u +%F)
TOMORROW=$(date -u -d "$TODAY + 1 day" +%F)
problems=''
for p in "${pages[@]}"; do
  printf '%s\n' "$renamed" | grep -qxF -- "$p" && continue
  # The field in the frontmatter of the staged content, quoted or not.
  lv=$(git show ":$p" 2>/dev/null | awk '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^lastVerified:[[:space:]]*"?[0-9]{4}-[0-9]{2}-[0-9]{2}"?[[:space:]]*$/ { s = $0; sub(/^lastVerified:[[:space:]]*"?/, "", s); print substr(s, 1, 10); exit }')
  [ -n "$lv" ] || continue
  landed=$(git log -1 --format=%cs origin/main -- "$p" 2>/dev/null)
  from=${landed:-any date}
  if [ -n "$landed" ] && [[ $lv < $landed ]]; then
    problems+="  \`$p\`: lastVerified $lv is older than the page's last landed change ($landed); set it to a date in [$from, $TODAY]: the page you touched is the page you verified"$'\n'
  elif [[ $lv > $TOMORROW ]]; then
    problems+="  \`$p\`: lastVerified $lv is in the future (today is $TODAY UTC); set it to a date in [$from, $TODAY]"$'\n'
  fi
done
[ -z "$problems" ] && exit 0
{
  echo "❌ User-docs freshness gate. Fix the lastVerified date, restage the page, then retry:"
  printf '%s' "$problems"
} >&2
exit 2
