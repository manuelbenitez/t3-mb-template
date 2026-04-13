# t3-mb-template

A production-ready full-stack monorepo template. Clone it, run one script, start writing business logic.

**Stack:** Next.js 16 · React 19 · NestJS · MongoDB/Mongoose · shadcn/ui · Tailwind 4 · pnpm · Turborepo

---

## Quick Start

```bash
git clone https://github.com/yourusername/t3-mb-template.git my-project
cd my-project
./setup.sh
pnpm dev
```

`setup.sh` is interactive. It asks 5 questions and handles everything:

| Prompt | What it does |
|--------|-------------|
| Org name | Replaces `@acme` across the entire codebase |
| Project name | Sets the root `package.json` name |
| MongoDB URI | Written to `.env` |
| JWT secret | Auto-generates with `openssl rand -base64 32` if you skip |
| Frontend URL | Sets the CORS origin on the API |

After setup: `pnpm dev` starts both apps in parallel.

---

## What's Included

### Apps

| | Port | Description |
|--|------|-------------|
| `apps/nextjs` | 3000 | Next.js 16 + React 19 + shadcn/ui |
| `apps/api` | 3001 | NestJS + JWT auth + MongoDB |

### Packages

| | Description |
|--|-------------|
| `packages/ui` | shadcn/ui component library |
| `packages/validators` | Shared zod schemas (used in both apps) |
| `packages/api-client` | Typed fetch wrapper for the API |

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
- `@Public()` decorator on any route to bypass the global `JwtAuthGuard`
- `@GetUser()` param decorator to access the current user in controllers
- Passwords hashed with bcrypt (10 rounds)

**Swagger UI** at `http://localhost:3001/api/docs` when the API is running.

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
│           ├── auth/            JWT auth (controller, service, strategy, guards)
│           ├── users/           User CRUD (schema, service, controller)
│           └── common/          HttpExceptionFilter (global error formatter)
├── packages/
│   ├── ui/                      shadcn/ui components
│   ├── validators/              Zod schemas shared between frontend and backend
│   └── api-client/              Type-safe fetch client (no React dependencies)
├── tooling/                     Shared ESLint, Prettier, TypeScript, Tailwind configs
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
export const createPostSchema = z.object({ title: z.string().min(1), body: z.string() })
export type CreatePostInput = z.infer<typeof createPostSchema>
```

**3. API client** — add to `packages/api-client/src/`
```ts
export function createPostsClient(client: ApiClient) {
  return {
    create: (data: CreatePostInput) => client.post<Post>("/api/posts", data),
    list: () => client.get<Post[]>("/api/posts"),
  }
}
```

**4. Frontend** — add page + react-query hook in `apps/nextjs/src/`

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

| Command | Description |
|---------|-------------|
| `pnpm dev` | Start Next.js + API in parallel |
| `pnpm dev:next` | Next.js only (port 3000) |
| `pnpm dev:api` | API only (port 3001) |
| `pnpm build` | Build all packages |
| `pnpm typecheck` | Type-check all workspaces |
| `pnpm lint` | Lint all workspaces |
| `pnpm format` | Format with Prettier |
| `pnpm ui-add` | Add a shadcn/ui component |

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

- Node.js >= 20
- pnpm >= 10.19
- MongoDB (local or Atlas)
