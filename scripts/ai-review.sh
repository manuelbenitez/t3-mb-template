#!/usr/bin/env bash
# The ai-review evidence. Records that gstack's /review and the skills the review
# map requires came back clean on ONE commit, so the push and pr-open gates and
# branch protection have something to check.
#
#   bash scripts/ai-review.sh verify [sha]                   # exit 0 when the log satisfies the manifest; no network
#   bash scripts/ai-review.sh mark [summary-file] [--force]  # verify, post the status, then write the marker
#   bash scripts/ai-review.sh check [sha]                    # exit 0 if marked
#   bash scripts/ai-review.sh fail [reason]                  # revoke / record a failed review
#
# verify (B11): required names = `review` + the map's required_skills for the
# changed paths of origin/main...sha. A record satisfies when it names the commit
# (commit_full), the tree was clean and it found nothing critical. A satisfying
# record on a first-parent ancestor carries when the delta since is docs-only
# (review) or touches none of that skill's paths (other skills). Records come from
# the branch's own gstack log, then HEAD-reviews.jsonl. Exit 0 ok, 1 missing,
# 2 unreadable. mark = verify + the `ai-review` commit status + the marker
# `<git-common-dir>/ai-review/<sha>`. Per-commit by design.
# Tests: scripts/ai-review.test.sh. Bypasses: internal-docs/runbooks/local-gates.md.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../.claude/hooks/lib.sh
. "$SCRIPT_DIR/../.claude/hooks/lib.sh"
cd "${CLAUDE_PROJECT_DIR:-$SCRIPT_DIR/..}" || exit 1

CONTEXT="ai-review"
# --git-common-dir, not --git-dir: linked worktrees share one marker store, so a
# commit reviewed in one worktree stays reviewed in another and markers survive
# `git worktree remove`.
COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "not a git repo" >&2; exit 1; }
TOP=$(git rev-parse --show-toplevel)
MARK_DIR="$COMMON_DIR/ai-review"
REVIEW_READER=${AI_REVIEW_LOG_READER:-$HOME/.claude/skills/gstack/bin/gstack-review-read}
GSTACK_HOME=${GSTACK_HOME:-$HOME/.gstack}

