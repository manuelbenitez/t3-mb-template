#!/usr/bin/env bash
# The core rows, sourced by scripts/hooks.test.sh: which tree a commit is judged
# against (worktrees, -C, cd), flag-tolerant matching, heredocs, the co-author,
# docs and tests gates, the stop hook and failing closed. Every row runs through
# `gate`/`raw`, which exercise both payload paths; `git add -A && git commit`
# lives with the B15 refusal rows in 20-dispatcher.sh.
# shellcheck shell=bash disable=SC2034,SC2154

GATES="typecheck-lint docs-gate tests"
CLAUDE_MSG='Co-Authored-By: Claude <noreply@anthropic.com>'
BAD_TS='export const x: number = "not a number";'

# =============================================================================
echo "== 1. a commit from a linked worktree is checked against THAT tree, not the session root"
reset; stage wt apps/api/src/x.ts "$BAD_TS"
FAKE_FAIL=typecheck gate typecheck-lint 2 wt 'git commit -m x' 'staged TS in the worktree, typecheck fails → blocked'
pnpm_ran "^$T/wt${TAB}.*typecheck" && ok "  …typecheck ran in the worktree" || bad "  …typecheck did not run in the worktree"
gate docs-gate 2 wt 'git commit -m x' 'API code staged in the worktree, no internal-docs → blocked'
FAKE_FAIL=vitest gate tests 2 wt 'git commit -m x' 'related tests fail in the worktree → blocked'
: >"$FAKE_PNPM_LOG"
FAKE_FAIL=typecheck gate typecheck-lint 2 wt/apps/api 'git commit -m x' 'from a subdirectory of the worktree → blocked'
pnpm_ran "^$T/wt${TAB}.*typecheck" && ok "  …typecheck ran at the worktree top" || bad "  …typecheck did not run at the worktree top: $(cat "$FAKE_PNPM_LOG")"
PROJECT='' FAKE_FAIL=typecheck gate typecheck-lint 2 wt 'git commit -m x' 'with CLAUDE_PROJECT_DIR empty → still the worktree'

echo "== 2. the same commit from the clone itself"
reset; stage repo apps/api/src/x.ts "$BAD_TS"
FAKE_FAIL=typecheck gate typecheck-lint 2 repo 'git commit -m x'
gate docs-gate 2 repo 'git commit -m x'
FAKE_FAIL=vitest gate tests 2 repo 'git commit -m x'
: >"$FAKE_PNPM_LOG"
FAKE_FAIL=eslint gate typecheck-lint 2 repo 'git commit -m x' 'eslint fails on the staged file → blocked'
pnpm_ran "^$T/repo/apps/api${TAB}exec${TAB}eslint" && ok "  …eslint ran from apps/api" || bad "  …eslint did not run from apps/api: $(cat "$FAKE_PNPM_LOG")"
gate typecheck-lint 0 repo 'git commit -m x' 'typecheck and lint pass → allowed'

echo "== 2b. the converse: the session root is dirty, the worktree is clean → nothing to gate"
reset; stage repo apps/api/src/x.ts "$BAD_TS"
for h in $GATES; do FAKE_FAIL="typecheck vitest" gate "$h" 0 wt 'git commit -m x' 'clean worktree, dirty session root → allowed'; done
pnpm_ran "${TAB}typecheck" && bad "  …but typecheck ran (against the session root?)" || ok "  …and no typecheck ran"

# =============================================================================
echo "== 3. flag-tolerant matching: git's own options before the verb"
reset; stage repo apps/api/src/x.ts "$BAD_TS"
for c in \
  'git -c core.editor=true commit -m x' 'git -c a=b -c c=d commit -m x' 'git --no-pager commit -m x' \
  '/usr/bin/git commit -m x' 'pnpm test; git commit -m x' \
  'GIT_EDITOR=true git commit -m x' 'git   commit   -m x' "bash -c 'git commit -m x'" 'eval "git commit -m x"' \
  '"git" commit -m x' 'git -C . commit -m x' 'cd apps/api && git commit -m x' 'git commit --amend --no-edit' \
  'git commit -m "docs: explain the git commit gate"'; do
  FAKE_FAIL=typecheck gate typecheck-lint 2 repo "$c"
  gate docs-gate 2 repo "$c"
  FAKE_FAIL=vitest gate tests 2 repo "$c"
done
FAKE_FAIL=typecheck gate typecheck-lint 2 repo 'git commit \
  -m x' 'line continuation'

