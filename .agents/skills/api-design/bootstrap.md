# Bootstrap Checklist

Ordered build for a fresh API project: assemble the shared infrastructure (the
seams) **before any resource module exists** — a module without its seams gets
improvised, and improvised infrastructure is what this standard exists to
prevent. Each step cites the section that specifies it; those specs are the
single source of truth — this file is only the **order** and the exit checks.

## 0. Stack prerequisites — skip if already present

- Dependencies installed, pinned to this standard's majors: `express@5`,
  `cors`, `zod@4`, `@prisma/client@7` + `@prisma/adapter-pg@7` (runtime), plus
  `cookie-parser` if the auth module is planned from the start (auth.md),
  TypeScript strict ESM (`"type": "module"`, `.js` import suffixes). Verify
  current versions with context7 before installing.
- **The project profile is recorded.** Read the repo `AGENTS.md`: it must
  contain the `idType` / `dbSeam` / `serviceLayer` table (SKILL.md). If it
  doesn't, stop and record it **with the user** before writing any code —
  modules derive from the profile, they never re-decide it.
- Scripts: `dev` (`tsx watch`), `build`, `lint`, `typecheck`, and `test`
  (`vitest run` — the only runner, testing.md).
- `prisma/schema.prisma` at the project root with the `prisma-client` generator
  outputting to `src/generated/prisma`, and a schema **drafted with the user** —
  this skill reads the model, it never designs it. If no model exists yet,
  stop and ask before continuing. Run `npx prisma generate` so
  `src/generated/` exists.

## 1. `config/env.ts` — the env seam (conventions.md §8)

Env read once, validated with Zod, fail fast at boot. Minimum shape:
`DATABASE_URL`, `PORT` (coerced + default), `NODE_ENV` enum, and
`CORS_ORIGINS` (comma-separated whitelist, default empty; api-contract.md §9);
`import "dotenv/config";` on the first line. Nothing else reads `process.env`.
The auth module adds its own variables here when it lands (auth.md).

## 2. The data seam (profile `dbSeam`) — conventions.md §8

Build the `PrismaClient` over the `PrismaPg` adapter using `env.DATABASE_URL`;
export the `prisma` singleton and `connectDB()` (proves the connection with a
`SELECT 1`). Default path `config/db.ts`; if the client already lives elsewhere
(e.g. `lib/prisma.ts`), adopt that path as the profile's `dbSeam` — consume
`env` there and add `connectDB()`, never relocate existing code. This file is
the project's only client constructor.

## 3. `shared/utils/ApiError.ts` (api-contract.md §6)

Copy the class **as specified there** — `fieldErrors`, the
`DEFAULT_STATUS_CODES` map including `429: "RATE_LIMITED"`, and the
`validation` / `badRequest` / `unauthorized` / `forbidden` / `notFound` /
`conflict` / `tooManyRequests` factories. Do not "improve" the shape mid-build.

## 4. `shared/utils/prismaError.ts` — the ORM-error seam (api-contract.md §6)

`mapPrismaError(error, duplicateMessages, notFoundMessage): never` — P2002 →
conflict via the `duplicateMessages` map (`P2002.meta.target` lookup; a table
with several unique constraints gets per-constraint messages, single-constraint
tables pass `{ default: "..." }`), P2025 → notFound, P2003 → conflict
(relation), anything else rethrown untouched.

## 5. `shared/middleware/validate.ts` (api-contract.md §5)

Three factory middlewares over `schema.safeParse`:
`validateRequestBody` (replaces `req.body`, 400 on failure),
`validateRequestParams` (validate-only), `validateRequestQuery` (attaches
`req.validatedQuery`). Field errors built once via `formatFieldErrors` +
`z.flattenError` → `ApiError.validation`. No `console.log` debugging.

## 6. `shared/schemas/paginationSchema.ts` (api-contract.md §3)

Shared `page`/`pageSize` schema (defaults 1/10, max 100) + exported
`PaginationQuery`. Every list endpoint reuses it — `extend`, never re-declare.

## 7. `shared/types/express.d.ts` (conventions.md §6)

The project's single `declare global`: `validatedQuery?: Record<string,
unknown>` today; `req.user` arrives with the auth module (auth.md) — adding
new fields happens only here.

## 8. `shared/middleware/errorHandler.ts` (api-contract.md §6)

Will be mounted **last** in `server.ts`. `ApiError` → its status/body with the
optional `errors` array; anything else → `console.error` + generic
`INTERNAL_SERVER_ERROR`.

## 9. App shell (conventions.md §9)

`server.ts` and `index.ts` follow conventions.md §9 exactly — that section is
the single source for the shape, including the middleware order
(`express.json()` → malformed-JSON translator → `cors` → `cookieParser` →
routers → **catch-all 404** → `errorHandler` last), `app` + `startServer()`
exports, the boot-log line format, and the graceful shutdown. Build it from
there, not from memory.

## Final self-check — execute, don't eyeball

- [ ] `pnpm typecheck && pnpm lint` clean
- [ ] Boot with a corrupted env (empty `DATABASE_URL`) fails fast with the Zod
      message — not a hanging server
- [ ] Server boots and prints the exact boot-log line of conventions.md §9
- [ ] A forced validation failure (bad body on any test route) answers `400`
      with `{ message, code: "VALIDATION_ERROR", data: null,
      errors: [{ field, message }] }`
- [ ] `GET /api/v1/does-not-exist` answers `404` with
      `{ message, code: "ROUTE_NOT_FOUND", data: null }` — never HTML
- [ ] A malformed JSON body answers `400 VALIDATION_ERROR` with
      `errors: [{ field: "body", message: "Malformed JSON" }]` — never `500`
- [ ] Zero ORM imports outside the three seams (the profile `dbSeam`,
      `*.model.ts`, `prismaError.ts`)

When everything passes, continue with [new-resource.md](./new-resource.md) —
phase 0 grill first.
