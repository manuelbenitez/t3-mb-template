#!/usr/bin/env bash
# The heavy commit stages and the by-hand suites: deps-smoke at commit,
# typecheck-lint and tests under the dispatcher contract,
# scripts/lifecycle-suite.sh and scripts/deps-smoke.sh (the pr-open
# half of B9). Sourced by scripts/hooks.test.sh; the fake pnpm and df come from
# there.
# shellcheck shell=bash disable=SC2034,SC2154

BAD_TS='export const x: number = "not a number";'
mkdir -p "$T/heavy-bin" "$T/nohome/.claude/skills"
# A pnpm that first writes into the tree (a spec that touches a tracked file),
# then behaves as the fake: PATH="$T/heavy-bin:$PATH" FAKE_SUITE_TOUCH=<file>.
cat >"$T/heavy-bin/pnpm" <<SH
#!/usr/bin/env bash
[ -n "\${FAKE_SUITE_TOUCH:-}" ] && printf '// touched by the suite\n' >>"\$FAKE_SUITE_TOUCH"
exec "$T/bin/pnpm" "\$@"
SH
chmod +x "$T/heavy-bin/pnpm"

echo "== H2. deps-smoke at commit: project.deps_check (lockfile-only, typecheck); never install, build or boot"
reset; stage repo package.json '{"name":"fixture","private":true,"packageManager":"pnpm@10.19.0","x":1}'
gate deps-smoke 0 repo 'git commit -m x' 'staged package.json → the two steps'
pnpm_ran "^$T/repo${TAB}install${TAB}--frozen-lockfile${TAB}--lockfile-only${TAB}--offline$" && ok "  …pnpm install --frozen-lockfile --lockfile-only --offline, in the repo" || bad "  …no lockfile-only call: $(cat "$FAKE_PNPM_LOG")"
pnpm_ran "^$T/repo${TAB}typecheck$" && ok "  …pnpm typecheck" || bad "  …no typecheck: $(cat "$FAKE_PNPM_LOG")"
order=$(awk -F'\t' '$2=="install"{print "i"} $2=="typecheck"{print "t"}' "$FAKE_PNPM_LOG" | tr -d '\n')
[ "$order" = itit ] && ok "  …in that order, on both payload paths" || bad "  …order was $order"
pnpm_ran "${TAB}build" && bad "  …but build ran" || ok "  …and never build"
pnpm_ran "boot:check" && bad "  …but boot:check ran" || ok "  …and never boot:check"
pnpm_ran "${TAB}install$" && bad "  …but a bare install ran" || ok "  …and never a bare install"
silent
: >"$FAKE_PNPM_LOG"
FAKE_FAIL=--lockfile-only gate deps-smoke 2 repo 'git commit -m x' 'the lockfile behind the manifests → blocked naming the command'
said "at: pnpm install --frozen-lockfile --lockfile-only --offline"; said "staged: package.json"
pnpm_ran "${TAB}typecheck$" && bad "  …but typecheck still ran after the failure" || ok "  …and stopped there"
FAKE_FAIL=typecheck gate deps-smoke 2 repo 'git commit -m x' 'typecheck fails → blocked naming it'
said "at: pnpm typecheck"
reset; stage repo apps/api/src/x.ts "$BAD_TS"
FAKE_FAIL=typecheck gate deps-smoke 0 repo 'git commit -m x' 'a .ts alone → no call'
pnpm_silent && ok "  …and pnpm never ran" || bad "  …but pnpm ran: $(head -1 "$FAKE_PNPM_LOG")"
reset; stage repo pnpm-workspace.yaml 'packages: ["apps/*", "packages/*"]'
gate deps-smoke 0 repo 'git commit -m x' 'pnpm-workspace.yaml fires it'
pnpm_ran "${TAB}--lockfile-only" && ok "  …lockfile check ran" || bad "  …no lockfile check"
reset; stage repo apps/nextjs/package.json '{"name":"@acme/nextjs","version":"2"}'
gate deps-smoke 0 repo 'git commit -m x' 'a workspace package.json fires it'
pnpm_ran "${TAB}--lockfile-only" && ok "  …lockfile check ran" || bad "  …no lockfile check"
reset; git -C "$T/repo" rm -q apps/api/package.json
gate deps-smoke 0 repo 'git commit -m x' 'a deleted package.json is a manifest change too'
pnpm_ran "${TAB}--lockfile-only" && ok "  …lockfile check ran" || bad "  …no lockfile check"
reset; stage wt pnpm-lock.yaml 'lockfileVersion: "9.0"'
FAKE_FAIL=--lockfile-only gate deps-smoke 2 repo "git -C $T/wt commit -m x" 'git -C <worktree> from the clone → checked in the worktree'
pnpm_ran "^$T/wt${TAB}install${TAB}--frozen-lockfile" && ok "  …in the worktree" || bad "  …ran elsewhere: $(cat "$FAKE_PNPM_LOG")"
raw deps-smoke 2 '{"tool_input":{"command":"git commit -m x"' 'truncated JSON → blocked on both paths'
gate deps-smoke 2 tmp 'git commit -m x' 'cwd is not a repo → blocked'
reset; stage other package.json '{"name":"other","x":1}'
FAKE_FAIL=--lockfile-only gate deps-smoke 0 other 'git commit -m x' 'another repo → not this gate'
pnpm_silent && ok "  …and pnpm never ran" || bad "  …but pnpm ran"
FAKE_FAIL=--lockfile-only gate deps-smoke 0 repo 'pnpm install' 'not a commit'

