# New Resource Checklist

Two phases, always in order: the **Decision grill** (phase 0) and the **build
checklist** (phase 1). No code — not even the Zod schema — exists until the
grill is answered.

> Assumed: `prisma/schema.prisma`, the recorded **project profile** (SKILL.md) and the
> shared infrastructure (`config/` or the profile `dbSeam`, `src/shared/`) already exist.
> If they don't, run [bootstrap.md](./bootstrap.md) first — creating a module in a project
> without its seams produces improvised infrastructure, which is exactly what this
> standard forbids.

## Phase 0 — Decision grill (ask the user, wait for the answers)

First **read `prisma/schema.prisma`** for the resource: fields, IDs, unique
constraints, relations, cascade. *The API adapts to the model* — this checklist
never invents a table. From that read fill the inferred-default column, then ask
the user **all seven questions** and wait for confirmation:

| # | Decision | Drives in the generated code | Default (inferred from the model) |
|---|---|---|---|
| 1 | **Ownership** — does the resource belong to a user? | Ownership filter (`where`) in the model; "exists but not yours" → 404 | A `userId`/owner FK in the model → yes |
| 2 | **Unique business key** — what counts as a duplicate? | `P2002` → `409 Conflict` message via `mapPrismaError` | The model's `@unique` field |
| 3 | **Sensitive fields** — what never leaves the server? | Destructure-and-strip before placing the object in `data` | `password`, `token`, `secret*` by name |
| 4 | **Operations** — full CRUD or read-only? what is editable? | Which routes exist; non-editable fields `.omit()`-ed from the `updateSchema` | Full CRUD; nothing extra omitted |
| 5 | **Nesting** — root resource or child of another? | Root: `app.use("/api/v1/<resources>", router)` in `server.ts`. Child: wired in the **parent's** router (`/:id/<children>`) | It has a required parent relation → nested |
| 6 | **List filters** — search, ranges, sorting beyond page/pageSize? | `<domain>QuerySchema = paginationSchema.extend({ ... })` + the `where` built in the model | Pagination only |
| 7 | **Deletion** — hard or soft? guarded by history? | Model `delete()`; guarded → business rule throwing `ApiError.conflict` | Hard delete |

Record each answer (a plain "confirmed" over the inferred defaults is enough)
and keep it at hand — **every answer must be visible in the finished code**, and
the final self-check verifies it.

## Phase 1 — Build the module `src/modules/<domain>/`

### 1.0 Decide the layering

Pure CRUD → four files (`routes`, `schema`, `controller`, `model`). Procedural
logic — pure algorithms, state machines, multi-model cascades — → add
`<domain>.service.ts` (conventions.md §5.1: the decision algorithm and a full
example live there) and name the single transactional model method it will
feed. Default `serviceLayer: on-demand`: a pass-through service is forbidden,
CRUD never gets one.

### 1.1 Zod schema — `wallet.schema.ts`

```ts
import z from "zod";
import { paginationSchema } from "../../shared/schemas/paginationSchema.js";

export const walletSchema = z.object({ ... });  // create payload

export const walletIdSchema = z.object({ id: z.uuid("Invalid ID") });  // profile idType = uuid

// Editable-fields contract — derive it exactly as api-contract.md §1 specifies:
// .omit() non-editables · .extend() relation fields as .nullable() (detach) ·
// .partial() · .refine() at least one field. Single PUT carries this schema.
export const walletUpdateSchema = walletSchema
  .extend({ categoryId: walletSchema.shape.categoryId.nullable() })
  .omit({ createdAt: true })
  .partial()
  .refine((data) => Object.keys(data).length > 0, "At least one field is required");

export const walletQuerySchema = paginationSchema.extend({ ... });  // decision #6 (omit if none)

export type WalletQuery = z.infer<typeof walletQuerySchema>;
```

- IDs follow the project profile's `idType` (SKILL.md): `uuid` → `z.uuid()`
  (the example; the validated param stays a string), `int` → `z.coerce.number().int()`
  (controller converts with `Number(req.params.id)`). Read the model, never assume.
