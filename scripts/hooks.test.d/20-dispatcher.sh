#!/usr/bin/env bash
# The dispatcher (bash-gate.sh), the stage payload contract, the B15 refusals,
# the heredoc rule and the lib.sh helpers. Sourced by
# scripts/hooks.test.sh.
# shellcheck shell=bash disable=SC2034,SC2154

CLAUDE_MSG='Co-Authored-By: Claude <noreply@anthropic.com>'
BAD_TS='export const x: number = "not a number";'
COMMIT_STAGES="$CHEAP deps-smoke typecheck-lint tests"

# =============================================================================
echo "== D1. the stage contract: one payload read, exported, stdin empty"
reset; stage repo apps/api/src/x.ts
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="coauthor=env" dispatch 2 repo 'git commit -m x' 'a stage sees the export'
said "PAYLOAD_SET=1"; said "CLASSES=[commit]"; said "TOP=$T/repo"; said "RAW=no"; said "STDIN=0"; said "CMD=git commit -m x"
unsaid "skills must run with the shell inside"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="push=env" dispatch 2 wt 'git commit -m x && git push origin feat' 'commit + push: both classes, the push stage after the commit stages'
said "CLASSES=[commit push]"; said "TOP=$T/wt"
stages_ran "$COMMIT_STAGES push"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="pr-open=env" dispatch 2 repo 'gh pr create --fill' 'pr-open alone'
said "CLASSES=[pr-open]"
stages_ran "pr-open"
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit -m x && git push && gh pr create --fill' 'all three classes, in order'
stages_ran "$COMMIT_STAGES push pr-open"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="coauthor=env" dispatch 2 repo "git -C $T/wt commit -m x" 'git -C <worktree> from the clone: TOP is the worktree'
said "TOP=$T/wt"; said "GIT_DIR=$T/wt"
said "skills must run with the shell inside $T/wt (cd $T/wt)"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="coauthor=env" dispatch_raw 2 '{"tool_input":{"command":"git commit -m x"' 'truncated JSON through the dispatcher: raw, still classified'
said "PAYLOAD_SET=1"; said "RAW=yes"; said "CLASSES=[commit]"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="coauthor=env" dispatch 2 other 'git commit -m x' 'another repo: the stages still get the payload (coauthor applies everywhere)'
said "TOP=$T/other"

# =============================================================================
echo "== D2. fast path, crash, timeout, aggregation"
reset
best=999999
for _ in 1 2 3; do
  : >"$FAKE_STAGE_LOG"
  t0=$(date +%s%N)
  payload 'pnpm test' "$T/repo" | CLAUDE_PROJECT_DIR="$PROJECT" HOOK_GATES_DIR=$T/fakegates bash "$HOOKS/bash-gate.sh" >/dev/null 2>&1; rc=$?
  t1=$(date +%s%N); ms=$(((t1 - t0) / 1000000)); [ "$ms" -lt "$best" ] && best=$ms
done
[ "$rc" = 0 ] && ok "dispatch(0): a non-member exits 0" || bad "dispatch: a non-member got rc $rc"
[ "$best" -lt 100 ] && ok "  …in ${best} ms (best of 3, < 100 ms)" || bad "  …but took ${best} ms (best of 3), the fast path is slower than 100 ms"
stages_ran ""
for c in 'git status' 'git log --oneline -3' 'echo "run git commit later"' "grep -rn 'git commit' .claude/hooks" 'gh pr view 12' 'git log --grep push' "cat >notes.md <<'EOF'
later: git commit -m x
EOF"; do
  HOOK_GATES_DIR=$T/fakegates dispatch 0 repo "$c"; stages_ran ""
