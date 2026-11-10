# API Contract

HTTP contract rules: routes, envelope, status codes, pagination, validation errors, centralized error handling.

## 1. Route design

- **RESTful only.** Nouns in plural, kebab-free lowercase; no verb-phrases in paths (no `/create-account`). Actions beyond CRUD belong to a resource or a separate skill, they are not hacked as verb endpoints.
- Versioned mount: `/api/v1/<resource>` in `server.ts`, importing the router from `modules/<resource>/index.js`.
- One module per domain; its `budget.routes.ts` wires `export const budgetRouter = Router();`.
- **Nested resources live in the parent router** (`budget.routes.ts` wires `/:id/expenses` with `ExpenseController`) — never create a mounted child router for a nested resource.
- Cross-cutting middleware at router level with `router.use(...)`; rate limiters where the router warrants it.
- Dynamic params validated via `router.param()`:

```ts
budgetRouter.param("id", validateRequestParams(budgetIdSchema));

budgetRouter.get("/", BudgetController.getAllBudgets);
budgetRouter.post("/", validateRequestBody(budgetSchema), BudgetController.createBudget);
budgetRouter.get("/:id", BudgetController.getBudgetById);
budgetRouter.put("/:id", validateRequestBody(budgetUpdateSchema), BudgetController.updateBudgetById);
budgetRouter.delete("/:id", BudgetController.deleteBudgetById);
```

**One update verb: PUT, carrying the module's `updateSchema`.** The update schema is not the create schema — it is the *edited-fields* contract, derived from it with the transforms that encode the resource's business rules: `.omit()` the non-editable fields (natural keys like `sku`, stock counters), `.extend()` relation fields as `.nullable()` (sending `null` detaches the relation), then `.partial()` and a final `.refine()` demanding at least one field. There is no PATCH route; partial editing lives in this schema:

```ts
// sku and stock quantity are never editable through the update endpoint.
// categoryId/supplierId accept null on update to detach the relation.
export const productUpdateSchema = productSchema
  .extend({
    categoryId: productSchema.shape.categoryId.nullable(),
    supplierId: productSchema.shape.supplierId.nullable(),
  })
  .omit({ sku: true })
  .partial()
  .refine((data) => Object.keys(data).length > 0, "At least one field is required");
```

**Middleware order per route** (fixed): param validators → auth guard (`authenticate` / `optionalAuthenticate` + `authorize(...roles)` — **[auth.md](./auth.md)**) → `validateRequestBody(schema)` → controller. Validation middleware replaces `req.body` with the parsed data before the controller runs; param validation validates but does not attach, so controllers convert the validated param per the profile's `idType` (conventions.md §2).

## 2. Response envelope

### Success

Every successful response is `{ message: string, data: T | null }`:

| Verb | Status | Body |
|---|---|---|
| GET (list) | 200 | `{ message: "Budgets retrieved successfully", data: { items, page, pageSize, total, totalPages } }` |
| GET (single) | 200 | `{ message: "Budget retrieved successfully", data: { ... } }` |
| POST | 201 | `{ message: "Budget created successfully", data: { ... } }` |
| PUT | 200 | `{ message: "... updated successfully", data: { ...updated } }` |
| DELETE | 200 | `{ message: "Budget deleted successfully", data: null }` |

Success rules:

- `message` is **always present and in English** ("Budget created successfully" — never "Producto encontrado"-style leftovers). Reads carry it too; envelope uniformity beats saving ~30 bytes per response.
- `data` holds the resource; `null` only for DELETE. No bare objects, no ad-hoc envelopes.
- Lists are **always paginated** (see §3) — never return a raw array in `data`, and pagination meta lives **inside `data`** (no top-level `meta` key).
- Returns strip sensitive fields (password, tokens, secrets) via destructuring on the object placed in `data`.
- **Serializable shapes**: response data must be JSON-serializable. `BigInt` values (event/audit-style IDs) are converted to strings **once, in the model**; `JsonB` travels as-is; `Timestamptz` serializes as ISO-8601 via `JSON.stringify`. No per-endpoint ad-hoc transforms.
- **Binary exception**: file-download responses (Excel/PDF export) are the only envelope exception — binary stream + `Content-Disposition`; errors on those routes still follow §Error.

