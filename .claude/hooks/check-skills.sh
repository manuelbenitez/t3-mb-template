#!/usr/bin/env bash
# SessionStart hook: check the workflow skills (gstack) are installed; nudge
# with the install command when not. The push and PR gates read gstack's
# /review log, so without it no PR can open.
set -u
SK="$HOME/.claude/skills"
[ -e "$SK/gstack/SKILL.md" ] && exit 0
msg=$'📦 gstack is not installed (/review, /ship, /qa, /investigate, /browse, /careful); the PR gate needs its /review log:\n    git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup'
jq -n --arg m "$msg" '{systemMessage: $m}'