done
stage repo apps/api/src/x.ts
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit -m x' 'every stage passes → allowed'
stages_ran "$COMMIT_STAGES"
silent
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="typecheck-lint=7" dispatch 2 repo 'git commit -m x' 'a stage exits 7 → gate crashed'
said "gate crashed: typecheck-lint rc=7"
stages_ran "$CHEAP deps-smoke typecheck-lint"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="docs-gate=7" dispatch 2 repo 'git commit -m x' 'a cheap stage crashes → in the aggregated block'
said "gate crashed: docs-gate rc=7"; said "Commit blocked by 1 gate(s)"
stages_ran "$CHEAP"
t0=$SECONDS
HOOK_GATES_DIR=$T/fakegates HOOK_DEADLINE=2 FAKE_STAGES="coauthor=sleep:5" dispatch 2 repo 'git commit -m x' 'a stage sleeps past the 2 s deadline → timed out'
said "gate timed out in coauthor after"; said "Run it yourself:"  # the budget is what is left of the 2 s deadline at 1 s granularity
[ $((SECONDS - t0)) -le 8 ] && ok "  …and the dispatcher returned in $((SECONDS - t0)) s, not the stage's 5" || bad "  …but the dispatcher took $((SECONDS - t0)) s"
HOOK_GATES_DIR=$T/fakegates HOOK_DEADLINE=2 FAKE_STAGES="typecheck-lint=remedy:5" dispatch 2 repo 'git commit -m x' 'the stage named its own remedy on fd 3'
said "gate timed out in typecheck-lint after"; said "run-me-by-hand-typecheck-lint"
HOOK_GATES_DIR=$T/fakegates HOOK_DEADLINE=2 FAKE_STAGES="tests=sleep:5" dispatch 2 repo 'git commit -m x' 'no REMEDY line → the static table'
said "gate timed out in tests after"; said "bash scripts/test-changed.sh"  # what was left of the 2 s, not a fresh 2 s
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="coauthor=2 docs-gate=2 user-docs-freshness=2" dispatch 2 repo 'git commit -m x' 'three cheap failures → one block listing all three'
said "Commit blocked by 3 gate(s)"; said "--- coauthor ---"; said "--- docs-gate ---"; said "--- user-docs-freshness ---"; said "fake user-docs-freshness: blocked"
stages_ran "$CHEAP"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="secret-block=2 deps-smoke=2" dispatch 2 repo 'git commit -m x' 'a cheap failure plus deps-smoke → the cheap block only'
said "--- secret-block ---"; unsaid "deps-smoke"
stages_ran "$CHEAP"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="deps-smoke=2" dispatch 2 repo 'git commit -m x' 'deps-smoke blocks → typecheck-lint and tests never run'
stages_ran "$CHEAP deps-smoke"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="tests=2" dispatch 2 repo 'git commit -m x' 'tests block last'
said "fake tests: blocked"
stages_ran "$COMMIT_STAGES"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="push=2" dispatch 2 repo 'git push origin feat' 'push blocks'
said "fake push: blocked"; stages_ran "push"
HOOK_GATES_DIR=$T/fakegates FAKE_STAGES="docs-gate=msg" dispatch 0 repo 'git commit -m x' 'a passing stage may leave a systemMessage'
said '"systemMessage"'; said "note from docs-gate"
mkdir -p "$T/gates-missing" && cp "$T/fakestage.sh" "$T/gates-missing/coauthor.sh"
HOOK_GATES_DIR=$T/gates-missing dispatch 2 repo 'git commit -m x' 'a stage file missing from the gates dir → fail closed'
said "gate missing: secret-block"
HOOK_GATES_DIR=$T/gates-missing dispatch 0 repo 'pnpm test' 'a non-member never notices a missing stage'

