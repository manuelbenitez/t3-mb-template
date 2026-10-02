#!/usr/bin/env bash
# Regression table for the ai-review gate: scripts/ai-review.sh and
# .claude/hooks/gates/pr-open.sh. Every row that blocks is a shape a review
# once got past the gate with; every row that allows is one it once wrongly
# blocked. Runs in a throwaway repo with a fake `gh` and a fake review log, so it
# never touches this repository or GitHub.
#
#   bash scripts/ai-review.test.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/scripts/ai-review.sh"
HOOK="$ROOT/.claude/hooks/gates/pr-open.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# --- fixtures ----------------------------------------------------------------
# The fixture's remote is this project's repo; its map is this project's plus
# five required skills and their rules, so the manifest and carry-over rows
# have something to require (REVIEW_MAP_TOP points every map query at it).
REPO=$(node "$ROOT/scripts/review-map.mjs" config | sed -n "s/^HOOK_CFG_REPO='\(.*\)'$/\1/p")
[ -n "$REPO" ] || { echo "cannot read project.repo from the review map" >&2; exit 1; }
mkdir -p "$T/bin" "$T/$(dirname "$REPO")" "$T/map/.claude"
sed -e 's|^skills:$|skills:\n  alpha-check: { when: "fixture" }\n  beta-check: { when: "fixture" }\n  gamma-check: { when: "fixture" }\n  delta-check: { when: "fixture" }\n  epsilon-check: { when: "fixture" }|' \
  "$ROOT/.claude/review-map.yml" >"$T/map/.claude/review-map.yml"
cat >>"$T/map/.claude/review-map.yml" <<'YML'
  - id: fx-billing
    paths: ["apps/api/src/billing/**"]
    skills: [alpha-check, beta-check, gamma-check]
    internal_docs: []
    user_docs: []
  - id: fx-math
    paths: ["apps/api/src/math/**"]
    skills: [alpha-check]
    internal_docs: []
    user_docs: []
  - id: fx-portal
    paths: ["apps/nextjs/src/app/billing/**"]
    skills: [delta-check]
    internal_docs: []
    user_docs: []
  - id: fx-companies
    paths: ["apps/api/src/companies/**"]
    skills: [epsilon-check]
    internal_docs: []
    user_docs: []
YML
export REVIEW_MAP_TOP="$T/map"
cat >"$T/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo "$FAKE_GH_REPO" ;;
  "pr view") exit 1 ;;
  "pr list") echo "" ;;
  api*)
    echo "$*" >>"$FAKE_GH_LOG"
    if [ "${FAKE_GH_API_FAIL:-0}" = 1 ]; then echo "HTTP 422: No commit found for SHA" >&2; exit 1; fi ;;
esac
SH
cat >"$T/bin/reader" <<'SH'
#!/usr/bin/env bash
cat "$FAKE_LOG" 2>/dev/null
echo ---CONFIG---
SH
chmod +x "$T/bin/gh" "$T/bin/reader"

g() { git -c user.email=t@t -c user.name=t "$@"; }
git init -q --bare "$T/$REPO.git"
git clone -q "$T/$REPO.git" "$T/repo" 2>/dev/null
g -C "$T/repo" commit -q --allow-empty -m base
git -C "$T/repo" push -q origin HEAD:main 2>/dev/null
git -C "$T/repo" fetch -q origin
g -C "$T/repo" checkout -q -b feat
g -C "$T/repo" commit -q --allow-empty -m change
g -C "$T/repo" worktree add -q "$T/wt" -b feat2 2>/dev/null
g -C "$T/wt" commit -q --allow-empty -m other-change
git init -q "$T/landing"
git -C "$T/landing" remote add origin git@github.com:acme/other.git
g -C "$T/landing" commit -q --allow-empty -m x

SHA=$(git -C "$T/repo" rev-parse HEAD)
MARKS="$(git -C "$T/repo" rev-parse --absolute-git-dir)/ai-review"

export PATH="$T/bin:$PATH" AI_REVIEW_LOG_READER="$T/bin/reader"
export FAKE_LOG="$T/review.jsonl" FAKE_GH_LOG="$T/gh.log" FAKE_GH_REPO="$REPO"

