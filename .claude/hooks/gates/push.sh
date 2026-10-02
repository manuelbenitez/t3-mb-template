#!/usr/bin/env bash
# push stage of bash-gate.sh (B8), also runnable on its own. Decided from git's
# own dry run, never from refspec text. In order: refusals that need no network
# (a command that also moves HEAD, a many-refs push), the remote (another repo
# is not this gate's business), `git push --dry-run --porcelain <the push's own
# arguments>`, then per porcelain line: main is landed by PR, a delete is free,
# a forced update needs --force-with-lease, and a ref with an open PR needs
# review evidence for the sha git would push (`ai-review.sh verify`, log-side,
# no network). Silent on pass, fails CLOSED on error.
# Tests: scripts/hooks.test.d/50-evidence.sh. Bypasses: internal-docs/runbooks/local-gates.md.
# Pushes from another repository (is_project_repo) are left alone.
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload
SCRIPT="$(cd "$(dirname "$0")/../../.." && pwd)/scripts/ai-review.sh"
BUDGET=${HOOK_STAGE_BUDGET:-60}
GH_TIMEOUT=${HOOK_GH_TIMEOUT:-5}
DRY_TIMEOUT=20
[ "$DRY_TIMEOUT" -le $((BUDGET / 2)) ] || DRY_TIMEOUT=$((BUDGET / 2 > 0 ? BUDGET / 2 : 1))

NOTES=''
note() { NOTES="${NOTES:+$NOTES$'\n'}$1"; }
block() {
  { printf '%s\n' "$@"; [ -z "$NOTES" ] || printf '\n%s\n' "$NOTES"; } >&2
  exit 2
}

[ -n "$HOOK_CMD" ] || exit 0
is_git_push_command || exit 0

# (a) The gate judges the sha git would push as HEAD is NOW. A command that also
# moves HEAD would push a commit no gate has seen.
if [[ $NORM =~ ${_GIT_RE}(commit|merge|rebase|reset|cherry-pick|revert|pull|am|switch|checkout|stash)([^[:alnum:]_.-]|$) ]] ||
  [[ $NORM == *--amend* ]]; then
  block "❌ Push blocked: this command also moves HEAD (commit, merge, rebase, pull, …) and pushes." \
    "" \
    "commit first, then push alone: the gate reads the sha git would push before the command runs."
fi

# The push's own arguments: the tokens after `git … push` up to ; & | ) or a
# comment, quotes stripped, redirections and --dry-run/--porcelain dropped
# (they are re-added below). Read from JOINED so quoted refspecs survive.
PUSH_ARGS=()
if [[ $JOINED =~ ${_GIT_RE}push([[:space:]]|$) ]]; then
  rest=${JOINED#*"${BASH_REMATCH[0]}"}
  rest=${rest%%[;\&|)]*}
  for tok in $rest; do
    case $tok in '#'*) break ;; esac
    tok=${tok//\"/}; tok=${tok//\'/}
    case $tok in
      ''|--dry-run|--porcelain|-n) continue ;;
      [0-9]*[\<\>]*|[\<\>]*) continue ;;
    esac
    PUSH_ARGS+=("$tok")
  done
fi
hook_remedy "git push --dry-run --porcelain ${PUSH_ARGS[*]-} && bash scripts/ai-review.sh verify"

# (b) One ref per push: the rules below are per ref, and --all/--mirror carry main.
for tok in "${PUSH_ARGS[@]}"; do
  case $tok in
    --all|--mirror|--prune)
      block "❌ Push blocked: '$tok' pushes many refs at once." \
        "" \
        "push one ref: git push origin <branch>" ;;
  esac
done

[ -n "${TOP:-}" ] || TOP=$(repo_top) || TOP=''
[ -n "$TOP" ] ||
  block "❌ Push blocked: cannot tell which tree the push acts on (${HOOK_GIT_DIR:-${HOOK_CWD:-the cwd}} is not a git repo)."
cd "$TOP" || block "❌ Push blocked: cannot enter $TOP."

# This gate is this project's. A push from another repo is that repo's business.
is_project_repo "$TOP" || exit 0

# The dry run tells what would be pushed: flag, from:to, summary per line.
ERR=$(mktemp); trap 'rm -f "$ERR"' EXIT
OUT=$(timeout "$DRY_TIMEOUT" git push --dry-run --porcelain "${PUSH_ARGS[@]}" 2>"$ERR"); RC=$?
if [ "$RC" != 0 ]; then
  [ "$RC" = 124 ] && GITSAYS="the dry run timed out after ${DRY_TIMEOUT}s" || GITSAYS=$(grep -v '^hint:' "$ERR" | sed 's/^/  /')
  block "❌ Push blocked: cannot tell what would be pushed (git push --dry-run --porcelain ${PUSH_ARGS[*]-} failed, rc=$RC):" \
    "$GITSAYS" \
    "" \
    "Fix what git reports, then push again."
