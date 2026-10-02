#!/usr/bin/env bash
# Regression harness for the hooks in .claude/hooks: the dispatcher (bash-gate.sh),
# the stages under gates/, the stop hook and lib.sh. This file holds the fixtures
# and the drivers; the rows live in scripts/hooks.test.d/*.sh, sourced in name
# order (10-core.sh: the core rows, 20-dispatcher.sh: the dispatcher, the payload
# contract, B15, heredocs and the lib additions; later files: one per gate).
#
# Every BLOCK row is a shape a commit once got past a gate with (a commit from a
# git worktree checked against the session root's index; `git -c x commit` and
# `git -C dir commit` never matching); every ALLOW row is one a gate once
# wrongly blocked or must never touch (another repo, a heredoc that merely
# mentions the commit command).
#
# Runs in a throwaway tree under mktemp — a bare <project.repo>.git remote, a
# clone, a linked worktree of the clone and an unrelated repo — with fake tools
# on PATH (pnpm, gh, df, gstack's review-log reader) that record their calls
# and fail on demand, so it never runs a real typecheck or test, never talks to
# GitHub and never touches this repository.
#
#   bash scripts/hooks.test.sh
# shellcheck disable=SC2034  # TAB, CHEAP, ENV_RAW and the drivers' results are read by the row files
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOKS="$ROOT/.claude/hooks"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
. "$HOOKS/lib.sh"

T=$(cd "$(mktemp -d)" && pwd -P) # the real path: the hooks report git's resolved toplevel
trap 'rm -rf "$T"' EXIT
TAB=$'\t'
fails=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# The dispatcher's stage list, in its order.
STAGES="coauthor secret-block docs-gate user-docs-freshness deps-smoke typecheck-lint tests push pr-open"
CHEAP="coauthor secret-block docs-gate user-docs-freshness"
# The fixture's remote is this project's repo, so the gates treat it as theirs.
REPO=$(node "$ROOT/scripts/review-map.mjs" config | sed -n "s/^HOOK_CFG_REPO='\(.*\)'$/\1/p")
[ -n "$REPO" ] || { echo "cannot read project.repo from the review map" >&2; exit 1; }

# --- fake tools ---------------------------------------------------------------
mkdir -p "$T/bin" "$T/$(dirname "$REPO")" "$T/elsewhere" "$T/fakegates" "$T/gates-mixed"
cat >"$T/bin/pnpm" <<'SH'
#!/usr/bin/env bash
# Fake pnpm: records the directory it ran in and its argv (tab-separated), and
# fails when any argument is listed in FAKE_FAIL (e.g. FAKE_FAIL="typecheck vitest").
{ printf '%s' "$PWD"; printf '\t%s' "$@"; printf '\n'; } >>"${FAKE_PNPM_LOG:-/dev/null}"
for a in "$@"; do
  case " ${FAKE_FAIL:-} " in *" $a "*) echo "fake pnpm: $a failed" >&2; exit 1 ;; esac
done
exit 0
SH
cat >"$T/bin/gh" <<'SH'
#!/usr/bin/env bash
# Fake gh: FAKE_GH_PRS is what `pr list` prints, FAKE_GH_SLEEP simulates a hang,
# `repo view` is the project repo, `api` calls are recorded (FAKE_GH_API_FAIL=1 → 422).
[ -n "${FAKE_GH_SLEEP:-}" ] && sleep "$FAKE_GH_SLEEP"
echo "$*" >>"${FAKE_GH_LOG:-/dev/null}"
case "${1:-} ${2:-}" in
  "repo view") echo "${FAKE_GH_REPO:-acme/app}" ;;
  "pr view") exit 1 ;;
  "pr list") printf '%s\n' "${FAKE_GH_PRS:-[]}" ;;
  api*) if [ "${FAKE_GH_API_FAIL:-0}" = 1 ]; then echo "HTTP 422: No commit found for SHA" >&2; exit 1; fi ;;