- Derive with `.pick()` / `.omit()` / `.extend()` instead of re-declaring shared
  fields (the derivation formula is api-contract.md §1's — that section owns it).
  English error messages; parameter names match route params (`:id` → `id`).

### 1.2 Model class — `wallet.model.ts`

```ts
import { prisma } from "../../config/db.js";
import type { Prisma } from "../../generated/prisma/client.js";
import type { WalletInput } from "./wallet.schema.js";

const listInclude = { ... } satisfies Prisma.WalletInclude;  // read shape, typed here

export class WalletModel {
  static async getAll(query: { page: number; pageSize: number }) {
    const { page, pageSize } = query;
    const [items, total] = await prisma.$transaction([
      prisma.wallet.findMany({
        include: listInclude,
        orderBy: { id: "asc" },          // deterministic pagination (api-contract.md §3)
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      prisma.wallet.count(),
    ]);
    return { items, total };
  }
  static async getById(id: string) { ... }
  static async create(data: WalletInput) { ... }
  static async update(id: string, data: Partial<WalletInput>) { ... }
  static async delete(id: string) { ... }
}
```

- Inputs are **domain types** (`z.infer`); the ORM mapping happens here:
  `categoryId: 3` from the controller becomes `category: { connect: { id: 3 } }`,
  `null` on update becomes `{ disconnect: true }`. Controllers send plain data.
- Duplicate/not-found → `mapPrismaError(...)` from the model's try/catch
  (signature and per-constraint messages: api-contract.md §6).
- Business-rule guards (decision #7) throw `ApiError.conflict` before touching
  the ORM. Ownership filters (decision #1) live in the `where`, here.
- Every `findMany` carries an explicit `orderBy`; count + page read in one
  `$transaction` (api-contract.md §3).
- When the module has a service (§1.0), the orchestration's persistence goes
  through ONE transactional model method that receives the computed payload and
  persists it atomically — the service never imports the ORM (conventions.md §5.1).

### 1.3 Controller — `wallet.controller.ts`

```ts
export class WalletController {
  static async getWalletById(req: Request, res: Response) {
    const wallet = await WalletModel.getById(req.params.id);
    if (!wallet) throw ApiError.notFound("Wallet not found");
    return res.status(200).json({ message: "Wallet retrieved successfully", data: wallet });
  }

  static async createWallet(req: Request, res: Response) {
    const wallet = await WalletModel.create(req.body);
    return res.status(201).json({ message: "Wallet created successfully", data: wallet });
  }
}
```

- Every response path is an early `return res.status(...).json(...)` with the
  envelope `{ message, data }`; sensitive fields (decision #3) stripped.
- Lists return `data: { items, ...buildMeta(page, pageSize, total) }` — `buildMeta`
  is the module-level helper specified in api-contract.md §3 (one per module;
  the contract owns its shape).
- With profile `idType = uuid` the validated param passes through unchanged;
  `int` → `Number(req.params.id)` (conventions.md §2).
- No try/catch, no `next(error)`; errors are `ApiError` thrown verbatim or bubbled
  (api-contract.md §6).

### 1.4 Router — `wallet.routes.ts`

```ts
import { Router } from "express";
import { validateRequestBody, validateRequestParams, validateRequestQuery } from "../../shared/middleware/validate.js";
import { WalletController } from "./wallet.controller.js";
import { walletSchema, walletUpdateSchema, walletIdSchema, walletQuerySchema } from "./wallet.schema.js";

export const walletRouter = Router();

walletRouter.param("id", validateRequestParams(walletIdSchema));
walletRouter.use(validateRequestQuery(walletQuerySchema));  // pagination + decision #6 filters

walletRouter.get("/", WalletController.getAllWallets);
walletRouter.post("/", validateRequestBody(walletSchema), WalletController.createWallet);
walletRouter.get("/:id", WalletController.getWalletById);
walletRouter.put("/:id", validateRequestBody(walletUpdateSchema), WalletController.updateWalletById);
walletRouter.delete("/:id", WalletController.deleteWalletById);
```

- The middleware order per route (param validators → auth guard →
  `validateRequestBody` → controller) is api-contract.md §1's — the auth
  middlewares come from [auth.md](./auth.md).
- Decision #5 nested child: `walletRouter.get("/:id/entries", EntryController...)`
  is wired **here**, in the parent router — never a mounted child router. The
  parent may import the child module's model through its public API
  (`../entry/index.js`) with a why-comment.

### 1.5 Public API — `index.ts`

```ts
export { walletRouter } from "./wallet.routes.js";
```

- This file is the **only** thing other modules import. Re-export the model only
  when another module genuinely needs it.

## 2. Mount — `src/server.ts`

```ts
import { walletRouter } from "./modules/wallet/index.js";

app.use("/api/v1/wallets", walletRouter);
// ...all other module routers...
app.use(errorHandler);   // always last (full order: conventions.md §9)
```

All controllers rely on the single global error handler — verify it is still
mounted last.

## Final self-check — run it, don't eyeball it

- [ ] Phase 0: all 7 decisions answered; **each one visible in the code**
      (ownership `where`, 409 message, stripped fields, `omit`-ed fields,
      nesting, query filters, deletion guard)
- [ ] If the model changed: migration ran with a theme-named name (repo
      convention decides naming). If the table already existed with its own
      migration: skip — never re-migrate an existing table, never `db push`.
- [ ] Profile decisions (`idType`, `dbSeam`, service layering) visible in the
      code: schema ID validators, param handling, and (when applicable) the
      service→transactional-model handoff
- [ ] `pnpm typecheck && pnpm lint` clean — the vertical slice exit criterion,
      not a formality
- [ ] One real request per operation exercised (curl/REST client, or the
      harness — testing.md): envelope `{ message, data }` on every success;
      pagination meta inside `data`; a forced duplicate answers `409` with the
      decision #2 message
- [ ] No try/catch in controllers; errors via `ApiError` or bubbling to
      `errorHandler`
- [ ] Zero ORM imports outside the seams (the profile `dbSeam`, `*.model.ts`,
      `prismaError.ts`); controllers carry no ORM payloads
- [ ] No `process.env` reads outside `config/`; no new `declare global` blocks —
      `shared/types/express.d.ts` only
- [ ] Correct spellings (`schemas`, `createdAt`), English messages and
      why-comments
