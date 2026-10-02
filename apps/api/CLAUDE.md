# apps/api: backend guide

## 1. Before you code here

Read `internal-docs/README.md`, then the page the map below names for the path you are touching; it is the source of truth for the subsystem and is updated in the same commit as the code (the docs gate blocks a commit that stages API code without an `internal-docs/` change). Every gate is in `internal-docs/runbooks/local-gates.md`.

## 2. Map: path → internal-docs page

Paths are under `apps/api/src/`; pages under `internal-docs/`. Rendered from `.claude/review-map.yml` (`node scripts/review-map.mjs render apps/api/CLAUDE.md`); edit the map, not the table.

<!-- review-map:api-pages -->

| You're touching…                   | Read / update          |
| ---------------------------------- | ---------------------- |
| `auth/**`, `config/**`, `users/**` | `architecture/auth.md` |
| `*.ts`, `common/**`                | `architecture/api.md`  |

<!-- /review-map:api-pages -->

## 3. Rules

- Every route is guarded: `JwtAuthGuard` and `RolesGuard` are global. `@Public()` opts a route or controller out; `@Roles("admin")` restricts it. Never add `@UseGuards(JwtAuthGuard)` by hand.
- Config through `ConfigService.getOrThrow`; a new variable is validated in `config/env.validation.ts` and named in `.env.example`.
- DTOs carry class-validator decorators; the global pipe rejects unknown fields. Never accept a privilege field (roles, status) from a request body.
- Never return a password: the `User` schema's `toJSON` strips it; a projection or a lean query must too (`.select("-password")`).

## 4. Verify

- `pnpm --filter @acme/api test` (every spec) and `pnpm --filter @acme/api test:e2e` (the e2e specs, against in-memory MongoDB).
- `pnpm --filter @acme/api build && pnpm --filter @acme/api boot:check`: does the compiled app start.
- `bash scripts/lifecycle-suite.sh` before a PR that touches auth or users (the PR gate asks for its marker).