esac
exit 0
SH
cat >"$T/bin/df" <<'SH'
#!/usr/bin/env bash
# Fake df: `df --output=avail <path>` reports FAKE_DF_AVAIL_KB (default 100 GiB).
printf '    Avail\n%s\n' "${FAKE_DF_AVAIL_KB:-104857600}"
SH
cat >"$T/bin/reader" <<'SH'
#!/usr/bin/env bash
# Fake gstack-review-read: the log is FAKE_LOG, one JSON record per line.
cat "$FAKE_LOG" 2>/dev/null
echo ---CONFIG---
SH
# Fake stages for the dispatcher rows: each logs its name to FAKE_STAGE_LOG and
# behaves per FAKE_STAGES, a list of name=spec where spec is an exit code, sleep:N,
# remedy:N (a REMEDY line on fd 3, then sleep), env (print the export, exit 2) or
# msg (a systemMessage on stdout). No spec → exit 0.
cat >"$T/fakestage.sh" <<'SH'
#!/usr/bin/env bash
name=$(basename "$0" .sh)
printf '%s\n' "$name" >>"${FAKE_STAGE_LOG:-/dev/null}"
spec=''
for kv in ${FAKE_STAGES:-}; do [ "${kv%%=*}" = "$name" ] && spec=${kv#*=}; done
case $spec in
  '') exit 0 ;;
  env) printf 'PAYLOAD_SET=%s CLASSES=[%s] TOP=%s RAW=%s GIT_DIR=%s STDIN=%s CMD=%s\n' \
    "${HOOK_PAYLOAD_SET:-}" "${HOOK_CLASSES:-}" "${TOP:-}" "${HOOK_RAW:-}" "${HOOK_GIT_DIR:-}" "$(wc -c <&0)" "${HOOK_CMD:-}" >&2; exit 2 ;;
  sleep:*) sleep "${spec#sleep:}"; exit 0 ;;
  remedy:*) { echo "REMEDY: run-me-by-hand-$name" >&3; } 2>/dev/null; sleep "${spec#remedy:}"; exit 0 ;;
  msg) printf '{"systemMessage":"note from %s"}\n' "$name"; exit 0 ;;
  *) [ "$spec" = 2 ] && echo "fake $name: blocked" >&2; exit "$spec" ;;
esac
SH
for s in $STAGES; do
  cp "$T/fakestage.sh" "$T/fakegates/$s.sh"
  # gates-mixed: the real stage when it exists, a pass-through stub until it is written.
  if [ -f "$HOOKS/gates/$s.sh" ]; then
    printf '#!/usr/bin/env bash\nexec bash "%s/gates/%s.sh" "$@"\n' "$HOOKS" "$s" >"$T/gates-mixed/$s.sh"
  else
    printf '#!/usr/bin/env bash\nexit 0\n' >"$T/gates-mixed/$s.sh"
  fi
done
chmod +x "$T/bin/"* "$T/fakegates/"*.sh "$T/gates-mixed/"*.sh

# --- repositories -------------------------------------------------------------
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
seed() { mkdir -p "$1/$(dirname "$2")"; printf '%s\n' "${3:-// $2}" >"$1/$2"; }

git init -q --bare "$T/$REPO.git"
git clone -q "$T/$REPO.git" "$T/repo" 2>/dev/null
seed "$T/repo" package.json '{"name":"fixture","private":true,"packageManager":"pnpm@10.19.0"}'
seed "$T/repo" pnpm-workspace.yaml 'packages: ["apps/*"]'
seed "$T/repo" apps/api/package.json '{"name":"@acme/api","devDependencies":{"vitest":"catalog:"}}'
seed "$T/repo" apps/api/src/x.ts 'export const x = 1;'
seed "$T/repo" apps/api/eslint.config.mjs 'export default [];'
seed "$T/repo" apps/nextjs/package.json '{"name":"@acme/nextjs","devDependencies":{"vitest":"catalog:"}}'
seed "$T/repo" apps/nextjs/src/app/page.tsx 'export default () => null;'
seed "$T/repo" internal-docs/README.md '# internal'
seed "$T/repo" internal-docs/frontend/README.md '# frontend'
# The router and what it reads: the fixture's own copy of the map and its reader.
mkdir -p "$T/repo/scripts" "$T/repo/.claude/hooks"
cp "$ROOT/scripts/test-changed.sh" "$ROOT/scripts/review-map.mjs" "$T/repo/scripts/"
cp "$HOOKS/lib.sh" "$T/repo/.claude/hooks/"
# The fixture's map is this project's plus what the rows need even while the
# project has none of it: user docs switched on, and one required skill
# (fixture-check) with its rule. Every map query in the harness reads it
# (REVIEW_MAP_TOP).
sed -e 's|^  user_docs_root: ""|  user_docs_root: "apps/docs/en"|' \
  -e 's|^  user_visible: \[\]|  user_visible: ["apps/nextjs/src/app/**", "apps/api/src/**/*.controller.ts", "apps/api/src/**/dto/**"]|' \
  -e 's|^skills:$|skills:\n  fixture-check: { when: "a fixture-only required skill" }|' \
  -e '/^lifecycle:/,/^  \]/s|^  \[$|  [\n    "apps/api/src/billing/**",|' \
  "$ROOT/.claude/review-map.yml" >"$T/repo/.claude/review-map.yml"
cat >>"$T/repo/.claude/review-map.yml" <<'YML'
  - id: fixture-billing
    paths: ["apps/api/src/billing/**"]
    skills: [fixture-check]
    internal_docs: ["architecture/billing.md"]
    user_docs: ["billing/"]
