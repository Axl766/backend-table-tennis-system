---
name: api-design
description: >-
  API standard for Express 5 + TypeScript (ESM) + Prisma 7/PostgreSQL + Zod 4,
  distilled from the reference codebase. Use when creating a new API project
  from scratch, adding resources, endpoints, auth or tests to it, changing
  existing API code, designing response, pagination or error contracts, or
  swapping the ORM behind the models. Covers the workflow (bootstrap the
  seams, grill each resource's decisions, build the vertical slice), the
  module architecture, the HTTP contract, auth (JWT + refresh cookie +
  roles), and testing (vitest over the plain-HTTP harness). Out of scope:
  database schema design, WebSockets/SSE.
---

# API Design Standard

Reusable standard for REST APIs in this stack, distilled from the author's reference
codebase. The generated code must read like home — these patterns are how the
author actually writes and understands backend code at a glance:

- **Express 5**, TypeScript strict, ESM (`"type": "module"`, `.js` import suffixes, `import type`)
- **PostgreSQL** via **Prisma 7** — the ORM is confined to the seams (the data seam per profile, each `*.model.ts`, `shared/utils/prismaError.ts`) so it stays swappable (adopt a new major, e.g. Prisma 8, once stable)
- **Zod 4** for all validation (modern API: `z.email()`, `z.coerce.number()`, `z.flattenError()`)

Before generating code, verify current stable versions and breaking changes with context7; this standard pins majors, never patch releases.

## Compliance — every edit, not just new code

The standard governs **all** API code: creating new code *and* changing existing
code. When an edit touches an existing surface, bring that surface into
conformance with this standard first. Deviations found but not fixed within the
edit are recorded as **debt in the file that owns the concern** (`auth.md` and
`testing.md` carry the current debt ledger) — a deviation nobody wrote down is
a bug the next session inherits. A full conformance migration is its own task,
never a silent drive-by refactor.

## Project profile — pin once per project, derive everywhere else

Before the first module, record these decisions in the project (a repo `AGENTS.md`
or equivalent). Modules **derive** from the profile; they never re-decide it.

| Decision | Options | Default (best practice) |
|---|---|---|
| `idType` | `uuid` \| `int` | **`uuid`** — non-enumerable, merge-safe, client-mintable (offline/idempotent flows). Use `int` only for small internal catalogs |
| `dbSeam` | any single path | `config/db.ts` — the project's only Prisma access point, wherever it lives |
| `serviceLayer` | `always` \| `on-demand` | **`on-demand`** — a service that only forwards to a model is forbidden (conventions.md §5.1) |

A repository's `AGENTS.md` **takes precedence** over this standard wherever the
two overlap — the standard defines the ceiling; the repo may be stricter.

## Workflow — phases in order, branches as needed

1. **Check the project state.** If the env seam, the data seam (profile `dbSeam`), `src/shared/` (middleware, schemas, utils, types) or `prisma/schema.prisma` are missing, execute **[bootstrap.md](./bootstrap.md)** first: the infrastructure is its own vertical slice — one seam at a time, self-checked, before any resource module exists.
2. **Add the resource** with **[new-resource.md](./new-resource.md)**. Its **Decision grill runs first**: the 7 domain questions (ownership, unique key, sensitive fields, operations, nesting, list filters, deletion) are answered by the user **before any code exists**. No answers → no endpoints.
3. **Auth surface** — protecting routes, designing `/auth/*` endpoints, tokens, refresh cookie, role guards, hackers rate-limited → **[auth.md](./auth.md)**.
4. **Tests** — unit or integration tests for any code in this stack (driven inside the `/tdd` loop, one red-green slice at a time) → **[testing.md](./testing.md)**.

Within the resource build, each step completes with its self-check before the next begins — a **vertical slice**, never horizontal layers.

## Absolute rules

1. **Feature modules as vertical slices.** Each domain owns its whole slice in `src/modules/<domain>/` with the flow `routes → schemas → controller → service (optional, conventions.md §5.1) → model` (the model is the only layer that touches the data seam, profile `dbSeam`). Cross-domain infrastructure lives in `src/shared/` (`middleware/`, `schemas/`, `utils/`, `types/`). Controllers carry zero ORM concepts — shaping an ORM payload is the model's job; translating HTTP is the controller's. **Modules import other modules only through their public API (`index.ts`)** — never their internal files.
2. **RESTful routes only** (verb-noun phrases are forbidden). Versioned base paths: `/api/v1/<resource>`. Updates travel through **one PUT per resource** carrying the module's `updateSchema` — this standard has no PATCH route.
3. **Uniform response envelope**: success is always `{ message, data }` (lists nest the pagination meta inside `data`); every error is `{ message, code, data: null }` — validation failures add `errors: [{ field, message }]`. The full envelope, status codes, and pagination shapes live in **api-contract.md §2–§4** — this rule points at the contract, it does not restate it.
4. **Controllers never try/catch.** They `throw` or let the ORM reject through the model; Express 5 forwards async rejections to the single global `errorHandler`. Errors are `ApiError` instances with a `statusCode` (api-contract.md §6).
5. **Env is validated once** in `config/env` with Zod; no `process.env.X!` scattered through the code (the Prisma adapter receives its URL from the config module).
6. **One style for controllers and models**: classes with `static async methodName(req: Request, res: Response)` declarations. No arrow-function properties, no default exports.
7. **Request augmentation lives centrally** in `shared/types/express.d.ts` — one `declare global` for `req.validatedQuery`, `req.user`, etc. Middleware files must not declare their own.
8. **English messages everywhere**: HTTP messages ("Budget updated successfully"), code comments, identifiers. Comments state the **why** of a non-obvious decision — never narrate the what.
9. **The ORM stays behind the seams.** Only the data seam (profile `dbSeam`), the module `*.model.ts` classes, and `shared/utils/prismaError.ts` import from the ORM or its generated client. Model methods take **domain types (`z.infer` of the module's Zod schemas)** and translate them to ORM payloads (relation `connect`/`disconnect`, typed `include`) **inside the model file** — controllers, schemas, and routes never shape ORM payloads. Swapping ORMs rewrites only those files.
10. **The API adapts to the model.** Read `prisma/schema.prisma` before deciding anything about a resource — IDs, unique constraints, relations, cascade. This standard never invents a table; schema design is out of scope.

## References (read what applies before coding)

- **[conventions.md](./conventions.md)** — folder layout (modules + shared), file/app naming, class & middleware style, Zod schema conventions, config module (`env.ts` + the `db.ts` seam), central request typing, the service layer (§5.1), the full app shape (§9).
- **[api-contract.md](./api-contract.md)** — route design (single PUT + `updateSchema`), status codes, success envelope, pagination (`buildMeta`, deterministic ordering), validation & error formats (including route-level 404 and malformed JSON), `ApiError` + provider-error mapping + `errorHandler`, CORS.
- **[new-resource.md](./new-resource.md)** — the decision grill plus the ordered checklist to add a new resource module end-to-end without missing a file.
- **[bootstrap.md](./bootstrap.md)** — ordered checklist to build the shared infrastructure of a fresh project, referencing (never duplicating) the sections above.
- **[auth.md](./auth.md)** — the auth standard: token kinds and minting, token placement (access in memory, refresh in an httpOnly cookie), the three middlewares, the auth endpoints, the rate limiter on the auth router.
- **[testing.md](./testing.md)** — the testing standard: vitest as the only runner, the two levels (unit, integration over the plain-HTTP harness), envelope-first assertions, cookie support.

## Deferred extensions (do not invent now)

- **Real-time (WebSockets / SSE)** — the REST envelope does not cover it; a separate design decides transport and resync (docs 07/08 territory).
- **File exports (Excel/PDF)** — binary responses are the single envelope exception (api-contract.md §2); the export tooling itself is separate.
- **OpenAPI / docs generation** — separate skill/convention.
- **Structured logging / `requestId` correlation** — the `errorHandler` keeps `console.error`; a logging design is a separate skill (until then, logs stay plain).
- **Database schema design** — the model is read, not written; a missing table stops the work and goes back to the user (db-design skill owns schema).