# --- the script ----------------------------------------------------------------
script() { # script <expected-rc> <label> <args...>
  local want=$1 label=$2 rc
  shift 2
  : >"$FAKE_GH_LOG"
  CLAUDE_PROJECT_DIR="$T/repo" bash "$SCRIPT" "$@" >/dev/null 2>&1
  rc=$?
  [ "$rc" = "$want" ] && ok "script: $label" || bad "script: $label (rc=$rc want $want)"
}
entry() { printf '{"skill":"review","status":"%s","commit":"%s","commit_full":"%s","dirty":%s}\n' "$@" >"$FAKE_LOG"; }
posted() { grep -q -- "$1" "$FAKE_GH_LOG"; }

echo "== mark / fail"
rm -f "$FAKE_LOG"
script 1 "no review logged → refused" mark
posted statuses && bad "  …but it posted a status" || ok "  …and posted nothing"

entry issues_found "${SHA:0:8}" "$SHA" false
script 1 "review found issues → refused (no false 'clean')" mark

printf '{"skill":"review","status":"clean","commit":"%s"}\n' "${SHA:0:1}" >"$FAKE_LOG"
script 1 "only the caller-typed .commit matches → refused" mark

entry clean "${SHA:0:8}" "$SHA" true
script 1 "clean review of a dirty tree → refused" mark

entry clean "${SHA:0:8}" "$(git -C "$T/wt" rev-parse HEAD)" false
script 1 "clean review of a different commit → refused" mark

entry clean "${SHA:0:8}" "$SHA" false
FAKE_GH_API_FAIL=1 script 1 "status POST fails → refused" mark
[ -f "$MARKS/$SHA" ] && bad "  …but wrote a marker anyway" || ok "  …and wrote no marker"

script 0 "clean review of exactly HEAD → marked" mark
posted "state=success" && ok "  …posted success" || bad "  …did not post success"
posted "FORCED" && bad "  …but called it forced" || ok "  …not called forced"
[ -f "$MARKS/$SHA" ] && ok "  …marker written" || bad "  …no marker"

script 1 "two summary files → refused" mark a.md b.md

rm -f "$FAKE_LOG"
script 0 "--force with no review → marked" mark --force
posted "FORCED" && ok "  …and the status says FORCED" || bad "  …status does not say forced"

FAKE_GH_API_FAIL=1 script 1 "fail cannot post the red status → non-zero" fail
[ -f "$MARKS/$SHA" ] && bad "  …but left the marker" || ok "  …marker revoked regardless"
script 0 "fail posts red" fail
posted "state=failure" && ok "  …posted failure" || bad "  …did not post failure"

g -C "$T/repo" checkout -q --detach origin/main
entry clean x "$(git -C "$T/repo" rev-parse HEAD)" false
script 1 "detached HEAD on main's tip → refused" mark
g -C "$T/repo" checkout -q feat

# --- the hook ----------------------------------------------------------------
hook() { # hook <expected-rc> <command> [cwd]
  local want=$1 cmd=$2 cwd=${3:-$T/repo} rc
  jq -n --arg c "$cmd" --arg d "$cwd" '{tool_input:{command:$c},cwd:$d}' |
    CLAUDE_PROJECT_DIR="$T/repo" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  [ "$rc" = "$want" ] && ok "hook($rc): $cmd" || bad "hook: got $rc want $want: $cmd"
}

rm -f "$MARKS/$SHA"
echo "== must BLOCK — HEAD unmarked"
for c in \
  'gh pr create --fill' 'gh pr create;' '(gh pr create)' 'gh pr new' \
  '/usr/bin/gh pr create --fill' "bash -c 'gh pr create --fill'" 'eval "gh pr create"' \
  '"gh" pr create' 'g\h pr create' 'GH_PAGER= gh   pr   ready' \
  'gh api -X POST repos/o/r/pulls -f head=x' 'gh api repos/o/r/pulls -X POST' \
  'gh api --method=POST repos/o/r/pulls' 'gh api repos/o/r/pulls -f head=x -f base=main' \
  "gh api graphql -f query='mutation { createPullRequest(input: {}) { clientMutationId } }'"; do
  hook 2 "$c"
done
hook 2 'gh pr \
  create --fill'

echo "== must BLOCK — even with HEAD marked"
: >"$MARKS/$SHA"
for c in \
  'gh pr create -H other-branch' 'gh pr create --head other-branch' 'gh pr create -R someone/fork' \
  'git commit -m x && gh pr create --fill' 'git -C . commit -m x && gh pr create' \
  'git commit --amend --no-edit && gh pr create' 'git pull && gh pr create' \
  'git merge other && gh pr create' 'cd /tmp && gh pr create'; do
  hook 2 "$c"