# =============================================================================
echo "== H3. typecheck-lint and tests under the contract: the exported TOP, the REMEDY line on fd 3"
reset; stage wt apps/api/src/x.ts "$BAD_TS"
payload 'git commit -m x' "$T/wt" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/gates/tests.sh" 3>"$T/remedy" >/dev/null 2>&1
grep -qx 'REMEDY: bash scripts/test-changed.sh apps/api/src/x.ts' "$T/remedy" && ok "tests: REMEDY names test-changed.sh with the staged files" || bad "tests REMEDY: $(cat "$T/remedy")"
payload 'git commit -m x' "$T/wt" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/gates/typecheck-lint.sh" 3>"$T/remedy" >/dev/null 2>&1
grep -q '^REMEDY: .*pnpm typecheck' "$T/remedy" && ok "typecheck-lint: REMEDY names pnpm typecheck" || bad "typecheck-lint REMEDY: $(cat "$T/remedy")"
stage wt package.json '{"name":"fixture","x":2}'
payload 'git commit -m x' "$T/wt" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/gates/deps-smoke.sh" 3>"$T/remedy" >/dev/null 2>&1
grep -q '^REMEDY: pnpm install --frozen-lockfile --lockfile-only --offline && pnpm typecheck$' "$T/remedy" && ok "deps-smoke: REMEDY names the deps_check commands" || bad "deps-smoke REMEDY: $(cat "$T/remedy")"
for s in tests typecheck-lint deps-smoke; do
  gate "$s" 0 wt 'git commit -m x' "$s without fd 3 → no REMEDY anywhere"; unsaid "REMEDY"
done
reset; stage wt apps/api/src/x.ts "$BAD_TS"
(
  export HOOK_PAYLOAD_SET=1 HOOK_CMD='git commit -m x' HOOK_CWD="$T/wt" HOOK_FILE='' HOOK_RAW=no HOOK_GIT_DIR='' HOOK_CLASSES=commit TOP=''
  FAKE_FAIL=typecheck bash "$HOOKS/gates/typecheck-lint.sh" </dev/null >/dev/null 2>&1
); rc=$?
[ "$rc" = 2 ] && ok "typecheck-lint: TOP='' from the dispatcher → recomputed from the payload cwd, gated" || bad "typecheck-lint with TOP='' got rc $rc"
pnpm_ran "^$T/wt${TAB}.*typecheck" && ok "  …typecheck ran in the worktree" || bad "  …typecheck did not run in the worktree: $(cat "$FAKE_PNPM_LOG")"
: >"$FAKE_PNPM_LOG"
(
  export HOOK_PAYLOAD_SET=1 HOOK_CMD='git commit -m x' HOOK_CWD="$T/wt" HOOK_FILE='' HOOK_RAW=no HOOK_GIT_DIR='' HOOK_CLASSES=commit TOP="$T/other"
  FAKE_FAIL=typecheck bash "$HOOKS/gates/typecheck-lint.sh" </dev/null >/dev/null 2>&1
); rc=$?
[ "$rc" = 0 ] && ok "typecheck-lint: the dispatcher's TOP is trusted (another repo → not our business)" || bad "typecheck-lint with TOP=other got rc $rc"
pnpm_silent && ok "  …and no typecheck ran" || bad "  …but pnpm ran: $(head -1 "$FAKE_PNPM_LOG")"

