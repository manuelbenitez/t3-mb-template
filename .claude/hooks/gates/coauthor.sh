#!/usr/bin/env bash
# Commit stage (cheap tier): block a commit whose message carries a Claude
# attribution line (Co-Authored-By: Claude, "Generated with Claude Code", the
# noreply address, a session link), when project.attribution_guard is true.
# Applies to every repo a session commits in, not only this one. A reused
# message (--amend --no-edit, -C, --fixup) is read from that commit (B5).
# Silent on pass.
# Standalone: bash .claude/hooks/gates/coauthor.sh < payload.json
set -u
. "$(dirname "$0")/../lib.sh"
hook_read_payload
is_git_commit_command || exit 0
hook_config || { echo "❌ Attribution guard: cannot read .claude/review-map.yml (node scripts/review-map.mjs check)." >&2; exit 2; }
[ "$HOOK_CFG_ATTRIBUTION_GUARD" = yes ] || exit 0
hook_remedy 'git log -1 --format=%B | grep -iE "claude|anthropic"'

# The message is the command text, any -F file and any reused commit message.
commit_message_from_command

if printf '%s\n' "$MESSAGE" | grep -qiE 'co-authored-by:\s*claude|generated with \[?claude code\]?|noreply@anthropic\.com|claude\.ai/code/session'; then
  {
    echo "❌ Commit blocked: message contains a Claude attribution line."
    echo ""
    echo "Remove any of:"
    echo "  • Co-Authored-By: Claude ..."
    echo "  • 🤖 Generated with [Claude Code](...)"
    echo "  • noreply@anthropic.com"
    echo "  • a claude.ai/code/session link"
    echo ""
    echo "Rewrite the commit message without those lines and retry (an amend or -C reuses the old message: pass a new -m)."
  } >&2
  exit 2
fi

exit 0
