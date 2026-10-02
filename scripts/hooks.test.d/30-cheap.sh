#!/usr/bin/env bash
# The cheap tier's own gates: secret-block (B19), docs-gate's map suggestions,
# reused-message trailer, user-docs-freshness (B6) and the coauthor gate's
# reused message.
# Sourced by scripts/hooks.test.sh.
# Fixtures added here (a fake `date`, commits on feat, a moved origin/main) are
# undone at the end of this file.
# shellcheck shell=bash disable=SC2034,SC2154

CLAUDE_MSG='Co-Authored-By: Claude <noreply@anthropic.com>'
JWT='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJVadQssw5c'

# remedy_line <stage> <where> <command>: the REMEDY line the gate writes to fd 3
remedy_line() {
  payload "$3" "$(where "$2")" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/gates/$1.sh" 3>"$T/remedy" >/dev/null 2>&1
  grep '^REMEDY: ' "$T/remedy" || true
}

# =============================================================================
echo "== C1. secret-block reads the added lines of the staged diff"
reset; stage repo apps/api/src/config/x.ts 'const cfg = { password: "hunter2hunter2" };'
gate secret-block 2 repo 'git commit -m x' 'an added credential literal → blocked'
said "apps/api/src/config/x.ts:1"; said "credential literal"; said "add the name to .env.example"
gate secret-block 2 repo "git -C $T/repo commit -m x" 'git -C <repo> → the same'
stage repo apps/api/src/config/y.ts $'// one\n// two\nexport const token = "abcdefghijklmnop";'
gate secret-block 2 repo 'git commit -m x' 'the line number is the added line'
said "apps/api/src/config/y.ts:3"
for p in apps/api/src/config/x.spec.ts apps/api/src/auth/__mocks__/x.ts apps/api/src/testing/x.ts apps/api/src/config/env.validation.ts x.test.ts notes.md; do
  reset; stage repo "$p" 'password: "hunter2hunter2"'
  gate secret-block 0 repo 'git commit -m x' "the same line in $p → exempt"
done
reset; stage repo apps/api/src/auth/auth.controller.ts '        access_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",'
gate secret-block 0 repo 'git commit -m x' 'the live auth.controller.ts Swagger example → passes (truncated value)'
reset; stage repo apps/api/src/config/z.ts 'const token = process.env.TOKEN ?? "placeholderplaceholder";'
gate secret-block 0 repo 'git commit -m x' 'process.env on the line → passes'
reset; stage repo apps/api/src/config/z.ts 'password: "short"'
gate secret-block 0 repo 'git commit -m x' 'a value under 12 characters → passes'
reset; stage repo apps/api/src/config/z.ts '@ApiProperty({ example: "sk_test_1234567890abcdef" }) secret: string;'
gate secret-block 0 repo 'git commit -m x' 'a documented example → passes'
reset; stage repo apps/api/src/jwt.ts "const t = \"$JWT\";"
gate secret-block 2 repo 'git commit -m x' 'a three-segment JWT in a .ts → blocked'
said "JWT literal"
reset; stage repo notes.txt "$JWT"
gate secret-block 0 repo 'git commit -m x' 'the same JWT in a .txt → not a source file'
reset; stage repo key.txt $'-----BEGIN PRIVATE KEY-----\nMIIE'
gate secret-block 2 repo 'git commit -m x' 'BEGIN PRIVATE KEY in a .txt → blocked'
said "key.txt:1"; said "private key"
reset; stage repo key.pem $'-----BEGIN RSA PRIVATE KEY-----'
gate secret-block 2 repo 'git commit -m x'
reset; stage repo apps/api/src/config/old.ts 'password: "hunter2hunter2"'; commit repo "a secret already in HEAD"
stage repo apps/api/src/config/old.ts $'password: "hunter2hunter2"\n// a comment'
gate secret-block 0 repo 'git commit -m x' 'a secret already in HEAD is not an added line → passes'
rewind repo
reset; stage repo apps/api/src/config/x.ts 'password: "hunter2hunter2"'; commit repo "a secret in HEAD"
git -C "$T/repo" rm -q apps/api/src/config/x.ts
gate secret-block 0 repo 'git commit -m x' 'deleting the file → passes'
rewind repo
reset; stage wt apps/api/src/config/x.ts 'password: "hunter2hunter2"'
gate secret-block 2 wt 'git commit -m x' 'from the worktree → blocked'
gate secret-block 2 repo "git -C $T/wt commit -m x" 'git -C <worktree> from the clean clone → blocked'
gate secret-block 0 repo 'git commit -m x' 'the clean clone itself → nothing staged'
reset; stage other apps/api/src/config/x.ts 'password: "hunter2hunter2"'
gate secret-block 0 other 'git commit -m x' 'another repo → not this gate'
reset
for h in secret-block docs-gate user-docs-freshness; do
  gate "$h" 0 repo 'git status'; silent
  gate "$h" 0 repo 'git commit -m x' 'nothing staged'; silent
  raw "$h" 2 '{"tool_input":{"command":"git commit -m x"' 'truncated JSON, commit text → blocked'
  raw "$h" 0 '{"tool_input":{"command":"echo hi"' 'truncated JSON, non-commit → allowed'
  gate "$h" 2 tmp 'git commit -m x' 'cwd is not a repo → blocked'
  gate "$h" 2 wt 'git -C /nonexistent commit -m x'