echo "== D2b. the real moved gates through the dispatcher"
reset; stage repo apps/api/src/x.ts "$BAD_TS"
HOOK_GATES_DIR=$T/gates-mixed FAKE_FAIL=typecheck dispatch 2 repo 'git commit -m x' 'staged bad TS, no docs → docs-gate in the cheap block'
said "--- docs-gate ---"; said "Code is staged without a change under internal-docs/"
unsaid "typecheck"
stage repo internal-docs/README.md '# updated'
HOOK_GATES_DIR=$T/gates-mixed FAKE_FAIL=typecheck dispatch 2 repo 'git commit -m x' 'docs staged, typecheck fails → typecheck-lint blocks'
said "--- typecheck ---"
HOOK_GATES_DIR=$T/gates-mixed FAKE_FAIL=vitest dispatch 2 repo 'git commit -m x' 'related tests fail → tests block'
said "Tests related to the staged files failed"
HOOK_GATES_DIR=$T/gates-mixed dispatch 0 repo 'git commit -m x' 'everything passes → allowed'
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo "git commit -m \"$CLAUDE_MSG\"" 'attribution → coauthor in the cheap block'
said "--- coauthor ---"; said "Claude attribution line"
stage wt apps/api/src/x.ts "$BAD_TS"
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 wt "git commit -m \"$CLAUDE_MSG\"" 'attribution + API code without docs in the worktree → both in one block'
said "Commit blocked by 2 gate(s)"; said "--- coauthor ---"; said "--- docs-gate ---"
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo "git -C $T/wt commit -m x" 'git -C <worktree> from the clone → the worktree is gated, the hint is appended'
said "--- docs-gate ---"; said "skills must run with the shell inside $T/wt"
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo 'gh pr create --fill' 'no review marker → pr-open blocks'
said "no clean AI review recorded"
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo 'git commit -m x && gh pr create --fill' 'commit + PR, commit stages pass → the PR half refuses the HEAD mover'
said "PR blocked: this command moves HEAD"
reset; stage repo apps/api/src/x.ts "$BAD_TS"
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo 'git commit -m x && gh pr create --fill' 'commit + PR, no docs staged → the commit half is gated first'
said "--- docs-gate ---"; unsaid "PR blocked"
HOOK_GATES_DIR=$T/gates-mixed dispatch_raw 2 '{"tool_input":{"command":"git commit -m x"' 'truncated JSON: the gates refuse the unreadable payload'
said "the hook payload is unreadable"

# =============================================================================
echo "== D3. the B15 shapes are refused on shape, whatever the index holds"
B15_SHAPES=('git add -A && git commit -m x' 'git add x && git commit -m x' 'git commit -am x' 'git commit -a -m x' 'git commit --all -m x' 'git commit -m x apps/api/src/auth/x.ts' 'git commit -m x -- x.ts' 'git commit --include x.ts -m x' 'git stash pop && git commit -m x')
reset
for c in "${B15_SHAPES[@]}"; do
  HOOK_GATES_DIR=$T/fakegates dispatch 2 repo "$c" "unstaged: $c → refused"
  said "stage in its own call, then commit alone"; stages_ran ""
done
reset; stage repo apps/api/src/auth/x.ts; stage repo x.ts
for c in "${B15_SHAPES[@]}"; do
  HOOK_GATES_DIR=$T/fakegates dispatch 2 repo "$c" "staged: $c → still refused, no stage spawned"
  said "stage in its own call, then commit alone"; stages_ran ""
done
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit -m x' 'the plain shape with the same index → gated normally'
stages_ran "$COMMIT_STAGES"
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit -m "fix: x" -m "User-Docs: none — a11y-only"' 'two -m values are not pathspecs'
stages_ran "$COMMIT_STAGES"
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo "git commit -F - <<'MSG'
fix: x
MSG" 'a heredoc message is not a pathspec'
stages_ran "$COMMIT_STAGES"
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit -m x 2>&1 | tail -3' 'a redirection is not a pathspec'
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit --author "A <a@b>" --trailer "X: y" -m x' 'option values are not pathspecs'
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit -uno -qm x' 'clusters: -uno takes its value, -qm x is a message'
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit -m x && git push' 'a clean shape with a push half runs the commit stages, then push'
unsaid "stage in its own call"; stages_ran "$COMMIT_STAGES push"
reset
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo 'git commit --amend --no-edit' '--amend --no-edit with nothing staged → allowed'
stages_ran "$COMMIT_STAGES"
# The gates themselves gate by state, not shape: the shape row that left section 3.
reset; stage repo apps/api/src/x.ts "$BAD_TS"
FAKE_FAIL=typecheck gate typecheck-lint 2 repo 'git add -A && git commit -m x' 'the gate alone still classifies the shape as a commit and gates the index'
gate docs-gate 2 repo 'git add -A && git commit -m x'
FAKE_FAIL=vitest gate tests 2 repo 'git add -A && git commit -m x'