done
hook 2 'gh pr create --fill' "$T/wt" # marked project dir, unmarked cwd
hook 0 'gh pr create --fill'         # the marked HEAD itself passes

rm -f "$MARKS/$SHA"
echo "== must ALLOW — HEAD unmarked"
for c in \
  'git status' 'pnpm test' 'gh pr view 12' 'gh pr list --state open' 'gh pr comment 12 --body hi' \
  'gh api repos/o/r/pulls/12/comments -X POST -f body=hi' 'gh api repos/o/r/pulls' \
  "grep -rn 'gh pr create' docs/" 'echo "open it later with gh pr create"' \
  'git commit -m "docs: explain the gh pr create gate"'; do
  hook 0 "$c"
done
hook 0 "git commit -F - <<'MSG'
docs: the hook now refuses git commit && gh pr create
MSG"
hook 0 'gh pr create --fill' "$T/landing" # another repo's PR is not this gate's business

echo "== fail closed"
printf '{"tool_input":{"command":"echo hi\\ngh pr create"' |
  CLAUDE_PROJECT_DIR="$T/repo" bash "$HOOK" >/dev/null 2>&1
[ $? = 2 ] && ok "unparseable payload, multi-line command → blocked" || bad "unparseable payload let a PR through"
jq -n '{tool_input:{command:"gh pr create"},cwd:"/nonexistent"}' |
  CLAUDE_PROJECT_DIR=/nonexistent bash "$HOOK" >/dev/null 2>&1
[ $? = 2 ] && ok "cwd not a repo → blocked" || bad "bad cwd let a PR through"

# --- B11: verify, the manifest, carry-over, merges, the log files (rows 19-24) ----
echo "== B11: the acceptance bar (row 19)"
export GSTACK_HOME="$T/gstack"
rec() { # rec <skill> <status> <sha> [critical] [dirty]   — append a record with the REAL sha
  printf '{"skill":"%s","status":"%s","commit":"%s","commit_full":"%s"%s,"dirty":%s}\n' \
    "$1" "$2" "${3:0:8}" "$3" "${4:+,\"critical\":$4}" "${5:-false}" >>"$FAKE_LOG"
}
verify() { # verify <expected-rc> <label> [sha]   — VOUT = stdout + stderr
  local want=$1 label=$2 rc
  shift 2
  VOUT=$(CLAUDE_PROJECT_DIR="$T/repo" bash "$SCRIPT" verify "$@" 2>&1)
  rc=$?
  [ "$rc" = "$want" ] && ok "verify($rc): $label" || bad "verify: got $rc want $want: $label: $(printf '%s' "$VOUT" | head -4 | tr '\n' ' ')"
}
vsaid() { case $VOUT in *"$1"*) ok "  …says: $1" ;; *) bad "  …does not say: $1 (said: $(printf '%s' "$VOUT" | head -6 | tr '\n' ' '))" ;; esac; }
vunsaid() { case $VOUT in *"$1"*) bad "  …but says: $1" ;; *) ok "  …and does not say: $1" ;; esac; }
gc() { git -C "$T/repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
add() { mkdir -p "$T/repo/$(dirname "$1")"; printf '%s\n' "${2:-// $RANDOM}" >"$T/repo/$1"; git -C "$T/repo" add -- "$1"; }
commit() { gc commit -q --allow-empty -m "$1"; }
H() { git -C "$T/repo" rev-parse HEAD; }
BASE=$(git -C "$T/repo" rev-parse origin/main)
rm -f "$MARKS/$SHA"

: >"$FAKE_LOG"; rec review issues_found "$SHA" 0
verify 0 "issues_found with critical:0 satisfies"
: >"$FAKE_LOG"; rec review issues_found "$SHA" 1
verify 1 "issues_found with critical:1 → refused"; vsaid "critical>0"
: >"$FAKE_LOG"; rec review issues_found "$SHA"
verify 1 "issues_found without a critical field → refused"
: >"$FAKE_LOG"; rec review clean "$SHA"
verify 0 "clean satisfies"; vsaid "✓ review: record for ${SHA:0:8}"
: >"$FAKE_LOG"; rec review clean "$SHA" '' true
verify 1 "dirty:true → refused"
: >"$FAKE_LOG"; rec review clean "$SHA" 1
verify 0 "clean with critical:1 (a live shape) still satisfies"
printf '{"skill":"review","status":"clean","verdict":"N/A","commit_full":"%s","dirty":false}\n' "$SHA" >"$FAKE_LOG"
verify 0 "an N/A verdict logged as clean counts"
: >"$FAKE_LOG"
MOUT=$(CLAUDE_PROJECT_DIR="$T/repo" bash "$SCRIPT" mark 2>&1); rc=$?
[ "$rc" = 1 ] && ok "script: mark without evidence → refused" || bad "script: mark without evidence got rc $rc"
case $MOUT in *--force*) bad "  …but the refusal names --force" ;; *) ok "  …and the refusal does not name --force" ;; esac
case $MOUT in *"/review"*) ok "  …and names /review" ;; *) bad "  …and does not name /review: $MOUT" ;; esac
script 0 "mark --force still marks" mark --force
posted "FORCED" && ok "  …and posts FORCED" || bad "  …status does not say FORCED"
rm -f "$MARKS/$SHA"

