# Internal docs

Engineering docs for this repository: how it is built, why, and how to change it safely. The source of truth for backend and frontend behaviour. Not user documentation.

**The rule:** a commit that changes code under `apps/api/src` updates a page here; one under `apps/nextjs/src` or `packages/ui/src` updates a page under `frontend/`. The docs gate blocks the commit otherwise (see [runbooks/local-gates.md](runbooks/local-gates.md)). Which page belongs to which path is in `.claude/review-map.yml`; `bash scripts/obligations.sh` lists what a branch still owes.

## Architecture

| Page                                         | Covers                                                                                            |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| [architecture/api.md](architecture/api.md)   | NestJS app shape: modules, config and env validation, the `/api` prefix, errors, Swagger, testing |
| [architecture/auth.md](architecture/auth.md) | JWT auth: register, login, session, the global guards, roles, account status, the secret          |

## Frontend

| Page                                                           | Covers                                                       |
| -------------------------------------------------------------- | ------------------------------------------------------------ |
| [frontend/README.md](frontend/README.md)                       | The Next.js portal: routes, data fetching, forms, auth state |
| [frontend/component-library.md](frontend/component-library.md) | `@acme/ui`: what exists, how to add a component              |

## Runbooks

| Page                                               | Covers                                                                                   |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [runbooks/local-gates.md](runbooks/local-gates.md) | The Claude Code hooks: every commit, push and PR gate, the review evidence, the bypasses |

## Adding a page

Create it under the right folder, link it from this index, and point the paths it describes at it in `.claude/review-map.yml` (`internal_docs:` of a rule). Then `node scripts/review-map.mjs check`.