done

# =============================================================================
echo "== C2. the docs gate's suggestions come from the map; reused trailer"
reset; stage repo apps/api/src/auth/x.ts
gate docs-gate 2 repo 'git commit -m x' 'API code → the page the map names'
said "  • internal-docs/architecture/auth.md"
reset; stage repo packages/ui/src/x.tsx
gate docs-gate 2 repo 'git commit -m x' 'UI library code → its page'
said "  • internal-docs/frontend/component-library.md"; said "under internal-docs/frontend/"
reset; stage repo apps/nextjs/src/lib/x.ts
gate docs-gate 2 repo 'git commit -m x' 'portal code → the frontend area'
said "  • internal-docs/frontend/README.md"
reset; stage repo packages/ui/src/x.tsx; stage repo internal-docs/x.md
gate docs-gate 2 repo 'git commit -m x' 'a page outside the area does not count'
reset; stage repo apps/api/src/zzz/y.ts
gate docs-gate 2 repo 'git commit -m x' 'a path no rule maps to a page → the fallback'
said "internal-docs/README.md (find the page for this area)"
reset; stage repo apps/api/src/users/users.controller.ts; stage repo internal-docs/architecture/auth.md
gate docs-gate 2 repo 'git commit -m x' 'user-visible code → the user-docs area'
said "apps/docs/en/"; said "User-Docs: none — <reason>"
reset; stage repo apps/nextjs/src/app/x.tsx; stage repo internal-docs/frontend/x.md
gate docs-gate 0 repo 'git commit -m "feat: x" -m "User-Docs: none — a11y-only"' 'portal screen + frontend page + trailer: allowed'
for p in apps/api/src/y.spec.ts .claude/hooks/x.sh scripts/x.mjs apps/nextjs/src/app/x.test.tsx apps/api/src/testing/x.ts; do
  reset; stage repo "$p"
  gate docs-gate 0 repo 'git commit -m x' "$p alone → allowed"
done
reset; stage repo apps/api/src/users/users.controller.ts; stage repo internal-docs/architecture/auth.md
g -C "$T/repo" commit -q -m "feat: x" -m "User-Docs: none — nothing a user reads changed"
stage repo apps/api/src/users/users.controller.ts 'export const v2 = 1;'; stage repo internal-docs/architecture/auth.md '# v2'
gate docs-gate 0 repo 'git commit --amend --no-edit' '--amend --no-edit: the trailer in HEAD is reused → allowed'
gate docs-gate 0 repo 'git commit -C HEAD' '-C HEAD reuses it too'
gate docs-gate 0 repo 'git commit --amend --no-edit --trailer "Refs: #12"' '--amend with a trailer keeps the message'
gate docs-gate 2 repo 'git commit --amend -m "feat: y"' '--amend -m replaces the message → the trailer is gone → blocked'
said "User-Docs: none"
gate docs-gate 2 repo 'git commit -m "feat: y"' 'a plain commit reads nothing from HEAD → blocked'
rewind repo

