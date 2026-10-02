#!/usr/bin/env bash
# Commit stage: run the tests related to the staged files and block if any
# fails. Scoped, not the whole suite: the same scripts/test-changed.sh the CI
# test job runs. Silent on pass. Runs under the
# dispatcher (bash-gate.sh, the exported payload) or alone on a piped one.
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload
is_git_commit_command || exit 0
# Fail closed: with no readable payload there is no cwd, so the tree this
# commit is for is unknown. A clean session root must not stand in for it.
[ "$HOOK_RAW" = yes ] && {
  echo "❌ Tests-on-commit: the hook payload is unreadable (jq missing or malformed JSON), so the tree this commit is for is unknown. Fix that and retry." >&2
  exit 2
}

# The tree the commit is for: the dispatcher's TOP, else `git -C` / `cd` in the
# command, else the payload cwd. Never the session root, which from a worktree
# is the wrong index.
[ "${HOOK_PAYLOAD_SET:-}" = 1 ] && [ -n "${TOP:-}" ] || TOP=$(repo_top) || {
  echo "❌ Tests-on-commit: cannot resolve the repository this commit runs in (${HOOK_GIT_DIR:-${HOOK_CWD:-?}}). Use a plain absolute path, or run the commit from inside the repo." >&2
  exit 2
}
is_project_repo "$TOP" || exit 0
cd "$TOP" || exit 2

staged_paths "$TOP"
CODE=()
for f in "${STAGED[@]}"; do
  # Code, plus the hooks themselves: the router runs scripts/hooks.test.sh for those.
  case $f in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|.claude/hooks/*.sh|scripts/hooks.test.sh|scripts/hooks.test.d/*.sh) CODE+=("$f") ;; esac
done
[ ${#CODE[@]} -eq 0 ] && exit 0
hook_remedy "bash scripts/test-changed.sh ${CODE[*]}"

# The suites must not inherit the dispatcher's payload export (the hook harness
# would read it instead of its own rows' payloads).
OUT=$(env -u HOOK_PAYLOAD_SET -u HOOK_CMD -u HOOK_CWD -u HOOK_FILE -u HOOK_RAW -u HOOK_GIT_DIR -u HOOK_CLASSES -u TOP \
  bash scripts/test-changed.sh "${CODE[@]}" 2>&1)
[ $? -eq 0 ] && exit 0
{
  echo "❌ Tests related to the staged files failed:"
  echo ""
  echo "$OUT" | tail -60
  echo ""
  echo "Fix them, or run them yourself: bash scripts/test-changed.sh ${CODE[*]}"
} >&2
exit 2
