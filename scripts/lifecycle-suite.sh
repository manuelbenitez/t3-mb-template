#!/usr/bin/env bash
# The lifecycle suite (B7): project.lifecycle_suite (by default the API's e2e
# specs), run by hand before a PR that touches a lifecycle path, then a marker
# keyed to what the suite can see (lifecycle_key: HEAD's project.lifecycle_inputs
# tree ids) under <state>/lifecycle/<key>, shared by every worktree of the
# checkout. The pr-open gate blocks when the branch touches a lifecycle path and
# HEAD's key has no marker; commits outside those trees keep it.
#
#   bash scripts/lifecycle-suite.sh       from inside the checkout it should attest
#
# Refuses on a dirty tracked tree (the marker attests HEAD) and when /tmp has
# under 4 GiB free (each spec starts its own mongodb-memory-server, which puts
# its dbpaths under os.tmpdir()), so TMPDIR is pointed at a private directory
# under /tmp that is removed on exit.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../.claude/hooks/lib.sh"

die() { printf '%s\n' "$@" >&2; exit 1; }
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "lifecycle-suite: run it from inside a checkout of this project (cd <TOP>)."
is_project_repo "$TOP" || die "lifecycle-suite: $TOP is not a checkout of this project (see project.repo in .claude/review-map.yml)."
cd "$TOP" || exit 1

DIRTY=$(git status --porcelain --untracked-files=no)
[ -z "$DIRTY" ] || die "lifecycle-suite: the tracked tree is dirty; the marker attests HEAD, so commit or stash first (git stash), then retry:" \
  "$(printf '%s\n' "$DIRTY" | head -10 | sed 's/^/  /')"

AVAIL_KB=$(df --output=avail /tmp 2>/dev/null | tail -1 | tr -d ' ')
case $AVAIL_KB in
  ''|*[!0-9]*) die "lifecycle-suite: cannot read the free space under /tmp (df --output=avail /tmp)." ;;
esac
[ "$AVAIL_KB" -ge 4194304 ] ||
  die "lifecycle-suite: only $((AVAIL_KB / 1024)) MiB free under /tmp; the suite's mongo-mem dbpaths need 4 GiB. Free it (ls /tmp; rm -rf /tmp/mongo-mem-*) and retry."

K0=$(lifecycle_key "$TOP" HEAD)
WORK=$(mktemp -d /tmp/lifecycle-suite.XXXXXX) || die "lifecycle-suite: cannot create a directory under /tmp."
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
export TMPDIR=$WORK
export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=4096"

echo "lifecycle-suite: HEAD $(git rev-parse --short HEAD), key ${K0:0:12}: $HOOK_CFG_LIFECYCLE_SUITE (dbpaths under $WORK)"
T0=$SECONDS
bash -c "$HOOK_CFG_LIFECYCLE_SUITE"
RC=$?
ELAPSED=$((SECONDS - T0))
[ "$RC" -eq 0 ] || die "lifecycle-suite: the suite failed (rc=$RC) after ${ELAPSED}s; no marker written. Fix it, then retry: bash scripts/lifecycle-suite.sh"

# What was attested must still be what is here.
K1=$(lifecycle_key "$TOP" HEAD)
DIRTY=$(git status --porcelain --untracked-files=no)
if [ "$K1" != "$K0" ] || [ -n "$DIRTY" ]; then
  die "lifecycle-suite: the tree changed during the run (${ELAPSED}s); no marker written:" \
    "$(printf '%s\n' "$DIRTY" | head -10 | sed 's/^/  /')" \
    "Commit or discard the change (git status), then retry: bash scripts/lifecycle-suite.sh"
fi
STATE=$(state_dir "$TOP") || die "lifecycle-suite: cannot resolve the git common dir of $TOP."
mkdir -p "$STATE/lifecycle" && printf '%s %s %ss\n' "$(git rev-parse HEAD)" "$(date -u +%FT%TZ)" "$ELAPSED" >"$STATE/lifecycle/$K1" ||
  die "lifecycle-suite: cannot write the marker under $STATE/lifecycle."
echo "lifecycle-suite: passed in ${ELAPSED}s; marker $STATE/lifecycle/$K1"
