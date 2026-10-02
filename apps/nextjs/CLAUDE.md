# apps/nextjs: portal

## Read first

[internal-docs/frontend/README.md](../../internal-docs/frontend/README.md): routes, data fetching, forms, auth state.

## Rules

- Reuse `@acme/ui` before writing a primitive; extend it with a prop or variant rather than forking (a nudge fires on a new primitive-looking component).
- Server data goes through `@acme/api-client` via the hooks in `src/hooks/`; one query key per resource.
- Forms: react-hook-form + `zodResolver` + the schema from `@acme/validators`, so the portal and the API validate the same shape.
- Public env vars are validated in `src/env.ts`; add a new one there.
- Semantic Tailwind tokens from the shared theme, never hex colours.

## When you change it

Update the matching page under `internal-docs/frontend/` in the same commit. `pnpm --filter @acme/nextjs test` and `pnpm --filter @acme/nextjs typecheck`.
