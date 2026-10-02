# Project

A full-stack monorepo: `apps/api` (NestJS 12 + MongoDB), `apps/nextjs` (Next.js 16 portal), `packages/ui` (shadcn/ui), `packages/validators` (shared zod schemas), `packages/api-client` (typed fetch client), `tooling/` (eslint, prettier, tailwind, tsconfig).

## Posture

- Boring by default: minimal scope, reversible changes, right-sized to the product's stage.
- Fail closed: config without a default, routes guarded unless marked `@Public()`, gates that block when they cannot tell.
- Replace this section with the product's own standing context (stage, market, constraints) once there is one.

## Hard rules

- pnpm only (`packageManager` in `package.json`; the one lockfile is `pnpm-lock.yaml`). Versions go through the `catalog:` in `pnpm-workspace.yaml`; overrides live there too, never in `package.json`.
- All work on branches, landed by PR; never push to `main` (the push gate refuses it).
- No AI attribution lines in commits (`.claude/hooks/gates/coauthor.sh` blocks them; `project.attribution_guard` in the map turns it off).
- Stage in its own call, then commit alone, then push alone. The gates read the index before the command runs, so a commit that also stages, or a push in the same call as a commit, is refused.
- Secrets live in `.env` (never committed) and the deploy platform; never in code or docs. A new variable is validated in `apps/api/src/config/env.validation.ts` and named in `.env.example`.
- Read config with `ConfigService.getOrThrow`; never a fallback default for a secret.

## Docs are part of the change

Code under `apps/api/src` updates its `internal-docs/` page in the same commit; code under `apps/nextjs/src` or `packages/ui/src` updates a page under `internal-docs/frontend/`. The docs gate enforces it and names the page from `.claude/review-map.yml`. Index: `internal-docs/README.md`.

## What gates a change

The local Claude Code hooks are the gate. One PreToolUse hook on the Bash tool, `.claude/hooks/bash-gate.sh`, classifies a command as a commit, a push or a PR open and runs the stages under `.claude/hooks/gates/`. Every gate, its trigger, remedy and bypass: `internal-docs/runbooks/local-gates.md`.

- On a commit: the attribution guard, the secret block, the docs gate, then the deps check on a manifest change, typecheck and eslint on the staged files, and the tests related to the staged files (`bash scripts/test-changed.sh <paths>`). Any failure blocks.
- On `git push`: never to `main`; a forced update needs `--force-with-lease`; a branch with an open PR needs review evidence for the pushed sha (`bash scripts/ai-review.sh verify`).
- On `gh pr create`: the lifecycle marker (`bash scripts/lifecycle-suite.sh`) when an auth or users path changed, the deps marker (`bash scripts/deps-smoke.sh`) when a manifest changed, and the review mark (`bash scripts/ai-review.sh mark`, after `/review`).
- `bash scripts/obligations.sh` prints what a branch still owes; the session-start hook injects it. On edit: secret scan, prettier and eslint fix, reuse nudge, scope nudge. On stop: typecheck of the touched workspaces.
- Everything project-specific (repo, workspaces, docs pairs, commands) is the `project:` block of `.claude/review-map.yml`.

## Skills: touch X, run Y

gstack: `/review` before every PR (required; its log is the evidence the push and PR gates read), `/investigate` for debugging, `/careful` around destructive commands. Review skills attached to paths are rendered from `.claude/review-map.yml` (`node scripts/review-map.mjs render CLAUDE.md`); a trigger-only skill is suggested, never required. Edit the map, not the table.

<!-- review-map:skills -->

| Skill  | Touch                               | When                                                                                 |
| ------ | ----------------------------------- | ------------------------------------------------------------------------------------ |
| `/cso` | auth, guards, users, env validation | authentication, sessions, secrets, permissions, anything an attacker would try first |

<!-- /review-map:skills -->

## Maps

- `internal-docs/README.md`: the engineering docs index.
- `apps/api/CLAUDE.md`: backend guide and the path-to-page map. `apps/nextjs/CLAUDE.md`: the portal. `packages/ui/CLAUDE.md`: the component library.
- `.claude/hooks/`: the dispatcher and its stages; `.claude/review-map.yml` the map they read; `scripts/` the by-hand suites and the gate tests (`pnpm test:gates`).
