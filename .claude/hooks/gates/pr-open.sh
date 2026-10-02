#!/usr/bin/env bash
# pr-open stage of bash-gate.sh, also runnable on its own: block opening a PR on
# this project until the evidence for HEAD is in place. In order: the
# refusals (a command that moves HEAD, changes directory or points the PR
# elsewhere), the lifecycle-suite marker when the branch touches a lifecycle
# path (B7), the dependency-smoke marker when it touches a manifest (B9), then
# `ai-review.sh check` (the mark). On pass it writes <state>/pr-open/<slug>, the
# push gate's offline "a PR exists" cache. Silent on pass, fails CLOSED on error.
# Tests: scripts/ai-review.test.sh, scripts/hooks.test.d/50-evidence.sh.
#
# Matching is textual, so it catches the honest shapes and the careless ones, not
# a determined bypass (`$GH pr create`, a browser-opened PR). The control that
# holds at merge time is the `ai-review` commit status as a required check (see
# internal-docs/runbooks/local-gates.md).
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload
SCRIPT="$(cd "$(dirname "$0")/../../.." && pwd)/scripts/ai-review.sh"

block() {
  printf '%s\n' "$@" >&2
  exit 2
}

# Fail closed: if jq is missing or the payload is not the shape we expect,
# hook_read_payload matches the raw payload rather than letting the command through.
[ -n "$HOOK_CMD" ] || exit 0
opens_pr_command || exit 0
hook_remedy "bash scripts/ai-review.sh check"

has() { printf '%s' "$NORM" | grep -qEi -- "$1"; }

# The hook sees HEAD as it is NOW. A command that also moves HEAD would be
# checked against the wrong commit.
if has '(^|[^[:alnum:]_-])git[[:space:]](.*[[:space:]])?(commit|rebase|reset|cherry-pick|revert|merge|pull|am|switch|checkout|stash)([[:space:]]|$)' ||
  has '--amend'; then
  block "❌ PR blocked: this command moves HEAD (commit, merge, pull, …) AND opens the PR." \
    "" \
    "The review check reads HEAD before the command runs, so the PR would open on" \
    "a commit no review has seen. Run that first, then /review, then open the PR alone."
fi

# The check covers one repo and one HEAD: the directory the command runs in.
if has '(^|[;&|(][[:space:]]*)(cd|pushd)[[:space:]]'; then
  block "❌ PR blocked: the command changes directory before opening the PR." \
    "" \
    "The review check covers the directory the command starts in. Run the PR" \
    "command on its own, from the repo it is for."
fi
if has '(^|[[:space:]])(-H|--head|-R|--repo)([[:space:]=]|$)'; then
  block "❌ PR blocked: --head / --repo point the PR somewhere the review check did not look." \
    "" \
    "Check the branch out and open the PR from it, in its own repo."
fi

# The PR is for the tree the command starts in (a `cd` was refused above), so
# the cwd's toplevel is the one that counts, whatever tree a push half named.
DIR=${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) ||
  block "❌ PR blocked: '$DIR' is not a git repo, so no review can be checked."

# This gate is this project's. A PR for another repo is that repo's business.
is_project_repo "$TOP" || exit 0
cd "$TOP" || block "❌ PR blocked: cannot enter $TOP."

[ -f "$SCRIPT" ] ||
  block "❌ PR blocked: $SCRIPT is missing, so no review can be verified."
STATE=$(state_dir "$TOP") ||
  block "❌ PR blocked: cannot resolve the git common dir of $TOP, so no marker can be read."
git rev-parse -q --verify origin/main >/dev/null 2>&1 ||
  block "❌ PR blocked: no origin/main ref, so the branch's changes are unknown." \
    "" \
    "  git fetch origin main"

# B7 / B9: the markers the user-run suites leave, keyed to what each suite can
# see (lifecycle_key, deps_key), so docs and portal commits keep them.
changed_paths origin/main...HEAD
if [ ${#CHANGED[@]} -gt 0 ]; then
  MATCH=$(map_query match "${CHANGED[@]}" 2>/dev/null) ||
    block "❌ PR blocked: cannot read the review map, so the lifecycle paths are unknown." \
      "" \
      "  node scripts/review-map.mjs check"
  LIFE=$(printf '%s' "$MATCH" | jq -r '.paths | to_entries[] | select(.value.lifecycle) | .key' | head -3 | paste -sd, - | sed 's/,/, /g')
  if [ -n "$LIFE" ]; then
    KEY=$(lifecycle_key "$TOP" HEAD)
    [ -f "$STATE/lifecycle/$KEY" ] ||
      block "❌ PR blocked: this branch changes lifecycle paths ($LIFE) and the lifecycle suite has not passed on this tree." \
        "" \
        "  bash scripts/lifecycle-suite.sh" \
        "" \
        "It runs project.lifecycle_suite and writes the marker keyed to HEAD's" \
        "project.lifecycle_inputs trees; a commit outside them keeps it."
  fi
  MANIFEST=''
  for p in "${CHANGED[@]}"; do
    case $p in
      pnpm-lock.yaml|pnpm-workspace.yaml|package.json|*/package.json) MANIFEST="${MANIFEST:+$MANIFEST, }$p" ;;
    esac
  done
  if [ -n "$MANIFEST" ]; then
    KEY=$(deps_key "$TOP" HEAD)
    [ -f "$STATE/deps/$KEY" ] ||
      block "❌ PR blocked: this branch changes a dependency manifest ($MANIFEST) and the dependency smoke has not passed on this tree." \
        "" \
        "  bash scripts/deps-smoke.sh" \
        "" \
        "It runs project.deps_smoke (build and boot), then writes the marker for" \
        "HEAD's lockfile, workspace file and package.json files."
  fi
fi

if CLAUDE_PROJECT_DIR=$TOP bash "$SCRIPT" check; then
  # The offline cache the push gate reads when gh cannot answer (B8). Pruned at
  # SessionStart once the branch is gone (B17).
  if BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null) && [ -n "$BRANCH" ]; then
    mkdir -p "$STATE/pr-open" && date -u +%Y-%m-%dT%H:%M:%SZ >"$STATE/pr-open/$(hook_slug "$BRANCH")"
  fi
  exit 0
fi

SHA=$(git rev-parse --short HEAD 2>/dev/null) || SHA="(no HEAD)"
block "❌ PR blocked: no clean AI review recorded for $SHA ($TOP)." \
  "" \
  "  1. /review                    (plus any skill bash scripts/obligations.sh names)" \
  "  2. fix what it finds, commit, and review again: the mark names one commit" \
  "  3. bash scripts/ai-review.sh mark [summary-file]" \
  "" \
  "Step 3 verifies gstack's review log against the review map for exactly this commit" \
  "(bash scripts/ai-review.sh verify shows the same result without touching the network)," \
  "posts the 'ai-review' status main needs, then writes the mark."
