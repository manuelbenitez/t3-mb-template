#!/usr/bin/env bash
# PostToolUse hook: per-file prettier --write and eslint --fix on the edited file.
# Sub-second, no tokens, no model interaction. Silent on success.

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[ -z "$f" ] && exit 0
[ -f "$f" ] || exit 0

PROJECT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Only operate on files inside the project
case "$f" in
  "$PROJECT"/*) ;;
  *) exit 0 ;;
esac

# Skip generated/vendor paths
case "$f" in
  *node_modules/*|*/dist/*|*/.next/*|*/.turbo/*|*/.cache/*) exit 0 ;;
esac

cd "$PROJECT" || exit 0

# Prettier handles many extensions
case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.md|*.mdx|*.yaml|*.yml|*.css|*.scss|*.html)
    pnpm exec prettier --write --log-level warn "$f" >/dev/null 2>&1 || true
    ;;
esac

# ESLint --fix only on JS/TS, from the file's own package (each package owns
# its eslint config).
case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    rel="${f#"$PROJECT"/}"
    pkg=$(echo "$rel" | grep -oE '^(apps|packages|tooling)/[^/]+')
    if [ -n "$pkg" ] && ls "$pkg"/eslint.config.* >/dev/null 2>&1; then
      (cd "$pkg" && pnpm exec eslint --fix --no-warn-ignored "${rel#"$pkg"/}") >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