echo "== B11: verify is network-free (row 20)"
: >"$FAKE_LOG"; rec review clean "$SHA"
# The fake gh leaves PATH; a tripwire gh that records any call and fails takes its place.
mkdir -p "$T/nogh"; printf '#!/usr/bin/env bash\necho "gh $*" >>"$FAKE_GH_LOG"; exit 1\n' >"$T/nogh/gh"; chmod +x "$T/nogh/gh"
NOGH="$T/nogh:$(printf '%s' "$PATH" | sed "s#$T/bin:##")"
: >"$FAKE_GH_LOG"
VOUT=$(PATH=$NOGH CLAUDE_PROJECT_DIR="$T/repo" bash "$SCRIPT" verify 2>&1); rc=$?
[ "$rc" = 0 ] && ok "verify(0): with gh failing on PATH, a satisfying HEAD verifies" || bad "verify without gh: rc $rc: $VOUT"
[ ! -s "$FAKE_GH_LOG" ] && ok "  …and gh was never called" || bad "  …but gh was called: $(cat "$FAKE_GH_LOG")"
FAKE_GH_API_FAIL=1 script 1 "mark on the same HEAD: the 422 fixture → refused" mark
[ -f "$MARKS/$SHA" ] && bad "  …but wrote a marker" || ok "  …and wrote no marker"
script 0 "mark on the same HEAD with gh working → marked" mark
rm -f "$MARKS/$SHA"

echo "== B11: the manifest (row 21)"
add apps/api/src/billing/x.ts 'export const w = 1;'; commit "billing"
A=$(H)
: >"$FAKE_LOG"; rec review clean "$A"
verify 1 "a billing path with a satisfying review but no skill records → refused naming the skills"
vsaid "✗ alpha-check"; vsaid "✗ beta-check"; vsaid "✗ gamma-check"; vsaid "/alpha-check"
vunsaid "cso"; vunsaid "--force"
rec alpha-check clean "$A"; rec beta-check clean "$A"; rec gamma-check clean "$A"
verify 0 "with every skill record → satisfied"
vsaid "required: review, alpha-check, beta-check, gamma-check"
script 0 "…and mark marks it" mark
posted "state=success" && ok "  …posted success" || bad "  …no status posted"
rm -f "$MARKS/$A"
gc checkout -q --detach "$BASE"; add apps/api/src/companies/x.ts 'export const c = 1;'; commit "companies only"
: >"$FAKE_LOG"; rec review clean "$(H)"
verify 1 "an epsilon-check rule → required; a trigger-only skill never adds a name"
vsaid "✗ epsilon-check"; vunsaid "cso"
rec epsilon-check clean "$(H)"
verify 0 "…and its record satisfies"
gc checkout -q --detach "$BASE"; add apps/api/src/auth/x.ts 'export const x = 2;'; commit "api-any only"
: >"$FAKE_LOG"; rec review clean "$(H)"
verify 0 "a path whose only rules are trigger-only needs review alone"
vsaid "required: review"; vunsaid "cso"
gc checkout -q feat

