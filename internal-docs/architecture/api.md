# API architecture

`apps/api` is a NestJS 12 application compiled to CommonJS. Nest 12 ships its packages as ESM; the app loads them through Node's `require(esm)`, which is why `tsconfig.json` uses `module: node20` and Node 22.12+ is the floor (`.nvmrc` pins the current LTS).

## Shape

- `src/main.ts` boots the app: CORS for `FRONTEND_URL`, the global `HttpExceptionFilter`, a whitelisting `ValidationPipe` (`forbidNonWhitelisted`, so unknown body fields are a 400), the `/api` prefix and Swagger at `/api/docs`.
- `src/app.module.ts` wires `ConfigModule` (global, reads the root `.env`, validated by `src/config/env.validation.ts`), Mongoose and the feature modules, and registers the global guards (see [auth.md](auth.md)).
- One folder per feature (`auth/`, `users/`): module, controller, service, `dto/` with class-validator decorators, `schemas/` for Mongoose.
- `src/common/filters/http-exception.filter.ts` gives every error the same JSON shape and logs it.

## Config

`validateEnv` runs when `AppModule` is imported and throws on an invalid environment, so a misconfigured API never starts. Today it requires `MONGODB_URI` (a `mongodb://` or `mongodb+srv://` URI) and `JWT_SECRET` (32+ characters, not the `.env.example` placeholder). Read config through `ConfigService.getOrThrow`, never with a fallback default. Add a variable: validate it there, add it to `.env.example`, document it here.

## Testing

Vitest with `unplugin-swc` (esbuild drops the decorator metadata Nest's DI needs). Specs sit next to the code as `*.spec.ts`; `*.e2e.spec.ts` boot the real `AppModule` against an in-memory MongoDB through `src/testing/test-app.ts`, with the same pipes, filter and prefix as `main.ts`.

- `pnpm --filter @acme/api test`: every spec.
- `pnpm --filter @acme/api test:e2e`: the e2e specs (the lifecycle suite the PR gate asks for when auth or users change).
- `pnpm --filter @acme/api boot:check`: starts the built `dist/main.js` against an in-memory MongoDB and waits for Nest's success line. Typecheck, build and tests each resolve modules their own way; only this proves the compiled app starts.