### Errors

Every error body is `{ message: string, code: string, data: null }`:

| Status | Body | Produced by |
|---|---|---|
| 401 / 403 / 404 / 409 / 400 (business) | `{ message, code, data: null }` | `ApiError` factories → `errorHandler` |
| 400 (validation) | `{ message: "Validation failed", code: "VALIDATION_ERROR", data: null, errors: [{ field, message }] }` | validation middlewares (§5) |
| 500 | `{ message: "Internal server error", code: "INTERNAL_SERVER_ERROR", data: null }` | `errorHandler` fallback |

Error rules:

- The HTTP status travels **only** in the status line — never duplicate `status` or a `success` boolean in the body; clients branch on the status line and on `code`.
- `code` (machine-readable, `UPPER_SNAKE_CASE`) is **always present on errors**: `ApiError` factories assign their default, the constructor falls back to a `statusCode → code` map, and the unmatched error is always `INTERNAL_SERVER_ERROR`.
- `data` is `null` on **every** error — it is reserved for resources. Field-level detail travels in the dedicated `errors` key (§5), never inside `data` or serialized into `message`.
- DELETE returns `200` with the envelope — not `204` — so DELETE keeps the same shape as every other response.
- Client-facing errors are **generic and user-facing**: internals (stack traces, ORM codes, table/constraint names, schemas) never leave the server and live only in server-side logs (§6).
- This envelope is a simplified profile of RFC 9457 problem details (`title` ↔ `message`, human explanation ↔ `message`, field extensions ↔ `errors`). Adopt `application/problem+json` only if the API becomes public or embeddable. `requestId` correlation is deferred to the logging skill.

### Route-level errors — the two clients always hit

The routers' happy paths never produce these, but every client does:

- **Unknown route** — the catch-all in `server.ts` (conventions.md §9) answers the plain error envelope: status `404`, body `{ message: "Route not found", code: "ROUTE_NOT_FOUND", data: null }`. Express's default HTML 404 never reaches a client.
- **Malformed JSON body** — an `express.json()` parse failure is translated right after the app boundary (a dedicated error-handling middleware in `server.ts`, conventions.md §9) into the validation envelope: status `400`, body `{ message: "Malformed JSON body", code: "VALIDATION_ERROR", data: null, errors: [{ field: "body", message: "Malformed JSON" }] }`. A broken body is client input, never a `500`.

## 3. Pagination

List endpoints paginate via the shared schema `shared/schemas/paginationSchema.ts`:

```ts
export const paginationSchema = z.object({
  page: z.coerce.number().int("Invalid page").positive("Invalid page").default(1),
  pageSize: z.coerce.number().int("Invalid page size").positive("Invalid page size").max(100, "Page size must be at most 100").default(10),
});
```

- Query params: `page` (default 1), `pageSize` (default 10, max 100).
- Apply per router with `router.use(validateRequestQuery(paginationSchema))`, or extend it for domain filters (`productQuerySchema = paginationSchema.extend({ ... })`).
- The controller computes the meta through a module-level helper and returns `data: { items, ...buildMeta(page, pageSize, total) }` — one `buildMeta` per module keeps every list identical:

```ts
const buildMeta = (page: number, pageSize: number, total: number) => ({
  page,
  pageSize,
  total,
  totalPages: Math.ceil(total / pageSize),
});
```

- Count and page read run in one `prisma.$transaction([...])` inside the model, always with an explicit `orderBy` (e.g. `{ id: "asc" }`) so pages are deterministic.

## 4. Status codes

Allowed: `200`, `201`, `400`, `401`, `403`, `404`, `409`, `429`, `500`.

