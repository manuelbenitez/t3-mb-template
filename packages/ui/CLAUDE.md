# packages/ui: @acme/ui component library

The shared component library. Inventory and rules: [`internal-docs/frontend/component-library.md`](../../internal-docs/frontend/component-library.md).

## Rules

1. Only generic, reused primitives here; a feature-specific widget belongs in the app.
2. Check the inventory before adding one; extend an existing component rather than forking a near-duplicate.
3. Variants use CVA, styled with semantic Tailwind tokens and composed with `cn()`.
4. Add shadcn components with `pnpm ui-add <name>`, then export them from `src/index.ts`.

## When you change it

Update `component-library.md` in the same commit (the docs gate blocks a `packages/ui/src` change without a page under `internal-docs/frontend/`).
