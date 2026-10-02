#!/usr/bin/env bash
# PreToolUse hook (Bash matcher), the only one. Reads the payload once, classifies
# the command into {commit, push, pr-open}, refuses the combined commit shapes
# (B15) and runs the stages in gates/ under one clock (B16). A command in no
# class exits 0 at once and spawns nothing.
#
# Fail closed (B4): a stage that is missing, exits anything but 0 or 2, or is
# killed at its budget blocks the command. The cheap tier runs to completion and
# reports every failure in one block; from deps-smoke on, the first block stops
# the chain. Tests: scripts/hooks.test.sh (scripts/hooks.test.d/20-dispatcher.sh).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
GATES=${HOOK_GATES_DIR:-$HERE/gates}
DEADLINE=${HOOK_DEADLINE:-840}
T0=$SECONDS

hook_read_payload
classify_command || exit 0

TOP=$(repo_top) || TOP=''
# Read once here and exported: no stage starts node for the config again.
if ! hook_config; then
  printf '❌ Blocked: cannot read .claude/review-map.yml, so the gates cannot run.\n\n  node scripts/review-map.mjs check\n' >&2
  exit 2
fi
CWD_TOP=$(git -C "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --show-toplevel 2>/dev/null) || CWD_TOP=''
# The stage contract: hook_read_payload returns at once on these, stdin is /dev/null.
export HOOK_PAYLOAD_SET=1 HOOK_CMD HOOK_CWD HOOK_FILE HOOK_RAW HOOK_GIT_DIR HOOK_CLASSES TOP

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
MESSAGES=''

# B10: a session in one checkout operating another tree would run the skills
# against the wrong tree.
hint() {
  [ -n "$TOP" ] && [ "$TOP" != "$CWD_TOP" ] || return 0
  printf '\nskills must run with the shell inside %s (cd %s)\n' "$TOP" "$TOP"
}
block() {
  { printf '%s\n' "$@"; hint; } >&2
  exit 2
}

# The command to run by hand when a stage is killed: the stage's own REMEDY
# line on fd 3 when it printed one, else this table.
remedy() {
  local r
  r=$(grep '^REMEDY: ' "$SCRATCH/remedy" 2>/dev/null | tail -1 | sed 's/^REMEDY: //')
  [ -n "$r" ] && { printf '%s' "$r"; return; }
  case $1 in
    coauthor) printf 'git log -1 --format=%%B | grep -i claude' ;;
    secret-block) printf 'git diff --cached -U0 --diff-filter=ACMR | grep -nE "password|secret|token|PRIVATE KEY"' ;;
    docs-gate) printf 'bash scripts/obligations.sh' ;;
    user-docs-freshness) printf 'git log -1 --format=%%cs origin/main -- <page>' ;;
    deps-smoke) cfg_lines DEPS_CHECK | paste -sd'&' - | sed 's/&/ \&\& /g' ;;
    typecheck-lint) printf 'pnpm typecheck && pnpm exec eslint <staged files>' ;;
    tests) printf 'bash scripts/test-changed.sh <staged files>' ;;
    push) printf 'git push --dry-run --porcelain <args> && bash scripts/ai-review.sh verify' ;;
    pr-open) printf 'bash scripts/ai-review.sh check' ;;
    *) printf 'bash .claude/hooks/gates/%s.sh' "$1" ;;
  esac
}

# run_stage NAME BUDGET → STAGE_RC (0 pass, 2 block, 124 timed out, else crash)
# and STAGE_ERR, the text to relay. Budget = min(BUDGET, what is left of DEADLINE).
run_stage() {
  local name=$1 budget=$2 f="$GATES/$1.sh" remaining rc err out
  STAGE_RC=0 STAGE_ERR=''
  if [ ! -f "$f" ]; then
    STAGE_RC=1
    STAGE_ERR="gate missing: $name ($f). Restore it (git checkout -- .claude/hooks/gates) and retry."
    return
  fi
  remaining=$((DEADLINE - (SECONDS - T0)))
  [ "$budget" -le "$remaining" ] || budget=$remaining
  if [ "$budget" -lt 1 ]; then
    STAGE_RC=124
    STAGE_ERR="gate timed out in $name after 0s (the ${DEADLINE}s deadline is spent). Run it yourself: $(remedy "$name"), then retry."
    return
  fi
  : >"$SCRATCH/remedy"; : >"$SCRATCH/out"
  err=$(HOOK_STAGE=$name HOOK_STAGE_BUDGET=$budget \
    timeout --foreground -k 5 "$budget" bash "$f" </dev/null 3>"$SCRATCH/remedy" 2>&1 >"$SCRATCH/out")
  rc=$?
  case $rc in
    0)
      # A passing stage may hand the operator a systemMessage on stdout.
      out=$(jq -r 'objects | .systemMessage? | strings' "$SCRATCH/out" 2>/dev/null) || out=''
      [ -n "$out" ] && MESSAGES="${MESSAGES:+$MESSAGES$'\n'}$out"
      ;;
    2) STAGE_RC=2; STAGE_ERR=$err ;;
    124|137) STAGE_RC=124; STAGE_ERR="gate timed out in $name after ${budget}s. Run it yourself: $(remedy "$name"), then retry." ;;
    *) STAGE_RC=$rc; STAGE_ERR="gate crashed: $name rc=$rc"${err:+$'\n'"$err"} ;;
  esac
}

if in_class commit; then
  if ! reason=$(refuse_combined_commit_shape); then
    block "❌ Commit blocked: $reason"
  fi
  failures=''; count=0
  for s in coauthor secret-block docs-gate user-docs-freshness; do
    run_stage "$s" 30
    [ "$STAGE_RC" = 0 ] && continue
    count=$((count + 1))
    failures="${failures}--- $s ---"$'\n'"$STAGE_ERR"$'\n'$'\n'
  done
  [ -z "$failures" ] || block "❌ Commit blocked by $count gate(s):" "" "$failures"
  run_stage deps-smoke 150;       [ "$STAGE_RC" = 0 ] || block "$STAGE_ERR"
  run_stage typecheck-lint 180;   [ "$STAGE_RC" = 0 ] || block "$STAGE_ERR"
  run_stage tests "$DEADLINE";    [ "$STAGE_RC" = 0 ] || block "$STAGE_ERR"
fi
if in_class push; then
  run_stage push 60; [ "$STAGE_RC" = 0 ] || block "$STAGE_ERR"
fi
if in_class pr-open; then
  run_stage pr-open 60; [ "$STAGE_RC" = 0 ] || block "$STAGE_ERR"
fi

[ -z "$MESSAGES" ] || jq -n --arg m "$MESSAGES" '{systemMessage: $m}'
exit 0
