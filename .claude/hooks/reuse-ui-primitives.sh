#!/usr/bin/env bash
# PreToolUse hook (Edit|Write): when about to CREATE a new frontend component
# whose name looks like a primitive (button, dialog, table, badge…), nudge to
# reuse or extend @acme/ui instead. Fires only for new .tsx files under the
# portal or packages/ui. Non-blocking systemMessage. Silent otherwise.
set -u

f=$(jq -r '.tool_input.file_path // empty')
[ -z "$f" ] && exit 0

# Only new files: editing an existing file is not inventing.
[ -e "$f" ] && exit 0
echo "$f" | grep -qE '(apps/nextjs/src/|packages/ui/src/).*\.tsx$' || exit 0

case "$f" in
  *Button.tsx|*Input.tsx|*Select.tsx|*Dialog.tsx|*Modal.tsx|*Card.tsx|*Tooltip.tsx|*Table.tsx|*Badge*.tsx|*Pill*.tsx|*Sheet*.tsx|*Drawer.tsx)
    hint="Check @acme/ui first (internal-docs/frontend/component-library.md, or \`pnpm ui-add <name>\` for a shadcn component); extend a primitive rather than fork it." ;;
  *) exit 0 ;;
esac

jq -n --arg h "$hint" '{systemMessage: ("♻️  New component: reuse before you invent. " + $h)}'