YML
grep -q 'user_docs_root: "apps/docs/en"' "$T/repo/.claude/review-map.yml" || { echo "fixture map: user docs not switched on" >&2; exit 1; }
seed "$T/repo" apps/docs/en/README.md '# docs'
export REVIEW_MAP_TOP="$T/repo"
hook_config || { echo "cannot load the fixture map" >&2; exit 1; }
g -C "$T/repo" add -A && g -C "$T/repo" commit -q -m base
git -C "$T/repo" push -q origin HEAD:main 2>/dev/null
g -C "$T/repo" checkout -q -b feat
g -C "$T/repo" worktree add -q "$T/wt" -b feat2 2>/dev/null
git init -q "$T/other"
git -C "$T/other" remote add origin git@github.com:acme/other.git
seed "$T/other" package.json '{"name":"other"}'
seed "$T/other" apps/api/src/x.ts 'export const x = 1;'
g -C "$T/other" add -A && g -C "$T/other" commit -q -m x
BASE=$(git -C "$T/repo" rev-parse HEAD) # the one commit on main; rows that commit rewind to it

export PATH="$T/bin:$PATH" FAKE_PNPM_LOG="$T/pnpm.log" FAKE_GH_LOG="$T/gh.log" FAKE_GH_REPO="$REPO" \
  FAKE_STAGE_LOG="$T/stages.log" AI_REVIEW_LOG_READER="$T/bin/reader" FAKE_LOG="$T/review.jsonl"
PROJECT="$T/repo" # the session root: a clean clone, like a main checkout
cd "$T/elsewhere" || exit 1 # never a repo, never a payload cwd: a hook that reads its own PWD, or falls back to `.`, lands nowhere

where() { case "$1" in wt) echo "$T/wt" ;; wt/apps/api) echo "$T/wt/apps/api" ;; repo) echo "$T/repo" ;; other) echo "$T/other" ;; tmp) echo "$T" ;; *) echo "$1" ;; esac; }
reset() {
  local r
  for r in "$T/repo" "$T/wt" "$T/other"; do git -C "$r" reset -q --hard && git -C "$r" clean -fdq; done
  : >"$FAKE_PNPM_LOG"; : >"$FAKE_STAGE_LOG"; : >"$FAKE_GH_LOG"
}
rewind() { git -C "$(where "$1")" reset -q --hard "$BASE"; }  # rewind <where>  — drop the row's commits
stage() { # stage <where> <path> [content]   — write and stage a file
  local d; d=$(where "$1")
  mkdir -p "$d/$(dirname "$2")"; printf '%s\n' "${3:-// $RANDOM}" >"$d/$2"; git -C "$d" add -- "$2"
}
dirty() { # dirty <where> <path>              — modify a tracked file, unstaged
  local d; d=$(where "$1"); printf '// %s\n' "$RANDOM" >>"$d/$2"
}
commit() { g -C "$(where "$1")" commit -q --allow-empty -m "$2"; } # commit <where> <message>
pnpm_ran() { grep -q -- "$1" "$FAKE_PNPM_LOG"; }      # some recorded call matches (basic regex)
pnpm_silent() { [ ! -s "$FAKE_PNPM_LOG" ]; }

# --- drivers ------------------------------------------------------------------
OUT="" ERR="" RC="" PATHS_AGREE="" ENV_RAW=""
payload() { jq -n --arg c "$1" --arg d "$2" '{tool_input:{command:$c},cwd:$d}'; }

