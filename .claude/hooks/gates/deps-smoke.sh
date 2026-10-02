#!/usr/bin/env bash
# Commit stage (B9, commit tier): when a staged path is pnpm-lock.yaml,
# pnpm-workspace.yaml or a package.json, run project.deps_check in order (by
# default: the lockfile against the manifests without writing node_modules,
# then typecheck). Blocks on the first failure naming the command. Nothing here
# installs, builds or boots: that half runs by hand before the PR
# (scripts/deps-smoke.sh, project.deps_smoke).
# Runs under the dispatcher or alone on a piped payload.
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload

is_git_commit_command || exit 0
# Fail closed: with no readable payload there is no cwd, so the tree this
# commit is for is unknown. A clean session root must not stand in for it.
[ "$HOOK_RAW" = yes ] && {
  echo "❌ Dependency smoke: the hook payload is unreadable (jq missing or malformed JSON), so the tree this commit is for is unknown. Fix that and retry." >&2
  exit 2
}
[ "${HOOK_PAYLOAD_SET:-}" = 1 ] && [ -n "${TOP:-}" ] || TOP=$(repo_top) || {
  echo "❌ Dependency smoke: cannot resolve the repository this commit runs in (${HOOK_GIT_DIR:-${HOOK_CWD:-?}}). Use a plain absolute path, or run the commit from inside the repo." >&2
  exit 2
}
is_project_repo "$TOP" || exit 0
cd "$TOP" || exit 2

# Every staged manifest, deletions included: a removed package.json changes the lockfile too.
staged_paths "$TOP" ''
MANIFESTS=()
for f in "${STAGED[@]}"; do
  case $f in
    pnpm-lock.yaml|pnpm-workspace.yaml|package.json|*/package.json) MANIFESTS+=("$f") ;;
  esac
done
[ ${#MANIFESTS[@]} -eq 0 ] && exit 0
hook_config || { echo "❌ Dependency smoke: cannot read .claude/review-map.yml (node scripts/review-map.mjs check)." >&2; exit 2; }
hook_remedy "$(cfg_lines DEPS_CHECK | paste -sd'&' - | sed 's/&/ \&\& /g')"

step() {
  local out
  out=$(bash -c "$1" 2>&1) && return 0
  {
    echo "❌ Dependency smoke failed (staged: ${MANIFESTS[*]}) at: $1"
    echo ""
    printf '%s\n' "$out" | tail -40
    echo ""
    echo "Fix it (a lockfile behind the manifests: pnpm install, then stage pnpm-lock.yaml), or run it yourself: $1, then retry."
  } >&2
  exit 2
}
while IFS= read -r c; do
  [ -n "$c" ] && step "$c"
done < <(cfg_lines DEPS_CHECK)
exit 0
