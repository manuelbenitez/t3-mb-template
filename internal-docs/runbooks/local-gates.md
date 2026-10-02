# Runbook: local gates

What the Claude Code hooks check on every commit, push and PR-opening command, what each gate reads and blocks on, the command that satisfies it, and the honest list of ways past it. The code is `.claude/hooks/` (the dispatcher `bash-gate.sh`, its stages under `gates/`, the shared `lib.sh`), `scripts/ai-review.sh`, `scripts/lifecycle-suite.sh`, `scripts/deps-smoke.sh` and `scripts/obligations.sh`; the wiring is `.claude/settings.json`. Everything project-specific lives in one file, `.claude/review-map.yml`, read only through `scripts/review-map.mjs`.

Posture: deterministic shell at commit time (cheap, fail-closed), evidence at PR open (where a bypass has to be deliberate). No model in the loop at commit, no full suite per commit. Every gate is worktree-aware. The property that matters is per commit: the reviewed code merges, not the reviewed branch. The hooks bind Claude Code sessions only; a commit made outside one skips every gate on this page.

## Setup

- **gstack** (required): `/review`, whose log the push and PR gates read. `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`. The session-start hook nags while it is missing.
- **jq**, **node 22+**, **git 2.31+** on PATH. Without jq every gate fails closed.
- **GitHub:** add the `ai-review` commit status as a required check on `main` (Settings → Branches). `ai-review.sh mark` posts it; that is the control that holds at merge time.

## Vocabulary

- **TOP**: the toplevel of the tree a command acts on, from a `cd` or `git -C` in the command, else the payload's cwd, never the session root (`repo_top`).
- **This project**: `is_project_repo` is true for a checkout or worktree of the repository holding the hooks, or any clone whose `origin` is `project.repo`. Every gate except the attribution guard exits 0 for another repository a session happens to operate on.
- **`<state>`**: `<git common dir>/<project.state_dir>`, shared by every worktree (`state_dir`).
- **Changed paths**: always `git diff --no-renames`: a rename-detecting diff hides a code deletion inside a docs-only delta.
- **Rule ids** (B-numbers in comments and tests):

| Id  | Rule                                                                              |
| --- | --------------------------------------------------------------------------------- |
| B3  | A heredoc body is text, unless it is fed to a shell (`bash <<EOF`), which runs it |
| B4  | Fail closed: a missing, crashed or timed-out stage blocks                         |
| B5  | A reused message (`--amend --no-edit`, `-C`, `--fixup`) is read from that commit  |
| B6  | User-docs `lastVerified` is keyed to the page's landed history                    |
| B7  | The lifecycle-suite marker, keyed to `project.lifecycle_inputs`                   |
| B8  | The push gate decides from `git push --dry-run --porcelain`, never refspec text   |
| B9  | The deps smoke: a cheap check at commit, build + boot by hand before the PR       |
| B10 | Obligations are computed from the tree and the log, never stored                  |
| B11 | `verify`: what counts as review evidence, and when it carries to a later commit   |
| B12 | The edit-time nudge, once per file per session                                    |
| B15 | A commit that also stages is refused on its shape                                 |
| B16 | One deadline for the dispatcher; a killed stage names its by-hand command         |
| B17 | State under the common git dir, pruned at session start                           |
| B19 | One secret-exemption list for the on-edit nudge and the commit gate               |

## How a command is gated

`.claude/settings.json` binds one PreToolUse hook to the Bash tool, `bash-gate.sh` (`timeout: 900`). It reads the payload once, normalizes the command and classifies it into `{commit, push, pr-open}`: `git commit -m x && git push` is both. A command in no class exits 0 at once and spawns nothing (the harness asserts under 100 ms). Then it loads the `project:` block once and exports it, so no stage starts node again.

- **Combined commit shapes are refused first (B15):** `git add … && git commit`, `-a`, `-i`, `-p`, `-o`, a short-flag cluster carrying one (`-am`), a pathspec or a bare `--`. The gates read the index before the command runs, so the commit would be judged on the wrong content. Stage in its own call, then commit alone.
- **Heredocs (B3):** a commit message or a doc that mentions `git commit` is not a commit.
- **Stage contract:** each stage is a standalone script. Piped a payload it reads it; spawned by the dispatcher with `HOOK_PAYLOAD_SET=1` it trusts the exported variables. Run any gate by hand: `printf '{"tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$PWD" | bash .claude/hooks/gates/<gate>.sh`.
- **The clock (B16):** an 840 s deadline; the cheap gates 30 s each, deps-smoke 150 s, typecheck-lint 180 s, tests the rest, push and pr-open 60 s. A killed stage blocks with `gate timed out in <stage>… Run it yourself: <command>`.
- **Aggregation:** the cheap tier (coauthor, secret-block, docs-gate, user-docs-freshness) runs to completion and reports every failure in one block; from deps-smoke on, the first block stops the chain.
- **When TOP is not the shell's checkout** the block adds `skills must run with the shell inside <TOP>`: gstack reads the checkout the shell stands in.

## Commit gates