echo "== C5. user-docs freshness is keyed to the page's landed history, in UTC"
cat >"$T/bin/date" <<'SH'
#!/usr/bin/env bash
# Fake date: FAKE_NOW (epoch seconds) is "now" when set; a later -d still wins.
real=/usr/bin/date; [ -x "$real" ] || real=/bin/date
if [ -n "${FAKE_NOW:-}" ]; then exec "$real" -d "@$FAKE_NOW" "$@"; fi
exec "$real" "$@"
SH
chmod +x "$T/bin/date"
FM() { printf -- '---\ntitle: X\naudience: both\nfeature: funds\nlastVerified: %s\n---\n# X\n%s\n' "$1" "${2:-body}"; }
DPAGE=apps/docs/en/funds/x.md
reset; rewind repo
# x.md lands on 2026-09-17 with lastVerified 09-10 (already behind); b.md lands on
# origin/main only, so a rename onto it meets a landed history (the R100 rows).
stage repo "$DPAGE" "$(FM 2026-09-10 landed)"
GIT_COMMITTER_DATE=2026-09-17T12:00:00+00:00 GIT_AUTHOR_DATE=2026-09-17T12:00:00+00:00 g -C "$T/repo" commit -q -m "x landed"
stage repo apps/docs/en/funds/b.md "$(FM 2026-09-23 landed)"
GIT_COMMITTER_DATE=2026-09-17T13:00:00+00:00 GIT_AUTHOR_DATE=2026-09-17T13:00:00+00:00 g -C "$T/repo" commit -q -m "b landed"
git -C "$T/repo" push -q origin HEAD:main 2>/dev/null
git -C "$T/repo" reset -q --hard HEAD~1
[ "$(git -C "$T/repo" log -1 --format=%cs origin/main -- "$DPAGE")" = 2026-09-17 ] && ok "fixture: the page landed on origin/main on 2026-09-17" || bad "fixture: origin/main landed date is $(git -C "$T/repo" log -1 --format=%cs origin/main -- "$DPAGE")"
[ ! -e "$T/repo/apps/docs/en/funds/b.md" ] && ok "fixture: b.md is on origin/main only" || bad "fixture: b.md is on feat"
export FAKE_NOW; FAKE_NOW=$(date -u -d 2026-09-24T10:00:00Z +%s)
stage repo "$DPAGE" "$(FM 2026-09-23)"
gate user-docs-freshness 0 repo 'git commit -m x' 'landed 09-17, lastVerified 09-23, today 09-24 → allowed'; silent
stage repo "$DPAGE" "$(FM 2026-09-10)"
gate user-docs-freshness 2 repo 'git commit -m x' 'lastVerified 09-10 is behind the landed change → blocked naming the range'
said "\`$DPAGE\`: lastVerified 2026-09-10 is older than the page's last landed change (2026-09-17)"; said "[2026-09-17, 2026-09-24]"
stage repo "$DPAGE" "$(FM 2026-09-17)"
gate user-docs-freshness 0 repo 'git commit -m x' 'equal to the landed date → allowed'
stage repo "$DPAGE" "$(FM 2026-09-24)"
gate user-docs-freshness 0 repo 'git commit -m x' 'today → allowed'
stage repo "$DPAGE" "$(FM 2026-09-25)"
gate user-docs-freshness 0 repo 'git commit -m x' 'tomorrow → allowed'
stage repo "$DPAGE" "$(FM 2026-09-26)"
gate user-docs-freshness 2 repo 'git commit -m x' 'two days ahead → blocked'
said "is in the future (today is 2026-09-24 UTC)"; said "[2026-09-17, 2026-09-24]"
stage repo "$DPAGE" "$(FM '"2026-09-23"')"
gate user-docs-freshness 0 repo 'git commit -m x' 'the quoted form parses → allowed'
stage repo "$DPAGE" "$(FM '"2026-09-10"')"
gate user-docs-freshness 2 repo 'git commit -m x' 'the quoted form parses → blocked'
said "lastVerified 2026-09-10"
gate user-docs-freshness 2 repo "git -C $T/repo commit -m x" 'git -C <repo> → the same'
gate user-docs-freshness 2 wt "git -C $T/repo commit -m x" 'git -C <repo> from the worktree → the same'
git -C "$T/repo" reset -q apps/docs/en/funds/x.md && git -C "$T/repo" checkout -q -- "$DPAGE"
stage repo apps/docs/en/funds/new.md "$(FM 2026-09-25)"
gate user-docs-freshness 0 repo 'git commit -m x' 'a new page dated tomorrow → allowed'
stage repo apps/docs/en/funds/new.md "$(FM 2020-01-01)"
gate user-docs-freshness 0 repo 'git commit -m x' 'a new page with any past date → allowed (no landed history)'
stage repo apps/docs/en/funds/new.md "$(FM 2026-09-26)"
gate user-docs-freshness 2 repo 'git commit -m x' 'a new page two days ahead → blocked'
said "[any date, 2026-09-24]"
reset
stage repo apps/docs/en/_stubs/x.md "$(FM 2020-01-01)"
gate user-docs-freshness 0 repo 'git commit -m x' '_stubs/ is exempt'; silent
stage repo apps/docs/en/funds/nofield.md $'---\ntitle: X\n---\n# X'
gate user-docs-freshness 0 repo 'git commit -m x' 'a page without the field → allowed'
stage repo apps/docs/en/README.md $'# docs\nlastVerified: 2020-01-01'
gate user-docs-freshness 0 repo 'git commit -m x' 'the field outside a frontmatter block is not the field'
stage repo apps/docs/en/funds/body.md "$(FM 2026-09-23)"$'\nlastVerified: 2020-01-01'
gate user-docs-freshness 0 repo 'git commit -m x' 'only the frontmatter field is read'
reset
git -C "$T/repo" mv "$DPAGE" apps/docs/en/funds/b.md
gate user-docs-freshness 0 repo 'git commit -m x' 'a pure rename onto a path with a landed history (R100) → exempt'; silent
printf '\nedited\n' >>"$T/repo/apps/docs/en/funds/b.md"; git -C "$T/repo" add apps/docs/en/funds/b.md
gate user-docs-freshness 2 repo 'git commit -m x' 'the same rename with an edit → judged against b.md history (09-10 < 09-17)'
said "\`apps/docs/en/funds/b.md\`: lastVerified 2026-09-10 is older than the page's last landed change (2026-09-17)"
reset
git -C "$T/repo" mv "$DPAGE" apps/docs/en/funds/moved.md
gate user-docs-freshness 0 repo 'git commit -m x' 'git mv to a new path → allowed'
reset
FAKE_NOW=$(date -u -d '2026-09-25T00:30:00+02:00' +%s) # 22:30 UTC the day before
stage repo "$DPAGE" "$(FM 2026-09-24)"
TZ=Europe/Madrid gate user-docs-freshness 0 repo 'git commit -m x' 'Madrid 00:30 on 09-25: the UTC date 09-24 passes'
stage repo "$DPAGE" "$(FM 2026-09-23)"
TZ=Europe/Madrid gate user-docs-freshness 0 repo 'git commit -m x' 'yesterday UTC passes'
stage repo "$DPAGE" "$(FM 2026-09-26)"
TZ=Europe/Madrid gate user-docs-freshness 2 repo 'git commit -m x' '09-26 is two days past the UTC date (the local clock would allow it) → blocked'
said "today is 2026-09-24 UTC"
reset; stage wt "$DPAGE" "$(FM 2026-09-10)"
gate user-docs-freshness 2 wt 'git commit -m x' 'from the worktree, origin/main is the same history → blocked'
stage wt "$DPAGE" "$(FM 2026-09-23)"
gate user-docs-freshness 0 wt 'git commit -m x'
reset; stage other "$DPAGE" "$(FM 2020-01-01)"
gate user-docs-freshness 0 other 'git commit -m x' 'another repo → not this gate'
unset FAKE_NOW; rm -f "$T/bin/date"
git -C "$T/repo" push -q -f origin "$BASE:main" 2>/dev/null; rewind repo; reset
[ "$(git -C "$T/repo" rev-parse origin/main)" = "$BASE" ] && ok "fixture: origin/main restored" || bad "fixture: origin/main is not BASE"