# =============================================================================
echo "== H4. scripts/lifecycle-suite.sh (fake pnpm, fake df)"
LS="$ROOT/scripts/lifecycle-suite.sh"
suite() { # suite <want-rc> <where> <label>   — the suite, run from inside <where>
  local want=$1 d; d=$(where "$2")
  OUT=$(cd "$d" && bash "$LS" 2>&1); RC=$?
  [ "$RC" = "$want" ] && ok "lifecycle-suite($want) in $2: $3" || bad "lifecycle-suite($want) in $2: $3 (got $RC): $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
}
lmarker() { printf '%s/lifecycle/%s' "$(state_dir "$T/repo")" "$(lifecycle_key "$T/repo" "$(git -C "$(where "$1")" rev-parse HEAD)")"; }
reset; rm -rf "$(state_dir "$T/repo")/lifecycle"
dirty wt apps/api/src/x.ts
suite 1 wt 'dirty tracked tree → refuses'
said "dirty"; said "git stash"; pnpm_silent && ok "  …before any pnpm call" || bad "  …but pnpm ran: $(head -1 "$FAKE_PNPM_LOG")"
reset
FAKE_DF_AVAIL_KB=1000000 suite 1 wt '/tmp under 4 GiB (fake df) → refuses'
said "4 GiB"; said "976 MiB free"; pnpm_silent && ok "  …before any pnpm call" || bad "  …but pnpm ran: $(head -1 "$FAKE_PNPM_LOG")"
PATH="$T/heavy-bin:$PATH" FAKE_SUITE_TOUCH="$T/wt/apps/api/src/x.ts" suite 1 wt 'the tree changed during the run (the suite touched a tracked file) → no marker'
said "changed during the run"; said "apps/api/src/x.ts"
[ ! -e "$(lmarker wt)" ] && ok "  …no marker written" || bad "  …but a marker was written"
pnpm_ran "^$T/wt${TAB}--filter${TAB}@acme/api${TAB}test:e2e$" && ok "  …the suite ran as project.lifecycle_suite (pnpm --filter @acme/api test:e2e)" || bad "  …suite call: $(cat "$FAKE_PNPM_LOG")"
reset
FAKE_FAIL=test:e2e suite 1 wt 'the suite fails → no marker'
said "the suite failed"; [ ! -e "$(lmarker wt)" ] && ok "  …no marker written" || bad "  …but a marker was written"
suite 0 wt 'green run → marker under the common dir'
[ -f "$(lmarker wt)" ] && ok "  …marker for HEAD's key, found through the main checkout" || bad "  …no marker at $(lmarker wt)"
said "marker $(state_dir "$T/repo")/lifecycle/"
work=$(printf '%s\n' "$OUT" | sed -n 's/.*dbpaths under \(\/tmp\/lifecycle-suite\.[^ ]*\).*/\1/p' | head -1)
[ -n "$work" ] && [ ! -e "$work" ] && ok "  …its private TMPDIR ($work) is gone" || bad "  …TMPDIR '$work' still there or not announced"
seed "$T/wt" internal-docs/x.md '# x'; g -C "$T/wt" add -A; commit wt docs
[ -f "$(lmarker wt)" ] && ok "  …a docs commit keeps the marker" || bad "  …a docs commit lost the marker"
seed "$T/wt" apps/api/src/y.ts 'export const y = 1;'; g -C "$T/wt" add -A; commit wt code
[ ! -f "$(lmarker wt)" ] && ok "  …an apps/api commit needs a new one" || bad "  …the marker survived an apps/api change"
rewind wt
suite 1 other 'another repo → refuses'
said "not a checkout of this project"
OUT=$(cd "$T" && bash "$LS" 2>&1); RC=$?
[ "$RC" = 1 ] && ok "lifecycle-suite(1) outside a repo → refuses" || bad "lifecycle-suite outside a repo got rc $RC"

