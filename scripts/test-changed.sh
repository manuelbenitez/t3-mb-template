#!/usr/bin/env bash
# Runs the tests related to a set of changed files. Shared by the commit hook
# and the CI test job, so both enforce the same thing: a file that changes has
# its tests run. Paths are repo-relative, given as arguments. Each path goes to
# its workspace (project.workspaces in .claude/review-map.yml) and runs
# `vitest related` there; a change in packages/* also runs the related tests of
# every app that imports it. Exits non-zero if any suite fails.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=../.claude/hooks/lib.sh
. .claude/hooks/lib.sh
hook_config || { echo "test-changed: cannot read .claude/review-map.yml (node scripts/review-map.mjs check)" >&2; exit 1; }

declare -A related=()
aireview=no hooks=no reviewmap=no
add() { related[$1]="${related[$1]:-}"$'\n'"$2"; }
for f in "$@"; do
  [ -f "$f" ] || continue # deleted paths have nothing to run
  case "$f" in
    # The map feeds the hooks: its reader, its fixtures and the map itself run
    # the map checks and the hook harness (listed before the *.yml skip).
    scripts/review-map.mjs|.claude/review-map.yml) reviewmap=yes; hooks=yes; continue ;;
    scripts/review-map.test.mjs) reviewmap=yes; continue ;;
    *.md|*.json|*.yml|*.yaml) continue ;;
    scripts/ai-review.sh|scripts/ai-review.test.sh) aireview=yes; continue ;;
    .claude/hooks/*|scripts/hooks.test.sh|scripts/hooks.test.d/*) hooks=yes; continue ;;
  esac
  while IFS=$'\t' read -r dir _; do
    [ -n "$dir" ] || continue
    case "$f" in "$dir"/*) ;; *) continue ;; esac
    add "$dir" "${f#"$dir"/}"
    # A shared package: its consumers' related tests as well.
    case "$dir" in packages/*)
      while IFS=$'\t' read -r app _; do
        case "$app" in apps/*) add "$app" "../../$f" ;; esac
      done < <(cfg_lines WORKSPACES) ;;
    esac
  done < <(cfg_lines WORKSPACES)
done

rc=0
run() { echo "→ $*" >&2; "$@" >&2 || rc=1; }
for dir in "${!related[@]}"; do
  mapfile -t files < <(printf '%s\n' "${related[$dir]}" | grep -v '^$' | sort -u)
  [ ${#files[@]} -gt 0 ] || continue
  [ -f "$dir/package.json" ] && grep -q '"vitest"' "$dir/package.json" || continue
  run pnpm -C "$dir" exec vitest related --run --passWithNoTests "${files[@]}"
done
[ "$hooks" = yes ] && run bash scripts/hooks.test.sh
[ "$aireview" = yes ] && run bash scripts/ai-review.test.sh
[ "$reviewmap" = yes ] && { run node scripts/review-map.test.mjs; run node scripts/review-map.mjs check; }
exit $rc
