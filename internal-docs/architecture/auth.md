# Auth

JWT bearer auth, fail-closed by default.

## Endpoints

| Route                     | Access  | Returns                                                      |
| ------------------------- | ------- | ------------------------------------------------------------ |
| `POST /api/auth/register` | public  | `{ access_token, user }`; new accounts get `roles: ["user"]` |
| `POST /api/auth/login`    | public  | `{ access_token, user }`; 401 on a wrong email or password   |
| `GET /api/auth/session`   | token   | `{ user }`                                                   |
| `GET /api/users/me`       | token   | the current user                                             |
| `GET /api/users`          | `admin` | every user (`?role=` filters)                                |

Passwords are bcrypt-hashed (10 rounds) and stripped from every JSON response by the schema's `toJSON` transform. Tokens carry `{ sub, email }` and expire after 7 days; there is no refresh token.

## Guards

Two guards are registered globally in `app.module.ts` (`APP_GUARD`), in this order:

1. **`JwtAuthGuard`** (`auth/guards/jwt-auth.guard.ts`): every route needs a valid bearer token. `@Public()` on a handler or a whole controller opts out (`reflector.getAllAndOverride` reads both).
2. **`RolesGuard`** (`auth/guards/roles.guard.ts`): a route with `@Roles(...)` needs the user to hold one of them; 403 otherwise.

`JwtStrategy.validate` reloads the user on every request: a deleted user is a 401, an account whose `accountStatus` is not `active` is a 403 even with a valid token.

## Roles

`ROLES` in `users/schemas/user.schema.ts` is the one list (`user`, `admin`). Roles are assigned server-side only: `CreateUserDto` has no `roles` field and the validation pipe rejects unknown fields, so a register call cannot grant one. Extend `ROLES` for your domain; `@Roles()` and the guard pick it up.

## The secret

`JWT_SECRET` is read with `getOrThrow`; there is no fallback. Boot fails unless it is 32+ characters and not the `.env.example` placeholder (`config/env.validation.ts`). Generate one with `openssl rand -base64 32`; `setup.sh` does it for you and writes it only to `.env`.

## Tests

`auth/auth.e2e.spec.ts` (register, login, session, default-deny, admin-only list, suspended account, role injection), `auth/guards/guards.spec.ts` (class- and handler-level `@Public()`, roles), `config/env.validation.spec.ts`.
