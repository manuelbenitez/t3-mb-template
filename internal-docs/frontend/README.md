# Portal (apps/nextjs)

Next.js 16 App Router, React 19, Tailwind 4 with the shared theme from `tooling/tailwind`.

## Routes

- `src/app/(auth)/login`, `src/app/(auth)/register`: the auth forms.
- `src/app/(dashboard)/dashboard`: the signed-in landing page.
- `src/app/providers.tsx`: the TanStack Query provider (`src/lib/query-client.ts`: one client per request on the server, one per tab in the browser).

## Data

- `src/lib/api.ts` builds the one `ApiClient` from `@acme/api-client` against `NEXT_PUBLIC_API_URL` and injects the bearer token from `localStorage`.
- Hooks in `src/hooks/` wrap queries and mutations (`use-auth.ts`: login, register, logout; `use-current-user.ts`: the session, query key `["session"]`).
- `src/env.ts` validates the public env with zod at build time (`next.config.ts` imports it), so a bad `NEXT_PUBLIC_API_URL` fails the build.

## Forms

react-hook-form with `zodResolver` and the shared schemas from `@acme/validators`, so the portal and the API validate the same shape.

## Components

Reuse `@acme/ui` before writing a primitive ([component-library.md](component-library.md)); add shadcn components with `pnpm ui-add`.

## Tests

Vitest, node environment by default; a component test opts into a DOM with a `// @vitest-environment jsdom` docblock. `pnpm --filter @acme/nextjs test`.