echo "== B11: per-skill carry-over (row 22)"
seed_A() { gc reset -q --hard "$A"; : >"$FAKE_LOG"; for s in review alpha-check beta-check gamma-check; do rec "$s" clean "$A"; done; }
seed_A; add internal-docs/x.md '# x'; commit "docs"
verify 0 "A + internal-docs/x.md → every record carries"; vsaid "carries"; vsaid "docs-only"
rec review clean "$(H)"
verify 0 "A + internal-docs/x.md with a fresh review on HEAD only → the skill records carry per skill"
vsaid "✓ review: record for $(H | cut -c1-8)"; vsaid "✓ alpha-check: record for ${A:0:8} carries"
seed_A; add 'apps/nextjs/src/app/billing/x.tsx' 'export default () => null;'; commit "portal"
rec review clean "$(H)"; rec delta-check clean "$(H)"
verify 0 "A + a portal billing file with fresh review + delta-check on HEAD → the billing records carry"
vsaid "✓ alpha-check: record for ${A:0:8} carries"; vsaid "touches none of its paths"
seed_A; add apps/api/src/math/math.ts 'export const m = 1;'; commit "math"
rec review clean "$(H)"; rec delta-check clean "$(H)"
verify 1 "A + math.ts with a fresh review → refused naming alpha-check"
vsaid "✗ alpha-check: record for ${A:0:8}"; vsaid "HEAD moved since"; vsaid "apps/api/src/math/math.ts"
vsaid "✓ beta-check: record for ${A:0:8} carries"; vsaid "✓ gamma-check: record for ${A:0:8} carries"
seed_A; add apps/api/src/auth/x.ts 'export const x = 3;'; commit "api-any"
rec review clean "$(H)"
verify 0 "A + apps/api/src/auth/x.ts (trigger-only rules) with a fresh review → the skill records carry"
seed_A; add package.json '{"name":"fixture","x":1}'; commit "manifest"
rec review clean "$(H)"
verify 1 "A + package.json with a fresh review → refused: never-docs-only code no skill's rule covers"
vsaid "✗ alpha-check"; vsaid "package.json"
seed_A; add .claude/hooks/x.sh '#!/bin/sh'; commit "hook"
verify 1 "A + .claude/hooks/x.sh → refused (never docs-only)"; vsaid "✗ review"; vsaid "✗ alpha-check"
seed_A; mkdir -p "$T/repo/internal-docs"; git -C "$T/repo" mv apps/api/src/billing/x.ts internal-docs/notes.md; commit "move code to docs"
verify 1 "A + git mv billing/x.ts internal-docs/notes.md → refused (the deleted side counts)"
vsaid "✗ review"; vsaid "apps/api/src/billing/x.ts"
seed_A; mkdir -p "$T/repo/apps/docs/en"; ln -s ../../../internal-docs/x.md "$T/repo/apps/docs/en/x.md"; git -C "$T/repo" add apps/docs/en/x.md; commit "symlink"
verify 1 "A + a symlink at apps/docs/en/x.md → refused"; vsaid "✗ review"; vsaid "symlink"
seed_A; add internal-docs/public/_headers 'x'; commit "headers"
verify 1 "A + internal-docs/public/_headers → refused"
seed_A; add internal-docs/.vitepress/config.mts 'export default {};'; commit "vitepress"
verify 1 "A + internal-docs/.vitepress/config.mts → refused"
seed_A; add CLAUDE.md '# rules'; commit "claude.md"
verify 1 "A + root CLAUDE.md → refused"
seed_A; add internal-docs/a.md; commit a; add apps/docs/en/b.md; commit b; add README.md '# r'; commit c
verify 0 "A + three docs commits → carries across the walk"
gc reset -q --hard "$A"; : >"$FAKE_LOG"
for s in review alpha-check beta-check gamma-check; do rec "$s" clean "$BASE"; done
verify 1 "records on origin/main's tip never count (the walk stops there)"; vsaid "no record"
seed_A; for i in $(seq 1 20); do add "internal-docs/d$i.md" "# $i"; commit "d$i"; done
verify 0 "20 docs commits after A → still found"
add internal-docs/d21.md '# 21'; commit d21
verify 1 "21 commits after A → beyond the walk, refused"