# =============================================================================
echo "== D4. heredocs fed to a shell are commands, heredocs elsewhere are text"
reset; stage repo apps/api/src/x.ts "$BAD_TS"
HOOK_GATES_DIR=$T/fakegates dispatch 0 repo "cat <<'EOF'
git commit -m x
$CLAUDE_MSG
EOF" 'a mention inside a cat heredoc → not a commit'
stages_ran ""
for c in "bash <<'EOF'
git commit -m x
EOF" "bash -s <<EOF
git commit -m x
EOF" "sh <<'EOF'
git commit -m x
EOF" "/bin/bash <<'EOF'
git commit -m x
EOF" "eval <<'EOF'
git commit -m x
EOF"; do
  HOOK_GATES_DIR=$T/fakegates dispatch 0 repo "$c" 'the body runs → classified as a commit'
  stages_ran "$COMMIT_STAGES"
  FAKE_FAIL=typecheck gate typecheck-lint 2 repo "$c" 'and the gate blocks on the staged TS'
done
HOOK_GATES_DIR=$T/fakegates dispatch 2 repo "bash <<'EOF'
git add -A && git commit -m x
EOF" 'a B15 shape inside a bash heredoc is refused too'
said "stage in its own call"
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo "bash <<'EOF'
git commit -m \"$CLAUDE_MSG\"
EOF" 'attribution inside a bash heredoc → the coauthor gate sees it'
said "--- coauthor ---"
gate coauthor 2 repo "bash <<'EOF'
git commit -m \"$CLAUDE_MSG\"
EOF"

# =============================================================================
echo "== D5. the pr-open gate on both paths (the other gates: every row above)"
reset
gate pr-open 2 repo 'gh pr create --fill' 'no marker → blocked'
gate pr-open 0 repo 'git status'
gate pr-open 0 other 'gh pr create --fill' 'another repo'
gate pr-open 2 repo 'git commit -m x && gh pr create' 'HEAD mover'
raw pr-open 2 '{"tool_input":{"command":"echo hi\ngh pr create"' 'truncated JSON, PR text → blocked'
[ "$ENV_RAW" = yes ] && ok "  …HOOK_RAW=yes on the exported path" || bad "  …HOOK_RAW was '$ENV_RAW' on the exported path"
raw pr-open 0 '{"tool_input":{"command":"git commit -m x"' 'truncated JSON, no PR → allowed'
raw typecheck-lint 2 '{"tool_input":{"command":"git commit -m x"' 'truncated JSON, commit → blocked on both paths'
[ "$ENV_RAW" = yes ] && ok "  …HOOK_RAW=yes on the exported path" || bad "  …HOOK_RAW was '$ENV_RAW' on the exported path"

# =============================================================================
echo "== D6. lib.sh additions"
reset
[ "$(state_dir "$T/repo")" = "$T/repo/.git/$HOOK_CFG_STATE_DIR" ] && ok "state_dir: the main checkout, absolute" || bad "state_dir(repo) = $(state_dir "$T/repo")"
[ "$(state_dir "$T/wt")" = "$T/repo/.git/$HOOK_CFG_STATE_DIR" ] && ok "state_dir: the worktree shares it" || bad "state_dir(wt) = $(state_dir "$T/wt")"
[ "$(cd "$T" && state_dir "$T/wt")" = "$T/repo/.git/$HOOK_CFG_STATE_DIR" ] && ok "state_dir: resolved from /tmp, never under \$PWD" || bad "state_dir from tmp = $(cd "$T" && state_dir "$T/wt")"
[ "$(hook_slug chore/x)" = chore-x ] && ok "hook_slug chore/x → chore-x" || bad "hook_slug: $(hook_slug chore/x)"
[ "$(hook_slug 'feat/a b(c)/d')" = 'feat-abc-d' ] && ok "hook_slug drops what gstack-slug drops" || bad "hook_slug: $(hook_slug 'feat/a b(c)/d')"

