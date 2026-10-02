#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): after an edit under packages/ui, check every
# @acme/ui subpath export is documented in internal-docs/frontend/component-library.md.
# Non-blocking: lists undocumented exports so they're fixed while editing.
set -u
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE" in */packages/ui/src/*|*/packages/ui/package.json|packages/ui/*) ;; *) exit 0 ;; esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
PKG="packages/ui/package.json"
DOC="internal-docs/frontend/component-library.md"
[ -f "$PKG" ] && [ -f "$DOC" ] || exit 0

missing=""
while IFS= read -r sub; do
  [ -z "$sub" ] && continue
  base="${sub#./}"
  grep -qE "(\./|@acme/ui/)${base}([^a-zA-Z0-9-]|$)" "$DOC" || missing="${missing}  • ${sub}"$'\n'
done < <(jq -r '.exports | keys[] | select(. != ".")' "$PKG" 2>/dev/null)
[ -z "$missing" ] && exit 0

MSG="📚 @acme/ui exports not documented in internal-docs/frontend/component-library.md:"$'\n'"${missing}"$'\n'"Document them now (or remove a dangling export)."
jq -n --arg m "$MSG" '{systemMessage:$m, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