# Runs gates/<stage>.sh twice on one payload text: piped on stdin, then the way
# the dispatcher spawns it (the export below, HOOK_PAYLOAD_SET=1, </dev/null).
# RC and OUT (stdout + stderr) are the stdin run's; PATHS_AGREE is yes when both
# runs have the same rc and byte-identical stderr; ENV_RAW is HOOK_RAW as exported.
_both() {
  local s=$1 p=$2 rc2
  printf '%s' "$p" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/gates/$s.sh" >"$T/o1" 2>"$T/e1"; RC=$?
  (
    export CLAUDE_PROJECT_DIR="$PROJECT"
    hook_read_payload < <(printf '%s' "$p")
    classify_command || true
    TOP=$(repo_top) || TOP=''
    printf '%s' "$HOOK_RAW" >"$T/raw2"
    export HOOK_PAYLOAD_SET=1 HOOK_CMD HOOK_CWD HOOK_FILE HOOK_RAW HOOK_GIT_DIR HOOK_CLASSES TOP
    exec bash "$HOOKS/gates/$s.sh" </dev/null >"$T/o2" 2>"$T/e2"
  ); rc2=$?
  OUT=$(cat "$T/o1" "$T/e1"); ERR=$(cat "$T/e1"); ENV_RAW=$(cat "$T/raw2")
  if [ "$RC" = "$rc2" ] && cmp -s "$T/e1" "$T/e2"; then PATHS_AGREE=yes; else PATHS_AGREE="no (env path rc=$rc2)"; fi
}
gate() { # gate <stage> <want-rc> <where> <command> [label]
  local s=$1 want=$2 cwd label; cwd=$(where "$3")
  label="$s($want) cwd=$3: ${5:-$4}"; label=${label//$'\n'/ ⏎ }
  _both "$s" "$(payload "$4" "$cwd")"
  [ "$RC" = "$want" ] && ok "$label" || bad "$label (got $RC)"
  [ "$PATHS_AGREE" = yes ] || bad "  …but the env-exported path differs: $PATHS_AGREE $(diff "$T/e1" "$T/e2" | head -4 | tr '\n' ' ')"
}
raw() { # raw <stage> <want-rc> <raw-stdin> <label>
  _both "$1" "$3"
  [ "$RC" = "$2" ] && ok "$1($2) raw: $4" || bad "$1($2) raw: $4 (got $RC)"
  [ "$PATHS_AGREE" = yes ] || bad "  …but the env-exported path differs: $PATHS_AGREE $(diff "$T/e1" "$T/e2" | head -4 | tr '\n' ' ')"
}
hook() { # hook <hook> <want-rc> <where> <command> [label]   — a hook outside gates/, stdin only
  local h=$1 want=$2 cwd label; cwd=$(where "$3")
  label="$h($want) cwd=$3: ${5:-$4}"; label=${label//$'\n'/ ⏎ }
  OUT=$(payload "$4" "$cwd" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/$h.sh" 2>&1); RC=$?
  [ "$RC" = "$want" ] && ok "$label" || bad "$label (got $RC)"
}
stop_hook() { # stop_hook <want-rc> <where> <label>
  local want=$1 cwd; cwd=$(where "$2")
  OUT=$(jq -n --arg d "$cwd" '{hook_event_name:"Stop",stop_hook_active:false,cwd:$d}' |
    CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/typecheck-on-stop.sh" 2>&1); RC=$?
  [ "$RC" = "$want" ] && ok "typecheck-on-stop($want) cwd=$2: $3" || bad "typecheck-on-stop($want) cwd=$2: $3 (got $RC)"
}
dispatch() { # dispatch <want-rc> <where> <command> [label]   — bash-gate.sh; HOOK_GATES_DIR etc. from the caller's env
  local want=$1 cwd label; cwd=$(where "$2")
  label="dispatch($want) cwd=$2: ${4:-$3}"; label=${label//$'\n'/ ⏎ }
  : >"$FAKE_STAGE_LOG"
  payload "$3" "$cwd" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/bash-gate.sh" >"$T/o1" 2>"$T/e1"; RC=$?
  OUT=$(cat "$T/o1" "$T/e1"); ERR=$(cat "$T/e1")
  [ "$RC" = "$want" ] && ok "$label" || bad "$label (got $RC): $(printf '%s' "$ERR" | head -3 | tr '\n' ' ')"
}
dispatch_raw() { # dispatch_raw <want-rc> <raw-stdin> <label>
  : >"$FAKE_STAGE_LOG"
  printf '%s' "$2" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOKS/bash-gate.sh" >"$T/o1" 2>"$T/e1"; RC=$?
  OUT=$(cat "$T/o1" "$T/e1"); ERR=$(cat "$T/e1")
  [ "$RC" = "$1" ] && ok "dispatch($1) raw: $3" || bad "dispatch($1) raw: $3 (got $RC)"
}
silent() { [ -z "$OUT" ] && ok "  …and said nothing" || bad "  …but printed: $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"; }
said() { case $OUT in *"$1"*) ok "  …and said: $1" ;; *) bad "  …but did not say: $1 (said: $(printf '%s' "$OUT" | head -6 | tr '\n' ' '))" ;; esac; }
unsaid() { case $OUT in *"$1"*) bad "  …but said: $1" ;; *) ok "  …and did not say: $1" ;; esac; }
stages_ran() { # stages_ran "<names in order>"   — what the fake stages logged
  local got; got=$(tr '\n' ' ' <"$FAKE_STAGE_LOG"); got=${got% }
  [ "$got" = "$1" ] && ok "  …stages ran: [${1:-none}]" || bad "  …stages ran: [$got], expected [${1:-none}]"
}

# --- rows ---------------------------------------------------------------------
for rows in "$ROOT"/scripts/hooks.test.d/*.sh; do
  [ -f "$rows" ] || continue
  # shellcheck disable=SC1090
  . "$rows"
done

echo
[ "$fails" = 0 ] && echo "all passed" || echo "$fails FAILED"
exit $((fails > 0))
