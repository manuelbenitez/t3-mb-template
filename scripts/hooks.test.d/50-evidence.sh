#!/usr/bin/env bash
# Evidence at push and PR open, the obligations context and the edit nudge:
# gates/push.sh (B8), gates/pr-open.sh (the B7 lifecycle and B9 deps markers,
# the pr-open marker), scripts/obligations.sh (B10), obligations-context.sh
# (the B17 prune), edit-nudge.sh (B12), all on top of `ai-review.sh verify`
# (B11, whose own rows 19-24 live in scripts/ai-review.test.sh). Sourced by
# scripts/hooks.test.sh.
#
# Records are written to the fake review log with the REAL shas of the
# throwaway repo; pushes dry-run against its bare origin; gh is the fake.
# shellcheck shell=bash disable=SC2034,SC2154

export GSTACK_HOME="$T/gstack"
STATE="$T/repo/.git/$HOOK_CFG_STATE_DIR"
MARKS="$T/repo/.git/ai-review"
PR12='[{"number":12}]'
BAD_TS='export const x: number = "not a number";'
rec() { # rec <skill> <status> <sha> [critical] [dirty]   — append a record to the fake branch log
  printf '{"skill":"%s","status":"%s","commit":"%s","commit_full":"%s"%s,"dirty":%s}\n' \
    "$1" "$2" "${3:0:8}" "$3" "${4:+,\"critical\":$4}" "${5:-false}" >>"$FAKE_LOG"
}
sha() { git -C "$(where "$1")" rev-parse "${2:-HEAD}"; }
mark_head() { mkdir -p "$MARKS" && : >"$MARKS/$(sha "${1:-repo}")"; }           # the ai-review mark for HEAD
life_marker() { mkdir -p "$STATE/lifecycle" && : >"$STATE/lifecycle/$(lifecycle_key "$(where "${1:-repo}")" HEAD)"; }
deps_marker() { mkdir -p "$STATE/deps" && : >"$STATE/deps/$(deps_key "$(where "${1:-repo}")" HEAD)"; }
evidence_for() { local s=$1; shift; for n in "$@"; do rec "$n" clean "$s"; done; } # evidence_for <sha> <names…>
scrub() { reset; : >"$FAKE_LOG"; rm -rf "$T/gstack" "$STATE" "$MARKS"; }
NOGH_PATH=$(printf '%s' "$PATH" | sed "s#$T/bin:##")
REQUIRED_SKILLS="fixture-check" # what the fixture map requires for apps/api/src/billing/**
obl() { # obl <where> [label]   — scripts/obligations.sh from that checkout, with no fake tools on PATH
  local cwd t0 t1; cwd=$(where "$1")
  t0=$(date +%s%N)
  OUT=$(cd "$cwd" && PATH=$NOGH_PATH bash "$ROOT/scripts/obligations.sh" 2>&1); RC=$?
  t1=$(date +%s%N); OBL_MS=$(((t1 - t0) / 1000000))
  [ "$RC" = 0 ] && ok "obligations($RC) $1: ${2:-} (${OBL_MS} ms)" || bad "obligations $1: ${2:-} got rc $RC: $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
}
nudge() { # nudge <file> <session> <label>   — edit-nudge.sh on an Edit payload
  OUT=$(jq -n --arg f "$1" --arg s "$2" --arg d "$T/repo" '{session_id:$s,cwd:$d,hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:$f}}' |
    CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/edit-nudge.sh" 2>&1); RC=$?
  [ "$RC" = 0 ] && ok "edit-nudge(0): $3" || bad "edit-nudge: $3 got rc $RC: $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
}
session_start() { # session_start <where> <label>   — obligations-context.sh on a SessionStart payload
  OUT=$(jq -n --arg d "$(where "$1")" '{session_id:"s9",cwd:$d,hook_event_name:"SessionStart",source:"startup"}' |
    CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/obligations-context.sh" 2>&1); RC=$?
  [ "$RC" = 0 ] && ok "obligations-context(0) $1: $2" || bad "obligations-context $1: $2 got rc $RC: $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
}

# =============================================================================
echo "== E1. pr-open needs the lifecycle and deps markers, then the mark"
scrub; rewind repo
seed "$T/repo" apps/api/src/auth/x.ts 'export const f = 1;'; g -C "$T/repo" add -A; commit repo "funds"
gate pr-open 2 repo 'gh pr create --fill' 'a lifecycle path in origin/main...HEAD, no marker → blocked naming the suite'
said "scripts/lifecycle-suite.sh"; said "apps/api/src/auth/x.ts"; unsaid "no clean AI review"
life_marker
gate pr-open 2 repo 'gh pr create --fill' 'lifecycle marker for HEAD, no ai-review mark → the mark check blocks'
said "no clean AI review recorded"; unsaid "lifecycle-suite"
mark_head
gate pr-open 0 repo 'gh pr create --fill' 'marker + mark → allowed'
[ -f "$STATE/pr-open/feat" ] && ok "  …and wrote <state>/pr-open/feat" || bad "  …no pr-open/feat marker under $STATE"
seed "$T/repo" internal-docs/x.md '# x'; g -C "$T/repo" add -A; commit repo "docs"; mark_head
gate pr-open 0 repo 'gh pr create --fill' 'then a commit touching only internal-docs/x.md → the lifecycle marker still holds'
seed "$T/repo" apps/api/src/auth/y.ts 'export const y = 1;'; g -C "$T/repo" add -A; commit repo "more funds"; mark_head
gate pr-open 2 repo 'gh pr create --fill' 'then a commit touching apps/api/src/auth/y.ts → the key turned, blocked'
said "scripts/lifecycle-suite.sh"
life_marker
git -C "$T/repo" mv apps/api/src/auth/x.ts internal-docs/x2.md; commit repo "rename code to docs"; mark_head
gate pr-open 2 repo 'gh pr create --fill' 'git mv apps/api/src/auth/x.ts internal-docs/x2.md → a lifecycle change, blocked'
said "scripts/lifecycle-suite.sh"
life_marker
gate pr-open 0 repo 'gh pr create --fill' 'fresh marker → allowed again'
seed "$T/repo" package.json '{"name":"fixture","private":true,"packageManager":"pnpm@10.19.0","x":1}'; g -C "$T/repo" add -A; commit repo "manifest"; mark_head; life_marker
gate pr-open 2 repo 'gh pr create --fill' 'a manifest change in the range and no deps marker → blocked naming the smoke'
said "scripts/deps-smoke.sh"; said "package.json"; unsaid "lifecycle-suite"
deps_marker
gate pr-open 0 repo 'gh pr create --fill' 'deps marker for HEAD → allowed'
gate pr-open 0 other 'gh pr create --fill' 'another repo: none of this applies'

# =============================================================================
echo "== E2. push, blocked before any network"
scrub; rewind repo
for c in 'git commit -m x && git push' 'git commit -m x; git push -u origin feat' "git -C $T/wt commit -m x && git -C $T/wt push"; do
  gate push 2 repo "$c"; said "commit first, then push alone"
done
[ ! -s "$FAKE_GH_LOG" ] && ok "  …and gh was never called" || bad "  …but gh was called: $(head -2 "$FAKE_GH_LOG" | tr '\n' ' ')"
stage repo apps/api/src/x.ts "$BAD_TS"; stage repo internal-docs/README.md '# updated'
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo 'git commit -m x && git push' 'through the dispatcher: the commit half is gated, then the push half refuses'
said "commit first, then push alone"
HOOK_GATES_DIR=$T/gates-mixed FAKE_FAIL=typecheck dispatch 2 repo 'git commit -m x && git push' 'and a failing commit stage blocks first'
said "--- typecheck ---"; unsaid "commit first, then push alone"
reset
for c in 'git push --all' 'git push --mirror origin' 'git push origin --prune'; do
  gate push 2 repo "$c"; said "push one ref"
done
gate push 0 repo 'git status' 'not a push'
gate push 0 repo 'git commit -m "docs: the git push gate"' 'a push mentioned in a message is not a push'
gate push 0 other 'git push origin main' 'another repo: its pushes are its business'
gate push 0 other 'git push -f origin main'
git -C "$T/repo" remote set-url origin "$T/broken/$REPO.git"
gate push 2 repo 'git push origin feat' 'the dry run fails (origin unreachable) → cannot tell what would be pushed'
said "cannot tell what would be pushed"; said "does not appear to be a git repository"
git -C "$T/repo" remote set-url origin "$T/$REPO.git"
git -C "$T/other" remote add proj "$T/$REPO.git"
gate push 2 other 'git push proj HEAD:main' 'another clone pushing to project.repo: gated (here its dry run is refused)'
said "Push blocked"
gate push 2 other "git push $T/$REPO.git HEAD:main" 'the same push by URL'
said "Push blocked"
gate push 0 other 'git push origin HEAD:main' 'the same clone pushing to its own origin: not this gate'
git -C "$T/other" remote remove proj
raw push 2 '{"tool_input":{"command":"git push --all"' 'truncated JSON: still classified, still refused'
said "push one ref"

# =============================================================================
echo "== E3. main is landed by PR"
scrub; rewind repo
git -C "$T/repo" branch -f main origin/main 2>/dev/null && git -C "$T/repo" branch --set-upstream-to=origin/main main -q
git -C "$T/repo" remote add upstream "$T/$REPO.git" 2>/dev/null || true
commit repo "ahead on feat"
for c in 'git push origin main' 'git push origin HEAD:main' 'git push origin feat:main' 'git push origin HEAD:refs/heads/main' \
  'git push -f origin main' 'git push origin +main' 'git push upstream main' 'git push origin HEAD:main --dry-run' 'git push origin :main'; do
  gate push 2 repo "$c"; said "main is landed by PR"
done
g -C "$T/repo" checkout -q main
gate push 2 repo 'git push' 'a bare git push while on main'
said "main is landed by PR"
g -C "$T/repo" checkout -q feat
gate push 0 repo 'git push origin feat' 'the same command shapes to a branch → allowed (no PR)'

# =============================================================================
echo "== E4. a branch with a PR needs evidence for the sha git would push"
scrub; rewind repo
seed "$T/repo" apps/api/src/billing/x.ts 'export const w = 1;'; g -C "$T/repo" add -A; commit repo "billing"
FEAT=$(sha repo)
gate push 0 repo 'git push origin feat' 'no PR (gh says [], no marker) → allowed'
grep -q 'pr list --head feat' "$FAKE_GH_LOG" && ok "  …after asking gh for feat's PRs" || bad "  …gh was not asked: $(cat "$FAKE_GH_LOG")"
FAKE_GH_PRS=$PR12 gate push 2 repo 'git push origin feat' 'PR open, no record → blocked naming /review, the skills and verify'
said "PR #12"; said "/review"; said "fixture-check"; said "bash scripts/ai-review.sh verify"
unsaid "cso"; unsaid "--force"
evidence_for "$FEAT" review $REQUIRED_SKILLS
FAKE_GH_PRS=$PR12 gate push 0 repo 'git push origin feat' 'PR open + review + kit records + NO ai-review marker → allowed (the deadlock row)'
[ ! -f "$MARKS/$FEAT" ] && ok "  …with no ai-review marker in play" || bad "  …an ai-review marker existed"
: >"$FAKE_LOG"; rec review issues_found "$FEAT" 1; evidence_for "$FEAT" $REQUIRED_SKILLS
FAKE_GH_PRS=$PR12 gate push 2 repo 'git push origin feat' 'the review found something critical → blocked'
said "critical>0"
: >"$FAKE_LOG"; rec review issues_found "$FEAT" 0; evidence_for "$FEAT" $REQUIRED_SKILLS
FAKE_GH_PRS=$PR12 gate push 0 repo 'git push origin feat' 'issues_found with critical:0 satisfies'
: >"$FAKE_LOG"
mkdir -p "$STATE/pr-open" && : >"$STATE/pr-open/feat"
FAKE_GH_SLEEP=3 HOOK_GH_TIMEOUT=1 gate push 2 repo 'git push origin feat' 'gh times out + pr-open marker → treated as a PR, no record → blocked'
said "could not confirm whether a PR exists for feat (gh timed out"; said "lacks review evidence"
rm -f "$STATE/pr-open/feat"
FAKE_GH_SLEEP=3 HOOK_GH_TIMEOUT=1 gate push 0 repo 'git push origin feat' 'gh times out, no marker → no PR, the line is printed'
said '"systemMessage"'; said "could not confirm whether a PR exists for feat"
# judged on the pushed branch's sha, never HEAD
g -C "$T/repo" checkout -q -b other "$BASE"
seed "$T/repo" internal-docs/other.md '# other'; g -C "$T/repo" add -A; commit repo "other"
OTHER=$(sha repo)
g -C "$T/repo" checkout -q feat
: >"$FAKE_LOG"; rec review clean "$OTHER"
FAKE_GH_PRS=$PR12 gate push 0 repo 'git push origin other' "git push origin other while on feat: judged on other's sha (recorded) → allowed"
: >"$FAKE_LOG"; evidence_for "$FEAT" review $REQUIRED_SKILLS
FAKE_GH_PRS=$PR12 gate push 2 repo 'git push origin other' "HEAD recorded, other not → blocked naming other's sha"
said "${OTHER:0:8}"; unsaid "${FEAT:0:8} (what git would push)"
git -C "$T/repo" push -q origin feat 2>/dev/null
FAKE_GH_PRS=$PR12 gate push 0 repo 'git push origin :feat' 'a delete → allowed'
FAKE_GH_PRS=$PR12 gate push 0 repo 'git push origin --delete feat'
FAKE_GH_PRS=$PR12 gate push 0 repo 'git push origin feat' 'up to date → nothing to judge'

echo "== E4b. forced updates"
g -C "$T/repo" commit -q --amend --allow-empty -m "billing (amended)"
NEW=$(sha repo)
gate push 2 repo 'git push origin feat' 'diverged without force → git rejects the dry run → cannot tell'
said "cannot tell what would be pushed"
for c in 'git push -f origin feat' 'git push --force origin feat' 'git push origin +feat'; do
  gate push 2 repo "$c" "$c → use --force-with-lease, the env var is never named"
  said "use --force-with-lease"; unsaid "HOOK_ALLOW_FORCE_PUSH"
done
: >"$FAKE_LOG"; evidence_for "$NEW" review $REQUIRED_SKILLS
FAKE_GH_PRS=$PR12 gate push 0 repo 'git push --force-with-lease origin feat' '--force-with-lease with a verified from-sha → allowed'
FAKE_GH_PRS=$PR12 gate push 0 repo 'git push --force-if-includes --force-with-lease origin feat'
: >"$FAKE_LOG"
FAKE_GH_PRS=$PR12 gate push 2 repo 'git push --force-with-lease origin feat' '--force-with-lease without evidence → blocked on verify'
said "lacks review evidence"
gate push 0 repo 'HOOK_ALLOW_FORCE_PUSH=1 git push -f origin feat' 'the prefix form → allowed'
gate push 0 repo 'env HOOK_ALLOW_FORCE_PUSH=1 git push -f origin feat'
gate push 2 repo 'export HOOK_ALLOW_FORCE_PUSH=1; git push -f origin feat' 'export … ; → not the prefix form, blocked'
said "use --force-with-lease"
gate push 2 repo 'git push -f origin feat # HOOK_ALLOW_FORCE_PUSH=1' 'a comment mentioning it → blocked'
said "use --force-with-lease"
git -C "$T/repo" push -q origin :feat 2>/dev/null
git -C "$T/repo" branch -q -D other 2>/dev/null

# =============================================================================
echo "== E5. obligations"
scrub; rewind repo
g -C "$T/repo" checkout -q main 2>/dev/null || g -C "$T/repo" checkout -q -b main origin/main
obl repo 'on main'; silent
g -C "$T/repo" checkout -q feat
seed "$T/repo" apps/api/src/billing/schemas/x.schema.ts 'export const s = 1;'; g -C "$T/repo" add -A; commit repo "billing schema"
obl repo 'a billing schema change, empty log'
[ "$OBL_MS" -lt 1000 ] && ok "  …in ${OBL_MS} ms (< 1 s, no gh on PATH)" || bad "  …took ${OBL_MS} ms"
said "Branch: feat"; said "apps/api/src/billing/schemas/x.schema.ts"
said "✗ review: no record"; said "✗ fixture-check: no record"
said "log: $T/gstack/projects/${REPO/\//-}/feat-reviews.jsonl"
said "internal-docs/architecture/billing.md"; said "apps/docs/en/billing/"
said "ai-review mark for"; said "✗ not marked"; said "lifecycle marker (a lifecycle path changed): ✗ missing"; said "scripts/lifecycle-suite.sh"; said "deps marker: not needed"
unsaid "HEAD merges main"
rec review clean "$(sha repo)"; rec fixture-check issues_found "$(sha repo)" 1
obl repo 'with records'
said "✓ review: record for"; said "✗ fixture-check: record for"; said "critical>0"
: >"$FAKE_LOG"; rec review clean "$(sha repo)"; rec fixture-check clean "$(sha repo)"
life_marker; mark_head
obl repo 'with the markers'
said "lifecycle marker (a lifecycle path changed): ✓ present"; said "✓ marked"
# a merge of main: origin/main advances with a companies file, feat merges it
g -C "$T/repo" checkout -q -b mainwork origin/main
seed "$T/repo" apps/api/src/companies/x.ts 'export const c = 1;'; g -C "$T/repo" add -A; commit repo "on main"
git -C "$T/repo" push -q origin HEAD:main 2>/dev/null && git -C "$T/repo" fetch -q origin
g -C "$T/repo" checkout -q feat && g -C "$T/repo" merge -q --no-edit origin/main
obl repo 'a merge-of-main HEAD'
said "HEAD merges main; the merged code is new to this branch"; said "✗ review"
said "✓ fixture-check: record for"; said "carries"
# restore origin/main for whoever runs after this file
git -C "$T/repo" push -q -f origin "$BASE:main" 2>/dev/null && git -C "$T/repo" fetch -q origin
git -C "$T/repo" branch -q -D mainwork 2>/dev/null
rewind repo

# =============================================================================
echo "== E6. the edit-time nudge, once per file per session"
scrub
seed "$T/repo" apps/api/src/billing/math.ts 'export const m = 1;'
nudge "$T/repo/apps/api/src/billing/math.ts" s1 'first edit of a billing file → the nudge'
said '"systemMessage"'; said "apps/api/src/billing/math.ts"; said "/fixture-check"
said "internal-docs/architecture/billing.md"; said "apps/docs/en/billing/"
nudge "$T/repo/apps/api/src/billing/math.ts" s1 'the second edit in the same session → nothing'; silent
nudge "$T/repo/apps/api/src/billing/math.ts" s2 'a new session → nudged again'; said "/fixture-check"
seed "$T/repo" apps/api/src/auth/x.ts 'export const c = 1;'
nudge "$T/repo/apps/api/src/auth/x.ts" s1 'an auth file → the trigger-only skill, its page'
said "Trigger-only"; said "/cso"; said "internal-docs/architecture/auth.md"; unsaid "skills before the PR"
seed "$T/repo" README.md '# fixture'
nudge "$T/repo/README.md" s1 'an unmapped file → nothing'; silent
nudge "$T/other/apps/api/src/x.ts" s1 'another repo → nothing'; silent
nudge "$T/repo/apps/api/src/billing/math.ts" 'x/../y z' 'a hostile session id is slugged'
[ -d "$STATE/nudged/x-..-yz" ] && ok "  …marker dir slugged: x-..-yz" || bad "  …marker dirs: $(ls "$STATE/nudged" 2>/dev/null | tr '\n' ' ')"
[ -d "$STATE/nudged/s1" ] && [ -d "$STATE/nudged/s2" ] && ok "  …nudged/<session> dirs live under the common git dir" || bad "  …no nudged dirs under $STATE"
printf '{"session_id":"s1","tool_input":{"file_path":"%s"' "$T/repo/apps/api/src/auth/x.ts" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/edit-nudge.sh" >"$T/o1" 2>&1
[ $? = 0 ] && [ ! -s "$T/o1" ] && ok "edit-nudge(0): a truncated payload → silent, a nudge never blocks" || bad "edit-nudge on a truncated payload: rc $? $(head -c 200 "$T/o1")"

echo "== E6b. SessionStart injects the obligations and prunes the state"
mkdir -p "$STATE/nudged/old" "$STATE/pr-open"; touch -d '8 days ago' "$STATE/nudged/old"
: >"$STATE/pr-open/gone-branch"; : >"$STATE/pr-open/feat"
seed "$T/repo" apps/api/src/billing/x.ts 'export const w = 1;'; g -C "$T/repo" add -A; commit repo "billing"
session_start repo 'on feat with a billing change'
said '"hookSpecificOutput"'; said '"additionalContext"'; said "Obligations for this branch"; said "fixture-check"; said "bash scripts/obligations.sh"
[ ! -d "$STATE/nudged/old" ] && ok "  …nudged/ dir older than 7 days pruned" || bad "  …nudged/old survived"
[ -d "$STATE/nudged/s1" ] && ok "  …today's session dir kept" || bad "  …nudged/s1 was pruned"
[ ! -f "$STATE/pr-open/gone-branch" ] && ok "  …pr-open/<slug> of a deleted branch pruned" || bad "  …pr-open/gone-branch survived"
[ -f "$STATE/pr-open/feat" ] && ok "  …pr-open/feat kept" || bad "  …pr-open/feat was pruned"
rewind repo
g -C "$T/repo" checkout -q main 2>/dev/null || g -C "$T/repo" checkout -q -b main origin/main
session_start repo 'on main → nothing'; silent
g -C "$T/repo" checkout -q feat
session_start other 'another repo → nothing'; silent
session_start tmp 'not a repo → nothing'; silent

# =============================================================================
echo "== E7. state under the common git dir"
scrub; rewind repo
mark_head wt
gate pr-open 0 wt 'gh pr create --fill' 'pr-open from the worktree, with the shell in /tmp'
[ -f "$STATE/pr-open/feat2" ] && ok "  …marker written under the main checkout's .git, found from there" || bad "  …no $STATE/pr-open/feat2"
[ ! -e "$T/elsewhere/.git" ] && ok "  …and nothing under \$PWD/.git" || bad "  …a .git appeared under the harness cwd"
[ "$(state_dir "$T/wt")" = "$STATE" ] && ok "  …state_dir from the worktree is the same dir" || bad "  …state_dir(wt) = $(state_dir "$T/wt")"
g -C "$T/repo" checkout -q -b chore/x
mark_head
gate pr-open 0 repo 'gh pr create --fill' 'a slashed branch name'
[ -f "$STATE/pr-open/chore-x" ] && ok "  …produces pr-open/chore-x" || bad "  …markers: $(ls "$STATE/pr-open" 2>/dev/null | tr '\n' ' ')"
g -C "$T/repo" checkout -q feat
g -C "$T/repo" worktree add -q "$T/wt3" -b tmpbr 2>/dev/null
mark_head "$T/wt3"
gate pr-open 0 "$T/wt3" 'gh pr create --fill' 'a marker written from a second worktree'
[ -f "$STATE/pr-open/tmpbr" ] && ok "  …lands in the shared state" || bad "  …no pr-open/tmpbr"
git -C "$T/repo" worktree remove --force "$T/wt3" && git -C "$T/repo" worktree prune
[ -f "$STATE/pr-open/tmpbr" ] && [ -f "$STATE/pr-open/chore-x" ] && ok "  …and survives git worktree remove + prune" || bad "  …markers lost after worktree remove"
session_start repo 'SessionStart with tmpbr still a branch'
[ -f "$STATE/pr-open/tmpbr" ] && ok "  …pr-open/tmpbr kept while the branch exists" || bad "  …pr-open/tmpbr pruned early"
git -C "$T/repo" branch -q -D tmpbr chore/x 2>/dev/null
session_start repo 'SessionStart after deleting tmpbr and chore/x'
[ ! -f "$STATE/pr-open/tmpbr" ] && [ ! -f "$STATE/pr-open/chore-x" ] && ok "  …both pruned" || bad "  …markers survived: $(ls "$STATE/pr-open" | tr '\n' ' ')"
[ -f "$STATE/pr-open/feat2" ] && ok "  …pr-open/feat2 kept" || bad "  …pr-open/feat2 pruned"
scrub