# =============================================================================
echo "== C6. the coauthor gate reads a reused message (B5)"
reset; g -C "$T/repo" commit -q --allow-empty -m "fix: x" -m "$CLAUDE_MSG"
gate coauthor 2 repo 'git commit --amend --no-edit' 'attribution in HEAD, --amend --no-edit keeps it → blocked'
gate coauthor 2 repo 'git commit -C HEAD' '-C HEAD → blocked'
gate coauthor 0 repo 'git commit --amend -m "fix: x"' 'a new message replaces it → allowed'
gate coauthor 0 repo 'git commit -m "fix: y"' 'a plain commit reads nothing from HEAD'
rewind repo

echo "== C7. every cheap gate names its by-hand command on fd 3"
reset; stage repo apps/api/src/auth/x.ts; stage repo "$DPAGE" "$(FM 2026-09-23)"
for h in coauthor secret-block docs-gate user-docs-freshness; do
  r=$(remedy_line "$h" repo 'git commit -m x')
  [ -n "$r" ] && ok "$h: $r" || bad "$h wrote no REMEDY line to fd 3"
done
r=$(remedy_line docs-gate repo 'git status'); [ -z "$r" ] && ok "  …and a non-commit writes none" || bad "  …but a non-commit wrote: $r"

echo "== C8. the cheap tier through the dispatcher"
reset; stage repo apps/api/src/config/x.ts 'password: "hunter2hunter2"'
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo "git commit -m x -m \"$CLAUDE_MSG\"" 'attribution + a secret + no docs → one block, three sections'
said "Commit blocked by 3 gate(s)"; said "--- coauthor ---"; said "--- secret-block ---"; said "--- docs-gate ---"
reset; stage repo apps/api/src/auth/x.ts 'export const ok = 1;'; stage repo internal-docs/architecture/auth.md '# auth'
HOOK_GATES_DIR=$T/gates-mixed dispatch 0 repo 'git commit -m "feat: x"' 'code + its page, clean message → every stage passes'
silent
reset; stage wt apps/api/src/auth/x.ts
HOOK_GATES_DIR=$T/gates-mixed dispatch 2 repo "git -C $T/wt commit -m x" 'git -C <worktree>: docs-gate judges the worktree, the hint is appended'
said "--- docs-gate ---"; said "skills must run with the shell inside $T/wt"
reset