| Gate                       | Fires on                                                           | Blocks on                                                                                                                                                                                                                        | Remedy                                                       |
| -------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `coauthor`                 | every commit, any repo, when `project.attribution_guard`           | `Co-Authored-By: Claude`, `Generated with Claude Code`, `noreply@anthropic.com`, a claude.ai session link, in the message or a reused one (B5)                                                                                   | rewrite the message (an amend reuses the old one: pass `-m`) |
| `secret-block` (B19)       | staged paths outside `project.secret_exempt`                       | an added credential literal (`password`/`secret`/`token`… `=` a quoted 12+ char value, unless the line reads config or is an example), a private key, a JWT in source                                                            | move it to `.env`, add the name to `.env.example`            |
| `docs-gate`                | anything staged                                                    | a path with docs areas (every matching `project.docs_pairs` entry) and nothing under one of them staged; a `project.user_visible` path with no change under `project.user_docs_root` and no `User-Docs: none — <reason>` trailer | stage the page it names (from the rule's `internal_docs`)    |
| `user-docs-freshness` (B6) | staged pages under `project.user_docs_root` (off when empty)       | `lastVerified` older than the page's last change on `origin/main`, or in the future                                                                                                                                              | set the date, restage                                        |
| `deps-smoke` (B9)          | a staged `package.json`, `pnpm-lock.yaml` or `pnpm-workspace.yaml` | the first failing `project.deps_check` command (lockfile vs manifests offline, then typecheck)                                                                                                                                   | `pnpm install`, stage the lockfile                           |
| `typecheck-lint`           | a staged TS/JS file                                                | `pnpm typecheck`, or eslint on the staged files from each file's own package                                                                                                                                                     | `pnpm typecheck && pnpm lint`                                |
| `tests`                    | a staged code file or hook                                         | `bash scripts/test-changed.sh <files>`: `vitest related` in each workspace of `project.workspaces`, plus the consumers of a changed package; the hook harness for the hooks; the map tests for the map                           | the same command                                             |

Specs, tests and stories (`project.docs_exempt`) never need docs. A project tripwire (a banned import, a parse guard) belongs in `typecheck-lint.sh` as one more `pnpm <script>` step.

## The push gate (`gates/push.sh`, B8)

- **Scope:** a push from this project, or to `project.repo` from any clone (a fork's `upstream`, a push by URL).

- **Refused before any network:** a command that also moves HEAD (`git commit … && git push`: commit first, then push alone); `--all`, `--mirror`, `--prune` (push one ref).
- **The dry run:** `git push --dry-run --porcelain <the push's own arguments>`; a failure blocks with `cannot tell what would be pushed`.
- **Per ref:** to `main` → `main is landed by PR`. A forced update needs `--force-with-lease` (or `--force-if-includes`). A ref with an open PR (`gh pr list --head`, falling back to the local `<state>/pr-open/<slug>` marker when gh fails) needs `ai-review.sh verify` to pass on the sha git would push.

## The pr-open gate (`gates/pr-open.sh`)

- **Fires:** `gh pr create|new|ready`, a `gh api` POST to `…/pulls`, a `createPullRequest` mutation.
- **Refused first:** a command that also moves HEAD, changes directory, or uses `-H/--head/-R/--repo`.
- **Needs**, for `origin/main...HEAD`: the lifecycle marker when a `lifecycle:` path changed (B7: `bash scripts/lifecycle-suite.sh`); the deps marker when a manifest changed (B9: `bash scripts/deps-smoke.sh`); the ai-review mark for HEAD (`bash scripts/ai-review.sh mark`).
- **On pass:** writes `<state>/pr-open/<slug>`, the push gate's offline cache.

## The review loop

`bash scripts/obligations.sh` prints what the branch still owes: the changed paths, the review evidence per required name, the docs pages the map expects, and the marker status. The session-start hook injects it.

First PR: commit → `/review` (plus any required skill the map names) → `git push` (no PR yet, allowed) → `bash scripts/ai-review.sh mark` → `gh pr create`.
Later commits: commit → `/review` → `git push` (the gate runs `verify` on the pushed sha) → `mark`.

### `ai-review.sh` (B11)

- **`verify [sha]`**: log-side only, no network. Required names are `review` plus the map's `required_skills` for the changed paths (trigger-only skills never count). A **satisfying record** names the commit (`commit_full`), was taken on a clean tree, and is `clean` or `issues_found` with `critical == 0`. A record on an earlier commit **carries** when the delta since is docs-only (`review`), or touches none of that skill's paths and no code outside every skill's rules (other skills). A merge of `main` never carries `review`. Exit 0 satisfied, 1 missing, 2 unreadable.
- **`mark [summary] [--force]`**: verify, post the `ai-review` commit status, write `<git common dir>/ai-review/<sha>`. `--force` marks without evidence and says FORCED in the status.
- **`check [sha]`**: the marker exists (what pr-open reads). **`fail [reason]`**: revokes it and posts a red status.

### `lifecycle-suite.sh` (B7) and `deps-smoke.sh` (B9)

Both run by hand from a clean checkout and write a marker keyed to what they can see, so unrelated commits keep it. `lifecycle-suite.sh` runs `project.lifecycle_suite` (default: the API's e2e specs, against in-memory MongoDB, with a private `TMPDIR`, refusing under 4 GiB free in `/tmp`). `deps-smoke.sh` runs `project.deps_smoke` (default: build the API, then `boot:check` starts `dist/main.js`); it refuses while something listens on the API port unless `DEPS_SMOKE_ALLOW_DEV=1`.

## Context and nudges

- **SessionStart:** `check-skills.sh` (gstack installed?), `internal-docs-index.sh` (points the session at these docs), `obligations-context.sh` (prunes stale state, injects `obligations.sh`).
- **PreToolUse Edit|Write:** `reuse-ui-primitives.sh`, a nudge toward `@acme/ui` when a new primitive-looking component is created.
- **PostToolUse Edit|Write:** `secret-scan.sh` (wider patterns, a message, never a block), `format-on-edit.sh` (prettier and eslint `--fix` from the file's package), `ui-inventory-drift.sh`, `edit-nudge.sh` (B12: the skills, page and user-docs area the map attaches to the file, once per file per session).
- **Stop:** `typecheck-on-stop.sh` typechecks the touched workspaces and wakes the session on failure.

## State (B17)

`<state>/lifecycle/<key>`, `<state>/deps/<key>`, `<state>/pr-open/<slug>`, `<state>/nudged/<session>/<sha1>`, plus `<git common dir>/ai-review/<sha>`. Plain unsigned files, shared by every worktree, surviving `git worktree remove`. Session start prunes `nudged/` older than 7 days and `pr-open/` markers of deleted branches.

## The review map

`.claude/review-map.yml`: the `project:` block (every gate's configuration), `docs_only` / `never_docs_only` (the carry-over verdict), `lifecycle` (paths that need the lifecycle marker), `skills` and `rules` (path globs → skills and internal-docs pages). `scripts/review-map.mjs` subcommands: `match <paths>`, `lists`, `config`, `render <file>` (the `<!-- review-map:… -->` blocks in `project.rendered_files`), `check` (every glob matches a tracked file, every page and workspace exists, the rendered blocks are current). After editing: `node scripts/review-map.mjs render CLAUDE.md && node scripts/review-map.mjs render apps/api/CLAUDE.md && node scripts/review-map.mjs check`. `check` reads `git ls-files`, so `git add` the files a new rule globs before checking.

**Adding a review skill:** a skill entry (`name: { when: "…" }`), then a rule naming it. A required skill must write records to gstack's review log (`skill`, `commit_full`, `status`), or `verify` can never be satisfied; a skill that only advises is `trigger_only: true` with `touch:` prose (it is suggested, never required).

## Bypasses, stated honestly

Every block names its remedy and never a bypass. The ways past exist; they are listed so nobody mistakes a gate for a boundary.

| Way past                                                        | What it does                                                                                                                                                   |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash scripts/ai-review.sh mark --force`                        | Marks without evidence; the status and marker say FORCED.                                                                                                      |
| `HOOK_ALLOW_FORCE_PUSH=1 git push -f origin <branch>`           | Lets a bare force push through (the prefix form only). `main` stays refused.                                                                                   |
| Commits the Bash tool never sees                                | `git rebase --continue`, `git merge`, another terminal or editor, an alias, `$GIT commit`, a script file. The push and PR gates still judge the resulting sha. |
| A branch that edits `.claude/hooks/**`, `scripts/**` or the map | Judges itself: the hooks are re-read from the working tree. Put those paths in CODEOWNERS.                                                                     |
| `gh` failing during a push                                      | Falls back to the local pr-open marker; a PR opened in the browser leaves none, so an offline push to it is not verified.                                      |
| `touch` a marker                                                | Satisfies pr-open. Markers are unsigned local flags.                                                                                                           |
| A review logged or a status posted by hand                      | Satisfies `verify`, `mark` or the required check. Takes someone acting deliberately, which is the line these controls draw.                                    |
| A PR opened in the browser                                      | The pr-open gate is textual and local; the required `ai-review` status is the merge-time control.                                                              |

## Tests

- `bash scripts/hooks.test.sh`: the harness, rows in `scripts/hooks.test.d/*.sh`. A throwaway tree (a bare remote named after `project.repo`, a clone, a worktree, an unrelated repo) with fake `pnpm`, `gh`, `df` and review-log reader that record their calls. Its map is this one plus user docs and a fixture-only required skill, so every gate's paths run even while the project uses none of them. Every gate row runs twice (piped and exported) and asserts identical results.
- `bash scripts/ai-review.test.sh`: `verify`, `mark`, the carry-over, merges, the log files, the pr-open matcher.
- `node scripts/review-map.test.mjs` and `node scripts/review-map.mjs check`.
- `pnpm test:gates` runs all three. CI runs them too.
- Lint: `shellcheck -x -S warning .claude/hooks/*.sh .claude/hooks/gates/*.sh scripts/*.sh scripts/hooks.test.d/*.sh`.
