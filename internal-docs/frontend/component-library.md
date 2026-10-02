# Component library (@acme/ui)

shadcn/ui components on Radix and Tailwind, exported from `packages/ui/src/index.ts`.

| Export                                                                            | File                           |
| --------------------------------------------------------------------------------- | ------------------------------ |
| `Button`, `buttonVariants`                                                        | `src/components/ui/button.tsx` |
| `Card`, `CardHeader`, `CardTitle`, `CardDescription`, `CardContent`, `CardFooter` | `src/components/ui/card.tsx`   |
| `cn`                                                                              | `src/lib/utils.ts`             |

## Adding a component

`pnpm ui-add <name>` runs the shadcn CLI in `packages/ui`; it writes the component and installs its Radix dependency. Export it from `src/index.ts` and add a row here in the same commit (the docs gate wants a page under `internal-docs/frontend/` for any `packages/ui/src` change). If the package gains subpath exports, `ui-inventory-drift.sh` checks each is listed on this page.