echo "== 4. git -C <dir>: the gates check <dir>, wherever the shell sits"
reset; stage wt apps/api/src/x.ts "$BAD_TS"
FAKE_FAIL=typecheck gate typecheck-lint 2 repo "git -C $T/wt commit -m x" 'git -C <worktree> from the clean clone → blocked'
pnpm_ran "^$T/wt${TAB}.*typecheck" && ok "  …typecheck ran in the worktree" || bad "  …typecheck did not run in the worktree"
gate docs-gate 2 repo "git -C $T/wt commit -m x" 'git -C <worktree> from the clean clone → blocked'
FAKE_FAIL=vitest gate tests 2 repo "git -C $T/wt commit -m x" 'git -C <worktree> from the clean clone → blocked'
: >"$FAKE_PNPM_LOG"
FAKE_FAIL=typecheck gate typecheck-lint 2 tmp 'git -C wt commit -m x' 'relative -C resolves against cwd'
pnpm_ran "^$T/wt${TAB}.*typecheck" && ok "  …typecheck ran in the worktree" || bad "  …typecheck did not run in the worktree (resolved against the harness's own cwd?)"
FAKE_FAIL=typecheck gate typecheck-lint 2 other "git -C $T/wt commit -m x" 'git -C <worktree> from an unrelated repo → blocked'
stage other apps/api/src/x.ts "$BAD_TS"
for h in $GATES; do FAKE_FAIL="typecheck vitest" gate "$h" 0 wt "git -C $T/other commit -m x" 'git -C <unrelated repo> from the dirty worktree → allowed'; done

# =============================================================================
echo "== 5. another repo is not this gate's business"
reset; stage other apps/api/src/x.ts "$BAD_TS"
for h in $GATES coauthor; do FAKE_FAIL="typecheck vitest" gate "$h" 0 other 'git commit -m x'; done
dirty other apps/api/src/x.ts
FAKE_FAIL=typecheck stop_hook 0 other 'dirty TS in an unrelated repo → not our business'
pnpm_silent && ok "  …and pnpm was never called" || bad "  …but pnpm was called: $(head -1 "$FAKE_PNPM_LOG")"

echo "== 6. nothing staged → silent pass"
reset
for w in wt repo; do
  for h in $GATES coauthor; do
    FAKE_FAIL="typecheck vitest" gate "$h" 0 "$w" 'git commit -m x'; silent
  done
done

# =============================================================================
echo "== 7. heredocs: the body of a commit's -F - IS the message; a body elsewhere is just text"
reset; stage repo apps/api/src/x.ts "$BAD_TS"
gate coauthor 2 repo "git commit -F - <<'MSG'
chore: the guard reads what git commit is given
$CLAUDE_MSG
MSG" 'attribution in a heredoc commit message → blocked'
FAKE_FAIL=typecheck gate typecheck-lint 2 repo "git commit -F - <<'MSG'
fix: something
MSG" 'heredoc commit message still gates'
gate docs-gate 2 repo "git commit -F - <<'MSG'
fix: something
MSG" 'heredoc commit message still gates'
: >"$FAKE_PNPM_LOG"
for c in "cat >notes.md <<'EOF'
later: git commit -m x
$CLAUDE_MSG
EOF" "grep -rn 'git commit' .claude/hooks" 'echo "run git commit later"' 'git status' 'git log --oneline -3' 'pnpm test'; do
  for h in $GATES coauthor; do FAKE_FAIL="typecheck vitest" gate "$h" 0 repo "$c"; done
done
pnpm_silent && ok "  …and none of them ran pnpm" || bad "  …but a non-commit ran pnpm: $(head -1 "$FAKE_PNPM_LOG")"

# =============================================================================
echo "== 8. the co-author guard"
reset
gate coauthor 2 wt "git commit -m \"$CLAUDE_MSG\""
gate coauthor 2 wt "git -c x commit -m \"$CLAUDE_MSG\""
gate coauthor 2 wt "git -c core.editor=true commit -m 'fix: x' -m '$CLAUDE_MSG'"
gate coauthor 2 tmp "git -C $T/wt commit -m \"$CLAUDE_MSG\""
gate coauthor 2 wt 'git commit -m "🤖 Generated with [Claude Code](https://claude.com/claude-code)"'
gate coauthor 2 wt 'git commit --amend -m "x" --trailer "Co-Authored-By: Claude <x@y>"'
gate coauthor 0 wt 'git commit -m "fix: x"'
gate coauthor 0 wt 'git commit -m "docs: explain the no-claude-coauthor guard"'
gate coauthor 0 wt "grep -rn '$CLAUDE_MSG' ."