seed "$T/wt" internal-docs/x.md '# x'; g -C "$T/wt" add -A; commit wt docs
seed "$T/wt" apps/api/src/y.ts 'export const y = 1;'; g -C "$T/wt" add -A; commit wt code
git -C "$T/wt" mv apps/api/src/x.ts internal-docs/moved.md; commit wt "rename code to docs"
changed_paths "$BASE" HEAD "$T/wt"
[ "${#CHANGED[@]}" = 4 ] && ok "changed_paths: --no-renames lists both sides of a rename (${#CHANGED[@]} paths)" || bad "changed_paths: ${CHANGED[*]}"
case " ${CHANGED[*]} " in *" apps/api/src/x.ts "*) ok "  …the deleted code path is there" ;; *) bad "  …deleted side missing: ${CHANGED[*]}" ;; esac
changed_status "$BASE" HEAD "$T/wt" | tr '\0' '\n' | grep -q '^D$' && ok "changed_status: a D row, not an R" || bad "changed_status: $(changed_status "$BASE" HEAD "$T/wt" | tr '\0' ' ')"
walk=$(first_parent_walk HEAD 20 "$T/wt" | wc -l)
[ "$walk" = 3 ] && ok "first_parent_walk: the three branch commits, not the one on origin/main" || bad "first_parent_walk: $walk shas"
[ "$(first_parent_walk HEAD 1 "$T/wt" | wc -l)" = 2 ] && ok "first_parent_walk: MAX bounds the ancestors" || bad "first_parent_walk MAX=1: $(first_parent_walk HEAD 1 "$T/wt" | wc -l)"
[ -z "$(first_parent_walk "$BASE" 20 "$T/wt")" ] && ok "first_parent_walk: a start on origin/main prints nothing" || bad "first_parent_walk from main printed shas"
k0=$(lifecycle_key "$T/wt" "$BASE"); k1=$(lifecycle_key "$T/wt" "HEAD~2"); k2=$(lifecycle_key "$T/wt" HEAD)
[ "$k0" = "$k1" ] && ok "lifecycle_key: a docs commit keeps the key" || bad "lifecycle_key changed on a docs commit"
[ "$k1" != "$k2" ] && ok "lifecycle_key: an apps/api change turns it" || bad "lifecycle_key unchanged after an apps/api change"
d0=$(deps_key "$T/wt" "$BASE"); d1=$(deps_key "$T/wt" HEAD)
[ "$d0" = "$d1" ] && ok "deps_key: code and docs commits keep it" || bad "deps_key changed without a manifest change"
seed "$T/wt" apps/api/package.json '{"name":"@acme/api","version":"2"}'; g -C "$T/wt" add -A; commit wt "api manifest"
[ "$(deps_key "$T/wt" HEAD)" != "$d0" ] && ok "deps_key: apps/api/package.json turns it" || bad "deps_key unchanged after apps/api/package.json"