Semantics: missing entity → `404` (including "exists but not yours" for resource objects); authenticated but not authorized → `403`; bad credentials/token → `401`; duplicate/conflict → `409`; schema/param validation failure → `400`; rate limit exhausted → `429`; unexpected server failure → `500`.

The `429` body is the plain error envelope with a fixed code:

```json
{ "message": "Too many requests", "code": "RATE_LIMITED", "data": null }
```

The limiter (auth router per auth.md) adds `Retry-After: <seconds>` when it knows the window reset.

## 5. Validation errors (Zod)

Body, param and query validation failures share one shape — status `400`, code `VALIDATION_ERROR`:

```json
{
  "message": "Validation failed",
  "code": "VALIDATION_ERROR",
  "data": null,
  "errors": [
    { "field": "email", "message": "Invalid email" },
    { "field": "amount", "message": "Amount must be positive" }
  ]
}
```

- Each `errors` entry is `{ field, message }`: a human-readable message **about the client's own input** — never a server internal.
- Field errors are built once from `z.flattenError` in `shared/middleware/validate.ts` and packed into `ApiError.validation(fieldErrors)`; never `JSON.stringify` them into `message`.
- The rest of the envelope is unchanged: `data` stays `null` so client parsing is uniform across every endpoint.

Validation middlewares (in `shared/middleware/validate.ts`, factory style):

```ts
// Zod 4: generic constraints extend z.ZodType (not the Zod 3 z.ZodTypeAny).
export const validateRequestBody = <T extends z.ZodType>(schema: T) =>
  (req, res, next) => { ... safeParse(req.body) → ApiError.validation(...) or req.body = result.data; next(); };

export const validateRequestParams = <T extends z.ZodType>(schema: T) =>
  (req, res, next) => { ... safeParse(req.params) → ApiError.validation(...) or next(); };

export const validateRequestQuery = <T extends z.ZodType>(schema: T) =>
  (req, res, next) => { ... safeParse(req.query) → ApiError.validation(...) or req.validatedQuery = result.data; next(); };
```

No `console.log` debugging inside shipped middleware.

## 6. Centralized error handling

**`src/shared/utils/ApiError.ts`** — one class, static factory helpers, machine-readable `code`:

```ts
export type FieldError = { field: string; message: string };

/** Machine-readable code for every HTTP status the API can produce. */
const DEFAULT_STATUS_CODES: Record<number, string> = {
  400: "BAD_REQUEST",
  401: "UNAUTHORIZED",
  403: "FORBIDDEN",
  404: "NOT_FOUND",
  409: "CONFLICT",
  429: "RATE_LIMITED",
  500: "INTERNAL_SERVER_ERROR",
};

export class ApiError extends Error {
  statusCode: number;
  code: string;
  fieldErrors: FieldError[] | null;

  constructor(statusCode: number, message: string, code?: string, fieldErrors: FieldError[] | null = null) {
    super(message);
    this.statusCode = statusCode;
    this.code = code ?? DEFAULT_STATUS_CODES[statusCode] ?? "INTERNAL_SERVER_ERROR";
    this.fieldErrors = fieldErrors;
  }

  static validation(fieldErrors: FieldError[]) {
    return new ApiError(400, "Validation failed", "VALIDATION_ERROR", fieldErrors);
  }

  static unauthorized(message = "Authorization denied") { return new ApiError(401, message); }
  static forbidden(message = "Access denied") { return new ApiError(403, message); }
  static notFound(message = "Resource not found") { return new ApiError(404, message); }
  static conflict(message: string) { return new ApiError(409, message); }
  static badRequest(message: string) { return new ApiError(400, message); }
  static tooManyRequests(message = "Too many requests") { return new ApiError(429, message); }
}
```