# =============================================================================
echo "== 9. the docs gate"
reset; stage repo apps/api/src/y.ts
gate docs-gate 2 repo 'git commit -m x' 'API code without internal-docs → blocked'
stage repo internal-docs/README.md '# updated'
gate docs-gate 0 repo 'git commit -m x' 'API code with internal-docs → allowed'
reset; stage repo apps/api/src/y.spec.ts
gate docs-gate 0 repo 'git commit -m x' 'a spec alone needs no docs'
reset; stage repo apps/nextjs/src/app/x.tsx; stage repo internal-docs/frontend/x.md
gate docs-gate 2 repo 'git commit -m "feat: x"' 'portal screen without apps/docs/en or a trailer → blocked'
gate docs-gate 0 repo 'git commit -m "feat: x" -m "User-Docs: none — a11y-only change"' 'User-Docs trailer in -m → allowed'
gate docs-gate 0 repo "git commit -F - <<'MSG'
feat: x

User-Docs: none — a11y-only change
MSG" 'User-Docs trailer in a heredoc message → allowed'
gate docs-gate 2 repo 'git commit -m "feat: x" -m "User-Docs: none"' 'a trailer with no reason → blocked'
stage repo apps/docs/en/x.md '# x'
gate docs-gate 0 repo 'git commit -m "feat: x"' 'portal screen with apps/docs/en → allowed'

echo "== 9b. the docs gate reads a -F <file> from the tree it checks"
reset; stage wt apps/nextjs/src/app/x.tsx; stage wt internal-docs/frontend/x.md
printf 'feat: x\n\nUser-Docs: none — a11y-only change\n' >"$T/wt/msg.txt"
gate docs-gate 2 wt 'git commit -m "feat: x"' 'portal screen in the worktree, no trailer → blocked'
gate docs-gate 0 wt 'git commit -F msg.txt' 'User-Docs trailer in -F <file>, resolved in the worktree → allowed'

# =============================================================================
echo "== 10. tests-on-commit hands the staged paths, spaces and parentheses intact, to the router of the tree it checks"
for w in repo wt; do
  reset; stage "$w" apps/api/src/x.ts 'export const x = 2;'; stage "$w" 'apps/api/src/a (b) c.ts' 'export const c = 1;'
  gate tests 0 "$w" 'git commit -m x' 'related tests pass → allowed'
  d=$(where "$w")
  pnpm_ran "^$d${TAB}.*vitest.*${TAB}src/a (b) c.ts\(${TAB}\|$\)" && ok "  …vitest ran in $w with 'src/a (b) c.ts'" || bad "  …vitest was not given 'src/a (b) c.ts' from $w: $(cat "$FAKE_PNPM_LOG")"
  pnpm_ran "vitest.*${TAB}src/x.ts\(${TAB}\|$\)" && ok "  …and with src/x.ts" || bad "  …and not with src/x.ts"
  FAKE_FAIL=vitest gate tests 2 "$w" 'git commit -m x' 'related tests fail → blocked'
done

# =============================================================================
echo "== 11. typecheck-on-stop follows the payload cwd"
reset; dirty wt apps/api/src/x.ts
FAKE_FAIL=typecheck stop_hook 2 wt 'dirty TS in the worktree, typecheck fails → wakes'
pnpm_ran "^$T/wt${TAB}.*typecheck" && ok "  …typecheck ran in the worktree" || bad "  …typecheck did not run in the worktree: $(cat "$FAKE_PNPM_LOG")"
: >"$FAKE_PNPM_LOG"
FAKE_FAIL=typecheck stop_hook 0 repo 'clean clone → silent'
silent
pnpm_silent && ok "  …and no typecheck ran" || bad "  …but typecheck ran: $(cat "$FAKE_PNPM_LOG")"

# =============================================================================
echo "== 12. an unparseable payload, or an unresolvable tree, fails closed"
reset # the session root is clean: a gate that guesses it from a payload with no cwd would let the commit through
for h in $GATES; do
  raw "$h" 2 '{"tool_input":{"command":"git commit -m x"' 'truncated JSON, commit-looking text → blocked'
  raw "$h" 2 '{"tool_input":{"command":"git -c x commit -m x"' 'truncated JSON, git -c commit → blocked'
  raw "$h" 2 '{"tool_input":{"command":"echo hi\ngit commit -m x"' 'truncated JSON, commit on line 2 → blocked'
  raw "$h" 0 '{"tool_input":{"command":"echo hi"' 'truncated JSON, non-commit text → allowed'
  raw "$h" 0 '' 'empty stdin → allowed'
  gate "$h" 2 wt 'git -C /nonexistent commit -m x' 'git -C <no such dir> → blocked'
  gate "$h" 2 wt 'cd /nonexistent && git commit -m x' 'cd <no such dir> && commit → blocked'
  gate "$h" 2 tmp 'git commit -m x' 'cwd is not a repo and no -C → blocked'
done
raw coauthor 2 "{\"tool_input\":{\"command\":\"git commit -m \\\"$CLAUDE_MSG\\\"\"" 'truncated JSON, attribution → blocked'
raw coauthor 0 '{"tool_input":{"command":"git commit -m x"' 'truncated JSON, clean message → allowed'