g -C "$T/wt" commit -q --allow-empty -m "feat: x" -m "User-Docs: none — nothing visible"
HOOK_CWD=$T/wt
commit_message_from_command 'git commit --amend --no-edit'
case $MESSAGE in *"User-Docs: none"*) ok "commit_message_from_command: --amend --no-edit reuses HEAD's message" ;; *) bad "--amend --no-edit: $MESSAGE" ;; esac
commit_message_from_command 'git commit --amend -m "other"'
case $MESSAGE in *"User-Docs: none"*) bad "--amend -m must not reuse HEAD's message" ;; *) ok "commit_message_from_command: --amend -m replaces the message" ;; esac
commit_message_from_command 'git commit --amend --no-edit --trailer "Refs: #12"'
case $MESSAGE in *"Refs: #12"*"User-Docs: none"*) ok "commit_message_from_command: --amend with a trailer keeps both" ;; *) bad "--amend --trailer: $MESSAGE" ;; esac
commit_message_from_command 'git commit -c HEAD'
case $MESSAGE in *"User-Docs: none"*) ok "commit_message_from_command: -c HEAD reuses it" ;; *) bad "-c HEAD: $MESSAGE" ;; esac
commit_message_from_command "git commit --fixup=$(git -C "$T/wt" rev-parse HEAD)"
case $MESSAGE in *"User-Docs: none"*) ok "commit_message_from_command: --fixup=<sha> reads that commit" ;; *) bad "--fixup: $MESSAGE" ;; esac
commit_message_from_command 'git commit -C HEAD~1'
case $MESSAGE in *"api manifest"*) ok "commit_message_from_command: -C HEAD~1 reads that commit, not HEAD" ;; *) bad "-C HEAD~1: $MESSAGE" ;; esac
commit_message_from_command 'git commit -m x'
case $MESSAGE in *"User-Docs: none"*) bad "a plain -m must not pull HEAD's message" ;; *) ok "commit_message_from_command: a plain -m reuses nothing" ;; esac
HOOK_CWD=''
rewind wt

v=$(docs_only_verdict internal-docs/x.md apps/docs/en/y.md); [ "$v" = docs ] && ok "docs_only_verdict: md pages → docs" || bad "docs_only_verdict: $v"
v=$(docs_only_verdict internal-docs/x.md apps/api/src/x.ts) || true; [ "$v" = never ] && ok "docs_only_verdict: a .ts in the set → never" || bad "docs_only_verdict: $v"
v=$(docs_only_verdict); [ "$v" = docs ] && ok "docs_only_verdict: an empty delta is docs-only" || bad "docs_only_verdict empty: $v"
if v=$(HOOK_REVIEW_MAP_SCRIPT=/nonexistent.mjs docs_only_verdict internal-docs/x.md); then bad "docs_only_verdict: a missing map reader must not pass"; else ok "docs_only_verdict: a missing map reader fails closed"; fi
for p in apps/api/src/testing/x.ts apps/api/src/config/env.validation.ts apps/api/src/auth/__mocks__/x.ts x.spec.ts x.test.ts README.md .env.example "$T/repo/apps/api/src/testing/x.ts"; do
  secret_exempt_path "$p" && ok "secret_exempt_path: $p" || bad "secret_exempt_path should exempt $p"
done
for p in apps/api/src/auth/auth.controller.ts packages/validators/src/x.ts apps/api/src/testing.ts x.stories.tsx key.txt; do
  secret_exempt_path "$p" && bad "secret_exempt_path must not exempt $p" || ok "secret_exempt_path: $p is scanned"
done
r=$(hook_remedy 'x' 2>&1); [ -z "$r" ] && ok "hook_remedy: silent without fd 3" || bad "hook_remedy printed: $r"
r=$(hook_remedy 'run me' 3>&1 >/dev/null 2>&1); [ "$r" = "REMEDY: run me" ] && ok "hook_remedy: writes the REMEDY line to fd 3" || bad "hook_remedy fd 3: $r"
classify_command 'git push origin feat' && [ "$HOOK_CLASSES" = push ] && ok "classify_command: push" || bad "classify: $HOOK_CLASSES"
classify_command 'git -C /a push --force-with-lease' && [ "$HOOK_GIT_DIR" = /a ] && ok "is_git_push_command: -C resolves like commit" || bad "push -C: $HOOK_GIT_DIR"
if classify_command 'echo hi'; then bad "classify_command matched echo"; elif [ -z "$HOOK_CLASSES" ]; then ok "classify_command: no class → returns 1, HOOK_CLASSES empty"; else bad "classify_command: HOOK_CLASSES=$HOOK_CLASSES"; fi
classify_command "gh api graphql -f query='mutation { createPullRequest(input: {}) { clientMutationId } }'" && in_class pr-open && ok "opens_pr_command: the GraphQL mutation" || bad "graphql not classified"