# =============================================================================
echo "== H5. scripts/deps-smoke.sh: the dev-server guard, project.deps_smoke (build + boot:check), the marker"
DS="$ROOT/scripts/deps-smoke.sh"
smoke() { # smoke <want-rc> <where> <label>
  local want=$1 d; d=$(where "$2")
  OUT=$(cd "$d" && bash "$DS" 2>&1); RC=$?
  [ "$RC" = "$want" ] && ok "deps-smoke.sh($want) in $2: $3" || bad "deps-smoke.sh($want) in $2: $3 (got $RC): $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
}
dmarker() { printf '%s/deps/%s' "$(state_dir "$T/repo")" "$(deps_key "$T/repo" "$(git -C "$(where "$1")" rev-parse HEAD)")"; }
: >"$T/listen.port"
node -e 'const s=require("net").createServer((c)=>c.end());s.listen(0,"127.0.0.1",()=>require("fs").writeFileSync(process.argv[1],String(s.address().port)))' "$T/listen.port" &
LISTEN_PID=$!
for _ in $(seq 1 50); do [ -s "$T/listen.port" ] && break; sleep 0.1; done
P=$(cat "$T/listen.port")
[ -n "$P" ] && ok "a TCP listener stands in for the dev API on :$P" || bad "could not start the listener"
reset; rm -rf "$(state_dir "$T/repo")/deps"
PORT=$P smoke 1 wt 'something on the API port → refuses'
said "listens on :$P"; said "DEPS_SMOKE_ALLOW_DEV=1 bash scripts/deps-smoke.sh"; pnpm_silent && ok "  …before any pnpm call" || bad "  …but pnpm ran"
PORT=$P DEPS_SMOKE_ALLOW_DEV=1 smoke 0 wt 'allowed under the dev API → build, boot:check, marker'
pnpm_ran "^$T/wt${TAB}--filter${TAB}@acme/api${TAB}build$" && ok "  …pnpm --filter @acme/api build, in the worktree" || bad "  …no build: $(cat "$FAKE_PNPM_LOG")"
pnpm_ran "^$T/wt${TAB}--filter${TAB}@acme/api${TAB}boot:check$" && ok "  …pnpm --filter @acme/api boot:check" || bad "  …no boot:check: $(cat "$FAKE_PNPM_LOG")"
pnpm_ran "${TAB}install" && bad "  …but an install ran" || ok "  …and no install"
[ -f "$(dmarker wt)" ] && ok "  …marker for HEAD's deps key, found through the main checkout" || bad "  …no marker at $(dmarker wt)"
said "marker $(state_dir "$T/repo")/deps/"
rm -f "$(dmarker wt)"; : >"$FAKE_PNPM_LOG"
PORT=1 FAKE_FAIL=build smoke 1 wt 'the build fails → named, no marker'
said "failed at: pnpm --filter @acme/api build"; [ ! -e "$(dmarker wt)" ] && ok "  …no marker written" || bad "  …but a marker was written"
pnpm_ran "boot:check" && bad "  …but boot:check still ran" || ok "  …and boot:check never ran"
PORT=1 FAKE_FAIL=boot:check smoke 1 wt 'boot:check fails → named, no marker'
said "failed at: pnpm --filter @acme/api boot:check"; [ ! -e "$(dmarker wt)" ] && ok "  …no marker written" || bad "  …but a marker was written"
dirty wt apps/api/package.json; : >"$FAKE_PNPM_LOG"
PORT=1 smoke 1 wt 'a modified, uncommitted manifest → refuses'
said "apps/api/package.json"; said "commit it first"; pnpm_silent && ok "  …before any pnpm call" || bad "  …but pnpm ran"
reset; dirty wt apps/api/src/x.ts
PORT=1 smoke 0 wt 'a dirty non-manifest file is fine (the key covers manifests only)'
[ -f "$(dmarker wt)" ] && ok "  …marker written" || bad "  …no marker"
reset
seed "$T/wt" internal-docs/x.md '# x'; g -C "$T/wt" add -A; commit wt docs
[ -f "$(dmarker wt)" ] && ok "  …a docs commit keeps the deps marker" || bad "  …a docs commit lost the deps marker"
seed "$T/wt" apps/api/package.json '{"name":"@acme/api","version":"2"}'; g -C "$T/wt" add -A; commit wt "api manifest"
[ ! -f "$(dmarker wt)" ] && ok "  …a manifest commit needs a new one" || bad "  …the deps marker survived a manifest change"
rewind wt
PORT=1 smoke 1 other 'another repo → refuses'
said "not a checkout of this project"
kill "$LISTEN_PID" 2>/dev/null; wait "$LISTEN_PID" 2>/dev/null
