#!/usr/bin/env bash
# SessionStart hook: point the session at the internal engineering docs so work
# loads the relevant page first. Injected into model context.
read -r -d '' CTX <<'TXT'
This repo keeps its engineering docs under `internal-docs/` (index: `internal-docs/README.md`), the source of truth for backend and frontend.

BACKEND (`apps/api/**`): read `internal-docs/README.md`, then the page for the subsystem (auth -> architecture/auth.md; modules, config, errors -> architecture/api.md). Map: `apps/api/CLAUDE.md`.

FRONTEND (`apps/nextjs/**`, `packages/ui/**`): read `internal-docs/frontend/README.md`. Reuse `@acme/ui` components and react-hook-form + zod (`@acme/validators`) for forms before inventing new primitives. Map: `apps/nextjs/CLAUDE.md` and `packages/ui/CLAUDE.md`.

After changing backend or frontend behaviour, update the matching internal-docs page in the same commit; the docs gate enforces it. `bash scripts/obligations.sh` lists what the branch still owes.
TXT
jq -n --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