cmd=${1:-}
[ $# -gt 0 ] && shift

# Drop markers for commits git no longer knows (amended, rebased away, gc'd), so
# a recycled sha can never inherit an old verdict.
prune_markers() {
  [ -d "$MARK_DIR" ] || return 0
  for f in "$MARK_DIR"/*; do
    [ -f "$f" ] || continue
    git cat-file -e "$(basename "$f")^{commit}" 2>/dev/null || rm -f "$f"
  done
}

# --- the review log ------------------------------------------------------------

# gstack's own project slug and branch file name when its bin is next to the
# reader, else the same derivation (origin owner-repo, branch slugged).
gstack_ids() {
  local bin ids url
  bin="$(dirname "$REVIEW_READER")/gstack-slug"
  if [ -x "$bin" ] && ids=$("$bin" 2>/dev/null); then
    SLUG=$(printf '%s\n' "$ids" | sed -n 's/^SLUG=//p' | tr -cd 'a-zA-Z0-9._-')
    BRANCH_SLUG=$(printf '%s\n' "$ids" | sed -n 's/^BRANCH=//p' | tr -cd 'a-zA-Z0-9._-')
  fi
  if [ -z "${SLUG:-}" ]; then
    if [ -n "${GSTACK_PROJECT_SLUG:-}" ]; then
      SLUG=$(printf '%s' "$GSTACK_PROJECT_SLUG" | tr -cd 'a-zA-Z0-9._-')
    else
      url=$(git remote get-url origin 2>/dev/null) || url=''
      SLUG=$(printf '%s' "${url%.git}" | sed -E 's#.*[:/]([^/]+)/([^/]+)$#\1-\2#' | tr -cd 'a-zA-Z0-9._-')
    fi
  fi
  [ -n "${BRANCH_SLUG:-}" ] || BRANCH_SLUG=$(hook_slug "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)")
  BRANCH_SLUG=${BRANCH_SLUG:-HEAD}
}

# One row per record: skill, commit_full, ok|bad, file. `commit_full` and `dirty`
# are stamped by gstack-review-log from git itself, never typed by the caller.
# ok = clean, or issues_found with critical == 0 (the FAIL tier is CRITICAL+HIGH;
# a record without the field is bad, N/A logs as clean and counts).
index_records() { # index_records FILE < jsonl
  jq -R -r --arg f "$1" '
    (fromjson? // empty) | objects
    | [(.skill // ""), (.commit_full // ""),
       (if .dirty != true and (.status == "clean" or (.status == "issues_found" and ((.critical // 1) == 0)))
        then "ok" else "bad" end), $f]
    | @tsv'
}

# RECORDS: the branch file through the reader, then HEAD-reviews.jsonl (records
# written on a detached HEAD). LOG_FILES names them, one per line.
load_records() {
  local out branch_file head_file
  RECORDS='' LOG_FILES=''
  gstack_ids
  branch_file="$GSTACK_HOME/projects/$SLUG/$BRANCH_SLUG-reviews.jsonl"
  head_file="$GSTACK_HOME/projects/$SLUG/HEAD-reviews.jsonl"
  [ -x "$REVIEW_READER" ] || return 2
  out=$("$REVIEW_READER" 2>/dev/null) || return 2
  RECORDS=$(printf '%s\n' "${out%%---CONFIG---*}" | index_records "$branch_file")
  LOG_FILES=$branch_file
  if [ "$BRANCH_SLUG" != HEAD ] && [ -f "$head_file" ]; then
    RECORDS="$RECORDS"$'\n'"$(index_records "$head_file" <"$head_file")"
    LOG_FILES="$LOG_FILES"$'\n'"$head_file"
  fi
  return 0
}

# record_for NAME SHA → "ok|bad<TAB>file" from the first file holding a record
# of that name for that commit (a hit in the branch file is never overruled by
# the fallback file); ok wins inside one file. Returns 1 when no file has one.
record_for() {
  printf '%s\n' "$RECORDS" | awk -F'\t' -v n="$1" -v s="$2" '
    $1 == n && $2 == s { if (!($4 in v)) { order[++k] = $4; v[$4] = $3 } else if ($3 == "ok") v[$4] = "ok" }
    END { if (k) { print v[order[1]] "\t" order[1]; exit 0 } exit 1 }'
}

# --- the manifest --------------------------------------------------------------

merges_main() { # HEAD is a merge whose second parent is on the local origin/main
  local p2
  p2=$(git rev-parse -q --verify "$1^2" 2>/dev/null) || return 1
  git merge-base --is-ancestor "$p2" origin/main 2>/dev/null
}

summ() { # the first three paths of a list, and how many more
  local n; n=$(printf '%s\n' "$1" | grep -c .)
  printf '%s' "$1" | head -3 | paste -sd, - | sed 's/,/, /g'
  [ "$n" -le 3 ] || printf ' (+%d more)' $((n - 3))
}

# Paths in A..C that are, were or became a symlink or a submodule (a .md name
# can point anywhere): never docs-only, whatever the map says about the name.
odd_modes() {
  git diff --no-renames --raw -z "$1" "$2" -- 2>/dev/null | tr '\0' '\n' | awk '
    /^:/ { odd = ($1 ~ /^:(120000|160000)$/ || $2 ~ /^(120000|160000)$/ || $5 ~ /^T/); if ((getline p) > 0 && odd) print p }'
}

# The match JSON for the delta A..C, cached per ancestor. Empty delta → no paths.
declare -A DELTA_CACHE
delta_json() {
  if [ -z "${DELTA_CACHE[$1]+x}" ]; then
    changed_paths "$1" "$2"
    if [ ${#CHANGED[@]} -eq 0 ]; then DELTA_CACHE[$1]='{"paths":{}}'
    else DELTA_CACHE[$1]=$(map_query match "${CHANGED[@]}" 2>/dev/null) || return 1; fi
  fi
  printf '%s' "${DELTA_CACHE[$1]}"
}

# delta_clear NAME A C → DELTA says why; 0 when the record on A still covers C.
# review: every path since is docs-only. Other skills: no path since is in a rule
# naming it, and none is never-docs-only code outside every skill's rules
# (.claude/**, scripts/**, manifests: the map cannot say whose business it is);
# on a merge of main only the branch's own paths count (skill scope is path-based,
# main's other changes are not its business).
delta_clear() {
  local n=$1 json hits
  json=$(delta_json "$2" "$3") || { DELTA="the review map cannot be read (node scripts/review-map.mjs check)"; return 1; }
  printf '%s' "$json" | jq -e '.paths | type == "object"' >/dev/null 2>&1 ||
    { DELTA="the review map's answer could not be parsed, so nothing carries"; return 1; }
  if [ "$n" = review ]; then
    hits=$(odd_modes "$2" "$3")
    [ -n "$hits" ] && { DELTA="the delta since adds, removes or retypes a symlink or submodule: $(summ "$hits")"; return 1; }
    hits=$(printf '%s' "$json" | jq -r '.paths | to_entries[] | select(.value.docs_only != "docs") | .key')
    [ -n "$hits" ] || { DELTA="the delta since is docs-only"; return 0; }
    DELTA="the delta since touches code: $(summ "$hits")"; return 1
  fi
  if [ "$MERGES_MAIN" = yes ]; then
    json=$(printf '%s' "$json" | jq -e --argjson own "$OWN_JSON" '.paths |= with_entries(.key as $k | select($own | any(. == $k)))') ||
      { DELTA="the review map's answer could not be parsed, so nothing carries"; return 1; }
  fi
  hits=$(printf '%s' "$json" | jq -r --arg n "$n" '.paths | to_entries[]
    | select((.value.skills | any(. == $n)) or (.value.docs_only == "never" and (.value.skills | length) == 0)) | .key')
  [ -n "$hits" ] || { DELTA="the delta since touches none of its paths"; return 0; }
  DELTA="the delta since touches its paths: $(summ "$hits")"; return 1
}

# evaluate NAME SHA → LINE (the report row), WHY (empty when satisfied).
evaluate() {
  local n=$1 c=$2 r f a
  WHY=''
  if r=$(record_for "$n" "$c"); then
    f=${r#*$'\t'}
    if [ "${r%%$'\t'*}" = ok ]; then LINE="✓ $n: record for ${c:0:8} ($f)"; return 0; fi
    WHY="record for ${c:0:8} on $f has critical>0, was taken on a dirty tree or did not come back clean: fix, commit and run /$n again"
    LINE="✗ $n: $WHY"; return 1
  fi
  if [ "$n" = review ] && [ "$MERGES_MAIN" = yes ]; then
    WHY="HEAD merges main; the merged code is new to this branch: run /review on it (carry-over does not apply to merges)"
    LINE="✗ review: $WHY"; return 1
  fi
  # The nearest first-parent ancestor with a satisfying record, never one on main.
  for a in $(first_parent_walk "$c" 20); do
    [ "$a" != "$c" ] || continue
    r=$(record_for "$n" "$a") || continue
    [ "${r%%$'\t'*}" = ok ] || continue
    f=${r#*$'\t'}
    if delta_clear "$n" "$a" "$c"; then LINE="✓ $n: record for ${a:0:8} carries; $DELTA ($f)"; return 0; fi
    WHY="record for ${a:0:8} on $f; HEAD moved since by merge, rebase or a commit ($DELTA): run /$n again"
    LINE="✗ $n: $WHY"; return 1
  done
  [ "$n" = review ] && WHY="no record for ${c:0:8}: run /review on this commit" ||
    WHY="no record for ${c:0:8}: run /$n on this commit"
  LINE="✗ $n: $WHY"; return 1
}

# evidence SHA → REPORT (stdout lines), REFUSAL (stderr lines), MISSING names.
# 0 satisfied, 1 missing, 2 the log, the map or origin/main cannot be read.
evidence() {
  local c=$1 n names json run='' rc
  REPORT=() REFUSAL=() MISSING=() OWN_JSON='[]'
  git rev-parse --verify -q origin/main >/dev/null ||
    { REFUSAL=("❌ no origin/main ref, so the branch's changed paths are unknown: git fetch origin main, then retry."); return 2; }
  load_records || { REFUSAL=("❌ cannot read gstack's review log ($REVIEW_READER missing?), so no review can be verified."); return 2; }
  if merges_main "$c"; then
    MERGES_MAIN=yes
    changed_paths "origin/main...$c^1"
    [ ${#CHANGED[@]} -eq 0 ] || OWN_JSON=$(printf '%s\n' "${CHANGED[@]}" | jq -R . | jq -sc .)
  else
    MERGES_MAIN=no
  fi
  changed_paths "origin/main...$c"
  names=review
  if [ ${#CHANGED[@]} -gt 0 ]; then
    json=$(map_query match "${CHANGED[@]}" 2>/dev/null) ||
      { REFUSAL=("❌ cannot read the review map (node scripts/review-map.mjs check), so the required skills are unknown."); return 2; }
    # Fail closed: an unparseable map answer must never shrink the requirement
    # to `review` alone (it did, silently, when the map's output was cut at 64 KB).
    local skills
    skills=$(printf '%s' "$json" | jq -er '.required_skills | join(" ")') ||
      { REFUSAL=("❌ the review map's answer could not be parsed, so the required skills are unknown: node scripts/review-map.mjs match <paths> | jq ."); return 2; }
    names="review $skills"
    names=${names% }
  fi
  REPORT+=("evidence for ${c:0:8} ($BRANCH_SLUG): required: ${names// /, }")
  REPORT+=("log: $(printf '%s' "$LOG_FILES" | tr '\n' ' ')")
  for n in $names; do
    evaluate "$n" "$c"; rc=$?
    REPORT+=("$LINE")
    [ "$rc" = 0 ] && continue
    MISSING+=("$n"); run="${run:+$run, }/$n"
    REFUSAL+=("   ✗ $n: $WHY")
  done
  [ ${#MISSING[@]} -eq 0 ] && return 0
  REFUSAL=("❌ ${c:0:8} is missing review evidence for: ${MISSING[*]}" "${REFUSAL[@]}"
    "   Run $run on this commit from $TOP, then: bash scripts/ai-review.sh verify ${c:0:8}")
  return 1
}

post_status() { # post_status <sha> <state> <description>
  local repo err
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || repo=""
  if [ -z "$repo" ]; then
    echo "❌ cannot resolve the GitHub repo (gh not installed or not authenticated)." >&2
    return 1
  fi
  if ! err=$(gh api -X POST "repos/$repo/statuses/$1" \
    -f state="$2" -f context="$CONTEXT" -f description="${3:0:139}" 2>&1 >/dev/null); then
    echo "❌ could not post $CONTEXT=$2 on ${1:0:8} to $repo:" >&2
    printf '   %s\n' "$err" >&2
    return 1
  fi
  echo "✓ posted $CONTEXT=$2 on ${1:0:8} ($repo)"
}

case "$cmd" in
check)
  SHA=$(git rev-parse --verify -q "${1:-HEAD}^{commit}" 2>/dev/null) || exit 1
  [ -f "$MARK_DIR/$SHA" ]
  exit $?
  ;;

verify)
  SHA=$(git rev-parse --verify -q "${1:-HEAD}^{commit}" 2>/dev/null) ||
    { echo "❌ no such commit: ${1:-HEAD}" >&2; exit 2; }
  evidence "$SHA"; VERDICT=$?
  [ ${#REPORT[@]} -eq 0 ] || printf '%s\n' "${REPORT[@]}"
  [ "$VERDICT" = 0 ] || printf '%s\n' "${REFUSAL[@]}" >&2
  exit $VERDICT
  ;;

mark)
  SUMMARY_FILE=""
  FORCE=no
  for arg in "$@"; do
    case "$arg" in
      --force) FORCE=yes ;;
      *)
        if [ -n "$SUMMARY_FILE" ]; then
          echo "❌ one summary file at most (got '$SUMMARY_FILE' and '$arg')." >&2
          exit 1
        fi
        SUMMARY_FILE=$arg
        ;;
    esac
  done

  SHA=$(git rev-parse HEAD)
  BRANCH=$(git rev-parse --abbrev-ref HEAD)

  # Branch NAME proves nothing (detached HEAD, or any branch parked on main's
  # tip). Ask git what it is — against a fresh origin/main, and refuse outright
  # when there is no origin/main to ask.
  git fetch origin main --quiet 2>/dev/null || true
  if ! git rev-parse --verify -q origin/main >/dev/null; then
    echo "❌ no origin/main ref — cannot tell whether HEAD is already on main." >&2
    exit 1
  fi
  if git merge-base --is-ancestor HEAD origin/main; then
    echo "❌ HEAD is already on origin/main — there is nothing under review." >&2
    exit 1
  fi
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "❌ working tree is dirty — commit first, so the mark names the reviewed code." >&2
    exit 1
  fi
  if [ -n "$SUMMARY_FILE" ] && [ ! -f "$SUMMARY_FILE" ]; then
    echo "❌ no such summary file: $SUMMARY_FILE" >&2
    exit 1
  fi

  # The evidence check is `verify`, verbatim: the same log, the same bar.
  evidence "$SHA"
  VERDICT=$?
  [ ${#REPORT[@]} -eq 0 ] || printf '%s\n' "${REPORT[@]}"
  FORCED=no
  if [ "$VERDICT" != 0 ]; then
    if [ "$FORCE" != yes ]; then
      printf '%s\n' "${REFUSAL[@]}" >&2
      exit 1
    fi
    echo "⚠ forcing past: ${REFUSAL[0]#❌ }" >&2
    FORCED=yes
  fi

  if [ "$FORCED" = yes ]; then
    DESC="FORCED: no clean /review verified for this commit"
  else
    DESC="gstack /review clean on this commit"
  fi

  # Status first, marker second: a marker without the status would let the PR
  # open locally while the check main requires never arrives.
  post_status "$SHA" success "$DESC" || {
    echo "   If the commit is not pushed yet, push it and re-run. No marker was written." >&2
    exit 1
  }

  prune_markers
  mkdir -p "$MARK_DIR"
  {
    echo "reviewed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "branch:   $BRANCH"
    echo "forced:   $FORCED"
    [ -n "$SUMMARY_FILE" ] && echo "summary:  $SUMMARY_FILE ($(sha256sum "$SUMMARY_FILE" | cut -c1-16))"
  } >"$MARK_DIR/$SHA"
  echo "✓ marked ${SHA:0:8} locally"

  # The PR comment is the only part of the trail that leaves this machine.
  if [ -n "$SUMMARY_FILE" ]; then
    PR=$(gh pr view --json number -q .number 2>/dev/null) || PR=""
    [ -n "$PR" ] || PR=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null) || PR=""
    if [ -z "$PR" ]; then
      echo "ℹ no PR for $BRANCH yet — re-run with the summary once it exists to leave the trail." >&2
    elif ERR=$({ echo "**AI review — \`${SHA:0:8}\`**"; echo; cat "$SUMMARY_FILE"; } |
      gh pr comment "$PR" --body-file - 2>&1 >/dev/null); then
      echo "✓ posted the review summary to PR #$PR"
    else
      echo "⚠ could not comment on PR #$PR (the status still stands):" >&2
      printf '   %s\n' "$ERR" >&2
    fi
  fi
  ;;

fail)
  SHA=$(git rev-parse HEAD)
  REASON=${1:-"review found blocking issues"}
  # Revoke locally no matter what, then insist on the red status: a revocation
  # that leaves a green check standing on GitHub is not a revocation.
  rm -f "$MARK_DIR/$SHA"
  echo "✓ cleared the local mark for ${SHA:0:8}"
  post_status "$SHA" failure "$REASON" || {
    echo "   The green $CONTEXT status (if any) is STILL on GitHub. Fix gh and re-run." >&2
    exit 1
  }
  ;;

*)
  echo "usage: bash scripts/ai-review.sh {verify [sha] | mark [summary-file] [--force] | check [sha] | fail [reason]}" >&2
  exit 1
  ;;
esac
