#!/usr/bin/env bash
# Commit stage: the workspace typecheck and eslint on the staged files from
# each file's own package. Silent on pass, blocks with the output on fail. Runs
# under the dispatcher (bash-gate.sh, the exported payload) or alone on a piped
# one. A project tripwire (a banned import, a parse guard) belongs here as one
# more `pnpm <script>` step before the typecheck.
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload

# Only fire on git commit commands. Ignore commit --amend --no-edit with no staged TS, etc.
is_git_commit_command || exit 0
# Fail closed: with no readable payload there is no cwd, so the tree this
# commit is for is unknown. A clean session root must not stand in for it.
[ "$HOOK_RAW" = yes ] && {
  echo "❌ Pre-commit gate: the hook payload is unreadable (jq missing or malformed JSON), so the tree this commit is for is unknown. Fix that and retry." >&2
  exit 2
}

# The tree the commit is for: the dispatcher's TOP, else `git -C` / `cd` in the
# command, else the payload cwd. Never the session root, which from a worktree
# is the wrong index.
[ "${HOOK_PAYLOAD_SET:-}" = 1 ] && [ -n "${TOP:-}" ] || TOP=$(repo_top) || {
  echo "❌ Pre-commit gate: cannot resolve the repository this commit runs in (${HOOK_GIT_DIR:-${HOOK_CWD:-?}}). Use a plain absolute path, or run the commit from inside the repo." >&2
  exit 2
}
is_project_repo "$TOP" || exit 0
cd "$TOP" || exit 2
hook_remedy 'pnpm typecheck && pnpm lint'

staged_paths "$TOP"
STAGED_TS=$(printf '%s\n' "${STAGED[@]}" | grep -E '\.(ts|tsx|js|jsx|mjs|cjs)$' || true)
[ -z "$STAGED_TS" ] && exit 0

# Run typecheck (turbo-cached, fast on no-change subtrees)
TC_OUT=$(pnpm typecheck 2>&1)
TC_RC=$?

# Lint staged files from their own package; a file outside a package with an
# eslint config (scripts/, the root) is skipped here.
LINT_OUT=""
LINT_RC=0
for pkg in $(echo "$STAGED_TS" | grep -oE '^(apps|packages|tooling)/[^/]+' | sort -u); do
  ls "$pkg"/eslint.config.* >/dev/null 2>&1 || continue
  files=$(echo "$STAGED_TS" | grep -E "^$pkg/" | sed "s#^$pkg/##")
  out=$(cd "$pkg" && echo "$files" | tr '\n' '\0' | xargs -0 pnpm exec eslint --no-warn-ignored 2>&1)
  if [ $? -ne 0 ]; then
    LINT_RC=1
    LINT_OUT+="[$pkg]"$'\n'"$out"$'\n'
  fi
done

if [ $TC_RC -eq 0 ] && [ $LINT_RC -eq 0 ]; then
  exit 0
fi

# Block the commit
{
  echo "❌ Pre-commit gate failed. Fix these before committing:"
  echo ""
  if [ $TC_RC -ne 0 ]; then
    echo "--- typecheck ---"
    echo "$TC_OUT" | tail -40
    echo ""
  fi
  if [ $LINT_RC -ne 0 ]; then
    echo "--- eslint on staged files ---"
    echo "$LINT_OUT" | tail -40
  fi
  echo ""
  echo "Run them yourself: pnpm typecheck && pnpm lint"
} >&2
exit 2
