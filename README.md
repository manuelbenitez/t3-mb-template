# t3-mb-template

A production-ready full-stack monorepo template with an agentic workflow built in: Claude Code hooks that gate every commit, push and PR. Clone it, run one script, start writing business logic.

**Stack:** Next.js 16 · React 19 · NestJS 12 · MongoDB/Mongoose 9 · shadcn/ui · Tailwind 4 · zod 4 · Vitest · pnpm · Turborepo

---

## Quick Start

```bash
git clone https://github.com/manuelbenitez/t3-mb-template.git my-project
cd my-project
./setup.sh
pnpm dev
```

`setup.sh` is interactive. It asks 6 questions and handles everything:

| Prompt            | What it does                                                         |
| ----------------- | -------------------------------------------------------------------- |
| Org name          | Replaces `@acme` across the entire codebase                          |
| Project name      | Sets the root `package.json` name                                    |
| GitHub repository | Points the Claude Code gates at your repo (`.claude/review-map.yml`) |
| MongoDB URI       | Written to `.env`                                                    |
| JWT secret        | Auto-generates with `openssl rand -base64 32` if you skip            |
| Frontend URL      | Sets the CORS origin on the API                                      |

After setup: `pnpm dev` starts both apps in parallel. For the agentic workflow, install [gstack](https://github.com/garrytan/gstack) (see below).

---

## What's Included

### Apps

|               | Port | Description                       |
| ------------- | ---- | --------------------------------- |
| `apps/nextjs` | 3000 | Next.js 16 + React 19 + shadcn/ui |
| `apps/api`    | 3001 | NestJS + JWT auth + MongoDB       |

### Packages

|                       | Description                            |
| --------------------- | -------------------------------------- |
| `packages/ui`         | shadcn/ui component library            |
| `packages/validators` | Shared zod schemas (used in both apps) |
| `packages/api-client` | Typed fetch wrapper for the API        |

### Tooling

Shared configs in `tooling/` — TypeScript, ESLint, Prettier, Tailwind 4.

---

## Auth

Wired up out of the box. No configuration needed.

```
POST /api/auth/register   { name, email, password }  →  { access_token, user }
POST /api/auth/login      { email, password }         →  { access_token, user }
GET  /api/auth/session    Authorization: Bearer ...   →  { user }
```

- JWT stored in `localStorage`, injected automatically by `api-client`
- Every route requires a valid token: `JwtAuthGuard` is global (`APP_GUARD`). Opt out with `@Public()` on a handler or a whole controller
- `@Roles("admin")` restricts a route by role (global `RolesGuard`); roles live in `ROLES` in `user.schema.ts` (`user`, `admin`), new accounts get `user`
- `@GetUser()` param decorator to access the current user in controllers
- Suspended or paused accounts get 403 even with a valid token
- The API refuses to boot unless `JWT_SECRET` is at least 32 characters and not the `.env.example` placeholder
- Passwords hashed with bcrypt (10 rounds)

**Swagger UI** at `http://localhost:3001/api/docs` when the API is running.

---

## Agentic workflow (Claude Code)

The repo ships the hooks, docs and review map that make Claude Code sessions safe to run on it. They bind every Claude Code session in the repo; a commit made outside one skips them.

| When                 | What runs                                                                                                                                                                |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `git commit`         | Blocks AI attribution lines, added secrets, code without its `internal-docs/` page, a stale lockfile, type or lint errors in the staged files, and failing related tests |
| `git push`           | Never to `main`; force pushes need `--force-with-lease`; a branch with an open PR needs `/review` evidence for the pushed commit                                         |
| `gh pr create`       | Needs the `/review` mark for HEAD, plus the e2e suite's marker when auth changed and the deps smoke when a manifest changed                                              |
| Editing a file       | prettier + eslint fix, a secret scan, a nudge naming the docs page and skills for that path                                                                              |
| Session start / stop | What the branch still owes (`bash scripts/obligations.sh`); a typecheck of the touched workspaces                                                                        |

Setup: install gstack (`git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`) and `jq`, then add the `ai-review` commit status as a required check on `main`.

The review loop: commit → `/review` → `git push` → `bash scripts/ai-review.sh mark` → `gh pr create`.

Everything project-specific (repo, workspaces, which paths need which docs, the commands) is the `project:` block of `.claude/review-map.yml`. The full reference, with every gate's trigger, remedy and bypass, is [`internal-docs/runbooks/local-gates.md`](internal-docs/runbooks/local-gates.md). `CLAUDE.md` files at the root and in each app tell sessions the rules.

---

## Project Structure

```
t3-mb-template/
├── apps/
│   ├── nextjs/                  Next.js frontend
│   │   └── src/
│   │       ├── app/             Pages (login, register, dashboard)
│   │       ├── hooks/           useLogin, useRegister, useLogout, useCurrentUser
│   │       ├── lib/             api.ts (client init), query-client.ts
│   │       └── env.ts           t3-env validated environment variables
│   └── api/                     NestJS backend
│       └── src/
│           ├── auth/            JWT auth (controller, service, strategy, global guards, roles)
│           ├── users/           Users (schema, service, controller)
│           ├── config/          Boot-time env validation
│           ├── testing/         Test app factory (in-memory MongoDB)
│           └── common/          HttpExceptionFilter (global error formatter)
├── packages/
│   ├── ui/                      shadcn/ui components
│   ├── validators/              Zod schemas shared between frontend and backend
│   └── api-client/              Type-safe fetch client (no React dependencies)
├── tooling/                     Shared ESLint, Prettier, TypeScript, Tailwind configs
├── internal-docs/               Engineering docs (architecture, frontend, runbooks)
├── .claude/                     Hooks, settings and the review map (the agentic gates)
├── scripts/                     Gate scripts and their tests
├── CLAUDE.md                    Rules for Claude Code sessions (also per app)
├── .env.example                 Documented environment template
└── setup.sh                     First-run setup script
```

---

## Adding a Feature

Typical pattern for a new resource (e.g. `posts`):

**1. API** — create `apps/api/src/posts/`

```
posts.module.ts
posts.controller.ts   ← routes
posts.service.ts      ← business logic
schemas/
  post.schema.ts      ← Mongoose schema
dto/
  create-post.dto.ts  ← class-validator DTOs
```

**2. Validators** — add to `packages/validators/src/posts.ts`

```ts
export const createPostSchema = z.object({
  title: z.string().min(1),
  body: z.string(),
});
export type CreatePostInput = z.infer<typeof createPostSchema>;
```

**3. API client** — add to `packages/api-client/src/`

```ts
export function createPostsClient(client: ApiClient) {
  return {
    create: (data: CreatePostInput) => client.post<Post>("/api/posts", data),
    list: () => client.get<Post[]>("/api/posts"),
  };
}
```

**4. Frontend** — add page + react-query hook in `apps/nextjs/src/`

**5. Docs and map** — add a page under `internal-docs/`, and a rule in `.claude/review-map.yml` pointing `apps/api/src/posts/**` at it. The docs gate and the edit nudge pick it up.

---

## Environment Variables

Copy `.env.example` to `.env` (or let `setup.sh` do it):

```bash
# Database
MONGODB_URI=mongodb://localhost:27017/myapp

# Auth
JWT_SECRET=                      # openssl rand -base64 32

# API
PORT=3001
FRONTEND_URL=http://localhost:3000
APP_NAME=My App

# Next.js
NEXT_PUBLIC_API_URL=http://localhost:3001   # no /api suffix
NODE_ENV=development
```

---

## Scripts

| Command           | Description                                                           |
| ----------------- | --------------------------------------------------------------------- |
| `pnpm dev`        | Start Next.js + API in parallel                                       |
| `pnpm dev:next`   | Next.js only (port 3000)                                              |
| `pnpm dev:api`    | API only (port 3001)                                                  |
| `pnpm build`      | Build all packages                                                    |
| `pnpm typecheck`  | Type-check all workspaces                                             |
| `pnpm test`       | Run every workspace's tests (Vitest)                                  |
| `pnpm test:gates` | The hook harness, the review-evidence suite and the review-map checks |
| `pnpm lint`       | Lint all workspaces                                                   |
| `pnpm format`     | Format with Prettier                                                  |
| `pnpm ui-add`     | Add a shadcn/ui component                                             |

---

## Per-Client Workflow

This repo is designed to be used as a template. For each new client project:

```bash
# Option A: GitHub template UI
# → Settings → check "Template repository"
# → Use this template → create new private repo

# Option B: manual clone
git clone git@github.com:you/t3-mb-template.git client-name
cd client-name
git remote set-url origin git@github.com:you/client-name.git
./setup.sh
```

Each project is independent — changes in one don't affect the others.

---

## Requirements

- Node.js 24 LTS (`.nvmrc`; >= 22.22.3 works)
- pnpm >= 10.19
- MongoDB (local or Atlas); tests use an in-memory server
- For the agentic workflow: Claude Code, gstack, `jq`, `gh`
