#!/usr/bin/env bash
# format-on-edit.sh: prettier and eslint --fix on the edited file, the jsdoc/*
# errors left after the fix fed back as a block, and the nudge on added `//`
# comments. The fake pnpm prints FAKE_ESLINT_JSON for an eslint call.
# Sourced by scripts/hooks.test.sh.
# shellcheck shell=bash disable=SC2034,SC2154

JSDOC_ERR='[{"messages":[{"ruleId":"jsdoc/require-jsdoc","severity":2,"message":"Missing JSDoc comment","line":3,"column":8}]}]'
NOT_JSDOC='[{"messages":[{"ruleId":"jsdoc/require-param","severity":1,"message":"a warning","line":1,"column":1},{"ruleId":"no-undef","severity":2,"message":"x is not defined","line":2,"column":1}]}]'
CLEAN='[{"messages":[]}]'
SRC="$T/repo/apps/api/src/x.ts"
fmt() { # fmt <file> <old_string> <new_string> <label>   — format-on-edit.sh on an Edit payload
  OUT=$(jq -n --arg f "$1" --arg o "$2" --arg n "$3" '{hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}' |
    CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/format-on-edit.sh" 2>&1); RC=$?
  [ "$RC" = 0 ] && ok "format-on-edit(0): $4" || bad "format-on-edit: $4 got rc $RC: $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
}
fmt_write() { # fmt_write <file> <content> <label>   — format-on-edit.sh on a Write payload
  OUT=$(jq -n --arg f "$1" --arg c "$2" '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$f,content:$c}}' |
    CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/format-on-edit.sh" 2>&1); RC=$?
  [ "$RC" = 0 ] && ok "format-on-edit(0): $3" || bad "format-on-edit: $3 got rc $RC: $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
}

# =============================================================================
echo "== F1. a jsdoc error left after --fix is fed back as a block"
reset
export FAKE_ESLINT_JSON="$JSDOC_ERR"
fmt "$SRC" '' 'export const y = 2;' 'a missing JSDoc → block naming the line and the rule'
said '"decision": "block"'; said "apps/api/src/x.ts: JSDoc missing"; said "3:8 Missing JSDoc comment (jsdoc/require-jsdoc)"
pnpm_ran "^$T/repo/apps/api${TAB}exec${TAB}eslint${TAB}--fix${TAB}--no-warn-ignored${TAB}--format${TAB}json${TAB}src/x.ts$" &&
  ok "  …one eslint run, from the file's package, --fix with a json report" || bad "  …eslint calls: $(tr '\t' ' ' <"$FAKE_PNPM_LOG")"
export FAKE_FAIL="eslint"
fmt "$SRC" '' 'export const y = 2;' 'eslint exits 1 on an error, as the real one does → still the block'
said '"decision": "block"'
unset FAKE_FAIL

echo "== F2. what is not a jsdoc error stays silent"
export FAKE_ESLINT_JSON="$NOT_JSDOC"
fmt "$SRC" '' 'export const y = 2;' 'a jsdoc warning and a non-jsdoc error → silent'; silent
export FAKE_ESLINT_JSON="not json"
fmt "$SRC" '' 'export const y = 2;' 'an unreadable eslint report → silent, fails open'; silent
unset FAKE_ESLINT_JSON
fmt "$SRC" '' 'export const y = 2;' 'no report at all → silent'; silent

echo "== F3. added // comments get the nudge"
export FAKE_ESLINT_JSON="$CLEAN"
fmt "$SRC" 'const a = 1;' $'// set a\nconst a = 1; // one\n' 'two added comments, one trailing → the nudge'
said '"additionalContext"'; said "this edit adds 2"; unsaid '"decision"'
fmt "$SRC" '' $'// eslint-disable-next-line no-console\n// @ts-expect-error legacy\n/// <reference types="node" />\nconst u = "http://x";\n// prettier-ignore\n' 'directives, a triple-slash and a URL → silent'; silent
fmt "$SRC" $'// keep\nconst a = 1;' $'// keep\nconst a = 2;' 'an edit that keeps its existing comment → silent'; silent
fmt_write "$SRC" $'// header\nexport const w = 1;\n' 'a Write counts its whole content'
said "this edit adds 1"
export FAKE_ESLINT_JSON="$JSDOC_ERR"
fmt "$SRC" '' $'// what\nexport const z = 3;' 'a jsdoc error and an added comment → one block carrying both'
said '"decision": "block"'; said "jsdoc/require-jsdoc"; said "this edit adds 1"

echo "== F4. paths it leaves alone"
reset
seed "$T/repo" node_modules/pkg/x.ts 'export const n = 1;'
fmt "$T/repo/node_modules/pkg/x.ts" '' '// c' 'a node_modules file → silent'; silent
fmt "$T/other/apps/api/src/x.ts" '' '// c' 'a file outside the project → silent'; silent
pnpm_silent && ok "  …and ran neither prettier nor eslint" || bad "  …pnpm calls: $(tr '\t' ' ' <"$FAKE_PNPM_LOG")"
seed "$T/repo" internal-docs/x.md '# x'
fmt "$T/repo/internal-docs/x.md" '' '// c' 'a markdown file → prettier only, no eslint, no nudge'; silent
pnpm_ran "prettier" && ! pnpm_ran "eslint" && ok "  …prettier ran, eslint did not" || bad "  …pnpm calls: $(tr '\t' ' ' <"$FAKE_PNPM_LOG")"
seed "$T/repo" scripts/x.mjs 'export const s = 1;'
fmt "$T/repo/scripts/x.mjs" '' '// c' 'a file outside any package with an eslint config → silent'; silent
unset FAKE_ESLINT_JSON
reset