**`src/shared/utils/prismaError.ts`** — the **ORM-error seam**: the one file that knows provider error codes and translates them to `ApiError`. Signature: `mapPrismaError(error, duplicateMessages, notFoundMessage): never` where `duplicateMessages` maps constraint names to messages — resolved via `P2002.meta.target` (tables with several unique constraints — especially partial ones — need per-constraint messages; single-constraint tables pass `{ default: "..." }`). P2002 → `ApiError.conflict(matched message)`, P2025 → `ApiError.notFound(notFoundMessage)`, P2003 → `ApiError.conflict("Operation violates a data relation")`, anything else re-thrown untouched. It is **called from the models' catch blocks**, not from the `errorHandler`. Controllers never inspect ORM internals.

**`src/shared/middleware/errorHandler.ts`** — mounted **last** in `server.ts`:

```ts
import type { Request, Response, NextFunction } from "express";
import { ApiError } from "../utils/ApiError.js";

export const errorHandler = (err: unknown, req: Request, res: Response, next: NextFunction) => {
  if (err instanceof ApiError) {
    return res.status(err.statusCode).json({
      message: err.message,
      code: err.code,
      data: null,
      ...(err.fieldErrors ? { errors: err.fieldErrors } : {}),
    });
  }
  // Client-facing errors stay generic and user-facing; specific detail (stack
  // traces, ORM internals) lives only in server-side logs.
  console.error(err);
  return res.status(500).json({
    message: "Internal server error",
    code: "INTERNAL_SERVER_ERROR",
    data: null,
  });
};
```

- Controllers **throw** `ApiError` or let Prisma rejections bubble; no try/catch in controllers (Express 5 forwards async rejections).
- Every controller response path is an early `return res.status(...).json(...)`; unreachable code after a return is a lint-worthy smell.
- **Client-facing errors stay generic; specific detail stays internal.** Responses carry only user-facing English messages; stack traces and ORM internals go only to server-side logs (`console.error` for now — structured logging and `requestId` correlation are deferred to the logging skill).
- Delete the legacy pattern of per-controller `try { ... } catch { res.status(500).json({ message: "..." }) }`.

## 7. Logic ownership

| Concern | Lives in |
|---|---|
| Parse/validate shape (body, params) | module `schema.ts` + `validateRequestBody`/`validateRequestParams` |
| Who owns what (DB filter) | Model (`where` clauses) |
| Editable fields & relation detach on update | module `updateSchema` (`.omit()`, `.nullable()`) |
| Relation payload mapping (`connect`/`disconnect`) | Model only — controllers send plain values |
| Procedural logic (algorithms, state machines, cascades) | module `service.ts` — optional, conventions.md §5.1; the transactional boundary stays in the model |
| Business rules of the domain | Model + controller code path; never in the router |
| Provider error → HTTP error | `shared/utils/prismaError.ts` (the ORM-error seam) |
| Cross-module reads | The other module's public API (`index.ts`) — never its internal files |

## 8. Soft delete (when the grill activates it)

When the project profile or the grill's decision #7 picks soft delete (a `deletedAt`-style column):

- Every read `where` filters the tombstone column (`deletedAt: null`) — built inside the model, never per-endpoint.
- A soft-deleted resource answers `404` like a missing one; its data never leaks through lists, counts or relation includes.
- Uniqueness across tombstones is decided once per project: partial unique indexes (tombstone excluded) or app-level checks in the model — documented in the schema.
- Restore travels through the module's `updateSchema` only if the grill's decision #7 said so; otherwise restoration is out of scope.

## 9. CORS

- The `cors` middleware mounts **once, at app level** (position in conventions.md §9). `origin` is a **whitelist read from env**: `CORS_ORIGINS` (comma-separated) — empty means the API serves same-origin clients only, no `Access-Control-Allow-Origin` header.
- `credentials: true` is part of the standard as soon as the auth module exists — the refresh cookie must travel with browser requests. With `credentials`, the origin is **never** `*`: the exact whitelisted origin is echoed, per the `cors` package's behavior when given an array.
- Preflight (`OPTIONS`) is owned by the `cors` package; routers never handle it, and routes never read the `Origin` header themselves.