echo "== B11: merge commits (row 23)"
gc checkout -q -b mainwork "$BASE"
add apps/api/src/companies/x.ts 'export const c = 1;'; commit "main: companies"
git -C "$T/repo" push -q origin HEAD:main 2>/dev/null; git -C "$T/repo" fetch -q origin
gc checkout -q feat; seed_A
gc merge -q --no-edit origin/main
verify 1 "git merge origin/main on A, main touching companies/x.ts → review refused with the merge text, the skill records carry"
vsaid "HEAD merges main; the merged code is new to this branch"; vsaid "✗ review"; vsaid "✓ alpha-check: record for ${A:0:8} carries"; vsaid "✓ beta-check"
rec review clean "$(H)"
verify 0 "…with a fresh review on the merge commit → satisfied"
gc checkout -q mainwork
add apps/api/src/billing/x.ts 'export const w = 2;'; commit "main: billing too"
git -C "$T/repo" push -q origin HEAD:main 2>/dev/null; git -C "$T/repo" fetch -q origin
gc checkout -q feat; seed_A
if ! gc merge -q --no-edit origin/main >/dev/null 2>&1; then
  printf 'export const w = 3;\n' >"$T/repo/apps/api/src/billing/x.ts"; git -C "$T/repo" add apps/api/src/billing/x.ts; commit "merge main (conflict resolved)"
fi
git -C "$T/repo" rev-parse -q --verify HEAD^2 >/dev/null && ok "  (the merge with a conflict in billing/x.ts is in place)" || bad "  the merge fixture did not produce a merge commit"
rec review clean "$(H)"
verify 1 "the same merge with main touching billing/x.ts and the conflict resolved → alpha-check refused too"
vsaid "✗ alpha-check"; vsaid "✗ beta-check"; vsaid "✓ review"
git -C "$T/repo" push -q -f origin "$BASE:main" 2>/dev/null; git -C "$T/repo" fetch -q origin
gc branch -q -D mainwork

echo "== B11: the log files (row 24)"
seed_A; : >"$FAKE_LOG"
verify 1 "no record in the branch file, no HEAD-reviews.jsonl → refused"
vsaid "log: $T/gstack/projects/${REPO/\//-}/feat-reviews.jsonl"
mkdir -p "$T/gstack/projects/${REPO/\//-}"
for s in review alpha-check beta-check gamma-check; do
  printf '{"skill":"%s","status":"clean","commit_full":"%s","dirty":false}\n' "$s" "$A" >>"$T/gstack/projects/${REPO/\//-}/HEAD-reviews.jsonl"
done
verify 0 "records under HEAD-reviews.jsonl (a detached-HEAD review) are found on a miss in the branch file"
vsaid "HEAD-reviews.jsonl"; vsaid "✓ review: record for ${A:0:8} ($T/gstack/projects/${REPO/\//-}/HEAD-reviews.jsonl)"
rec review issues_found "$A" 1
verify 1 "a branch-file record for the same commit is never overruled by the fallback file"
vsaid "✗ review: record for ${A:0:8} on $T/gstack/projects/${REPO/\//-}/feat-reviews.jsonl"
rm -rf "$T/gstack"

echo "== an unparseable map answer fails closed"
cat >"$T/bin/map.mjs" <<'JS'
// The real map, except the answers named in TRUNC_ON come back cut mid-string (the 64 KB pipe cut).
const [, , cmd, ...paths] = process.argv;
if (cmd === "match" && (process.env.TRUNC_ON === "all" || paths.join(" ") === process.env.TRUNC_ON)) {
  process.stdout.write('{"paths":{"apps/api/src/funds/wa');
} else {
  process.argv.splice(1, 1, process.env.REAL_MAP);
  await import(process.env.REAL_MAP);
}
JS
export HOOK_REVIEW_MAP_SCRIPT="$T/bin/map.mjs" REAL_MAP="$ROOT/scripts/review-map.mjs"
seed_A; add internal-docs/trunc.md '# t'; commit "docs"
TRUNC_ON=all verify 2 "the branch's answer cut short → refused, never 'review' alone"; vsaid "cannot read the review map"
TRUNC_ON=internal-docs/trunc.md verify 1 "the delta's answer cut short → nothing carries"; vsaid "the review map cannot be read"
( . "$ROOT/.claude/hooks/lib.sh"; TRUNC_ON=all map_query match apps/api/src/math/math.ts >/dev/null 2>&1 )
[ $? = 3 ] && ok "map_query refuses a cut answer for every caller (pr-open, the docs gate, obligations)" || bad "map_query passed a cut answer through"
TRUNC_ON=none verify 0 "…and the same branch with a whole answer carries (the fake is a pass-through)"
unset HOOK_REVIEW_MAP_SCRIPT REAL_MAP

echo
[ "$fails" = 0 ] && echo "all passed" || echo "$fails FAILED"
exit $((fails > 0))