fi

LEASE=no FORCE_OK=no
for tok in "${PUSH_ARGS[@]}"; do
  case $tok in --force-with-lease|--force-with-lease=*|--force-if-includes) LEASE=yes ;; esac
done
# The prefix form only: `HOOK_ALLOW_FORCE_PUSH=1 git push -f …` or `env … git push`.
# An `export …;` or a comment that mentions the name does not count.
printf '%s' "$JOINED" | grep -qE '(^|[;&|(][[:space:]]*)(env[[:space:]]+)?HOOK_ALLOW_FORCE_PUSH=1[[:space:]]+.*git[[:space:]].*push' && FORCE_OK=yes

STATE=$(state_dir "$TOP") || STATE=''
while IFS=$'\t' read -r FLAG REFS SUMMARY; do
  case $REFS in *:*) ;; *) continue ;; esac
  FROM=${REFS%%:*}; TO=${REFS#*:}
  TO_SHORT=${TO#refs/heads/}
  [ "$TO_SHORT" != main ] ||
    block "❌ Push blocked: this would push $FROM to main ($SUMMARY)." \
      "" \
      "main is landed by PR: push the branch, open the PR, merge it there."
  case $FLAG in
    '=') continue ;;
    '-') continue ;;
    '!') block "❌ Push blocked: git would reject $REFS ($SUMMARY). Fix what git reports, then push again." ;;
    '+')
      if [ "$LEASE" = no ] && [ "$FORCE_OK" = no ]; then
        block "❌ Push blocked: this would force-update $TO_SHORT ($SUMMARY), rewriting the remote branch." \
          "" \
          "use --force-with-lease (or --force-if-includes): git push --force-with-lease origin $TO_SHORT" \
          "so only a remote tip you have already seen is overwritten."
      fi ;;
  esac

  # A ref with an open PR needs review evidence for the sha git would push, never HEAD.
  HAS_PR=no PR_LABEL="a PR"
  PRS=$(timeout "$GH_TIMEOUT" gh pr list --head "$TO_SHORT" --state open --json number 2>/dev/null); GH_RC=$?
  if [ "$GH_RC" = 0 ]; then
    N=$(printf '%s' "$PRS" | jq -r 'if type == "array" and length > 0 then .[0].number else empty end' 2>/dev/null) || N=''
    [ -n "$N" ] && { HAS_PR=yes; PR_LABEL="PR #$N"; }
  else
    [ "$GH_RC" = 124 ] && WHY="gh timed out after ${GH_TIMEOUT}s" || WHY="gh failed, rc=$GH_RC"
    if [ -n "$STATE" ] && [ -f "$STATE/pr-open/$(hook_slug "$TO_SHORT")" ]; then
      HAS_PR=yes
      note "could not confirm whether a PR exists for $TO_SHORT ($WHY): proceeding on the local pr-open marker, which says one does"
    else
      note "could not confirm whether a PR exists for $TO_SHORT ($WHY): proceeding as if none does (no local pr-open marker)"
    fi
  fi
  [ "$HAS_PR" = yes ] || continue

  if [ -n "$FROM" ]; then
    SHA=$(git rev-parse --verify -q "$FROM^{commit}" 2>/dev/null) ||
      block "❌ Push blocked: cannot resolve '$FROM', the source of the push to $TO_SHORT, so its review evidence cannot be checked."
  else
    continue
  fi
  VERIFY=$(CLAUDE_PROJECT_DIR=$TOP bash "$SCRIPT" verify "$SHA" 2>&1 >/dev/null) && continue
  block "❌ Push blocked: $PR_LABEL is open for $TO_SHORT and ${SHA:0:8} (what git would push) lacks review evidence." \
    "" \
    "$VERIFY" \
    "" \
    "  1. /review, plus each skill named above, on ${SHA:0:8} (from $TOP)" \
    "  2. bash scripts/ai-review.sh verify ${SHA:0:8}     (log-side, no network)" \
    "  3. git push, then bash scripts/ai-review.sh mark    (posts the status main needs)"
done <<<"$OUT"

[ -z "$NOTES" ] || jq -n --arg m "$NOTES" '{systemMessage: $m}'
exit 0
