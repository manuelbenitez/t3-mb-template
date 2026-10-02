#!/usr/bin/env bash
# The by-hand half of the dependency smoke (B9, pr-open tier): runs
# project.deps_smoke (by default: build the API and boot it against an
# in-memory MongoDB), then writes the marker the pr-open gate wants when
# the branch changed a manifest (<state>/deps/<deps_key>, under the common git
# dir, so every worktree of the checkout shares it). The commit-time half
# (.claude/hooks/gates/deps-smoke.sh) never builds or boots.
#
#   bash scripts/deps-smoke.sh            from inside the checkout it should attest
#   DEPS_SMOKE_ALLOW_DEV=1 ...            when the dev API may keep running (see below)
#
# The build rewrites apps/api/dist, so the script refuses while something
# listens on the API port (PORT, default 3001) unless DEPS_SMOKE_ALLOW_DEV=1.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../.claude/hooks/lib.sh"

die() { printf '%s\n' "$@" >&2; exit 1; }
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "deps-smoke: run it from inside a checkout of this project (cd <TOP>)."
is_project_repo "$TOP" || die "deps-smoke: $TOP is not a checkout of this project (see project.repo in .claude/review-map.yml)."
cd "$TOP" || exit 1

# The marker attests HEAD's manifests, so they must be what is on disk.
DIRTY=$(git status --porcelain --untracked-files=no | awk '{ print $NF }' |
  grep -E '^(pnpm-lock\.yaml|pnpm-workspace\.yaml|(.*/)?package\.json)$' || true)
[ -z "$DIRTY" ] || die "deps-smoke: a manifest is modified but not committed; the marker attests HEAD, so commit it first (git status), then retry:" "$(printf '%s\n' "$DIRTY" | sed 's/^/  /')"

# From the environment, then the root .env (the API's own order).
env_value() { grep -E "^$1=" .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

API_PORT=${PORT:-$(env_value PORT)}
[ -n "$API_PORT" ] || API_PORT=3001
if timeout 1 bash -c "</dev/tcp/127.0.0.1/$API_PORT" 2>/dev/null && [ "${DEPS_SMOKE_ALLOW_DEV:-}" != 1 ]; then
  die "deps-smoke: something listens on :$API_PORT (the dev API?). The build deletes and rebuilds apps/api/dist under it." \
    "Stop it, or run: DEPS_SMOKE_ALLOW_DEV=1 bash scripts/deps-smoke.sh"
fi

K0=$(deps_key "$TOP" HEAD)
run() {
  echo "deps-smoke: $1"
  bash -c "$1" || die "deps-smoke: failed at: $1" "No marker written. Fix it, then retry: bash scripts/deps-smoke.sh"
}
while IFS= read -r c; do
  [ -n "$c" ] && run "$c"
done < <(cfg_lines DEPS_SMOKE)

K1=$(deps_key "$TOP" HEAD)
[ "$K1" = "$K0" ] || die "deps-smoke: HEAD's manifests changed during the run; no marker written. Retry: bash scripts/deps-smoke.sh"
STATE=$(state_dir "$TOP") || die "deps-smoke: cannot resolve the git common dir of $TOP."
mkdir -p "$STATE/deps" && printf '%s %s\n' "$(git rev-parse HEAD)" "$(date -u +%FT%TZ)" >"$STATE/deps/$K1" ||
  die "deps-smoke: cannot write the marker under $STATE/deps."
echo "deps-smoke: passed; marker $STATE/deps/$K1"
