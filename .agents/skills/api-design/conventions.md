# Code Conventions

Architecture, naming and style rules for the stack: Express 5 + TypeScript ESM + Prisma 7/PostgreSQL + Zod 4.

## 1. Folder layout

```
src/
├── config/            # env.ts (validated config), db.ts (Prisma client + connectDB)
├── modules/           # one folder per domain — the vertical slice
│   └── budget/
│       ├── budget.routes.ts      # export budgetRouter
│       ├── budget.controller.ts  # class BudgetController
│       ├── budget.model.ts       # class BudgetModel — the only layer that touches the db seam
│       ├── budget.service.ts     # OPTIONAL: procedural logic only (see §5.1)
│       ├── budget.schema.ts      # Zod schemas for the domain
│       └── index.ts              # the module's public API
├── shared/
│   ├── middleware/    # validate.ts, errorHandler.ts (cross-domain middleware)
│   ├── schemas/       # paginationSchema.ts (cross-domain schemas)
│   ├── types/         # express.d.ts — THE single Request augmentation file
│   └── utils/         # ApiError.ts, prismaError.ts (provider errors → ApiError)
├── generated/         # Prisma client output — do not edit
├── server.ts
└── index.ts
```

`prisma/schema.prisma` lives at the project root under `prisma/`.

**Module rules:**

- Module folders are **singular**; files carry the domain prefix (`budget.routes.ts`) so editor tabs and greps stay unambiguous.
- A module's `index.ts` is its **public API**: the only thing other modules may import. Never reach into another module's internal files. Re-export a model there only when another module genuinely needs it.
- `config/` and `generated/` stay top-level: the data seam (profile `dbSeam`, default `config/db.ts`) is the only Prisma access point; `generated/` is generator output.

## 2. Naming

| Thing | Rule | Example |
|---|---|---|
| Module folder | camelCase singular | `modules/budget/` |
| Route file & export | `budget.routes.ts` / `budgetRouter` | `budgetRouter` |
| Controller class & file | PascalCase singular + `Controller` | `BudgetController` / `budget.controller.ts` |
| Model class & file | PascalCase singular + `Model` | `BudgetModel` / `budget.model.ts` |
| Zod schema file | camelCase singular + `Schema` | `budget.schema.ts` (NOT "schemes") |
| Shared middleware | camelCase verb-ish, in `shared/middleware/` | `validateRequestBody`, `errorHandler` |
| Utility | camelCase per concern, in `shared/utils/` | `mapPrismaError` |
| Prisma models | **singular** with `@@map` to a snake_case table | `model Category` → `@@map("category")` |
| Primary key | Follows the project profile's `idType` (SKILL.md): `uuid` → `z.uuid()` in schemas, the validated param is already a string; `int` → `z.coerce.number().int()`, controller converts with `Number(req.params.id)`. Never mixed within a project | `idType = int`: `z.coerce.number().int()` |
| Timestamp fields | **`createdAt` / `updatedAt`** (correct spelling in new tables), mapped snake_case | `@map("created_at")` |
| API/html messages | English | "Budget deleted successfully" |

## 3. TypeScript style

- ESM project: all local imports end in `.js`; type-only imports use `import type`.
- Strict mode; avoid `!` non-null assertions except where a prior middleware guarantees the data (`req.user!.id`, `req.budget!`).
- Named exports only — no default exports.
- Comments state the **why** of a non-obvious decision ("SKU and stock quantity are never editable through the update endpoint") — the what is already readable in the code.

## 4. Controllers

One class per domain, **static async method declarations** (the one and only style):

```ts
import type { Request, Response } from "express";
import { BudgetModel } from "./budget.model.js";
import { ApiError } from "../../shared/utils/ApiError.js";

export class BudgetController {
  static async updateBudgetById(req: Request, res: Response) {
    const updated = await BudgetModel.update(req.params.id, req.body);
    if (!updated) throw ApiError.notFound("Budget not found");

    return res.status(200).json({ message: "Budget updated successfully", data: updated });
  }
}
```

Rules:

- **No try/catch, no `next(error)`** — Express 5 forwards async rejections to the global `errorHandler`.
- Throw `ApiError` (see api-contract.md) for expected failures; let unexpected Prisma errors bubble up to the 500 path.
- Odd/complex logic stays in the Model; the controller is HTTP translation only: read `req`, call model/middleware-provided data, respond with envelope.
- Destructure-and-strip sensitive fields when returning user objects (`password`, `token`, `confirmed`, etc.).

## 5. Models

Class with static methods wrapping the `prisma` singleton. The model is ORM territory: its **inputs are domain types** inferred from the module's Zod schemas and its return types stay inferred; the translation to ORM payloads — relation `connect`/`disconnect`, typed `include` fragments, `where` building — happens **inside this file**. Controllers send plain data and never shape ORM payloads:

```ts
import { prisma } from "../../config/db.js";
import type { Prisma } from "../../generated/prisma/client.js";
import type { CategoryInput } from "./category.schema.js";

const listInclude = { products: { select: { id: true, name: true } } } satisfies Prisma.CategoryInclude;

export class CategoryModel {
  static async create(data: CategoryInput) {
    return prisma.category.create({ data, include: listInclude });
  }
  static async getById(id: number) {
    return prisma.category.findUnique({ where: { id }, include: listInclude });
  }
}
```

- Naming: REST-ish verbs (`getAll`, `getById`, `create`, `update`, `delete`) plus descriptive finders (`findUserByEmail` — spelled correctly).
- Relation fields arrive as plain values (`categoryId: 3`) and are mapped **here**: `create` → `category: { connect: { id } }`; on update `null` → `{ disconnect: true }`. Typed `listInclude`/`listSelect` constants with `satisfies Prisma.XInclude` live at the top of the file.
- Duplicate/not-found: wrap the ORM call in try/catch **here** and delegate to `mapPrismaError(error, duplicateMessage, notFoundMessage)` (api-contract.md §6) — the model is the only file that knows the ORM.
- Business rules that guard an operation (e.g. "a record with history cannot be deleted") live here and throw `ApiError.conflict` before touching the ORM.
- Lists are deterministic: every `findMany` carries an explicit `orderBy` (e.g. `{ id: "asc" }`) so pages never shuffle.
- Ownership filters (`where: { userId: ... }`) belong here, not in controllers.
- Swapping ORMs rewrites the models plus the seams (§8) — controllers, schemas, and routes are untouched.
- **When a service exists** (§5.1), the model exposes the ONE transactional method the service feeds: it receives the computed payload and persists it atomically. The transaction boundary stays here — the service never imports the ORM.

## 5.1 Service layer (optional, profile `serviceLayer: on-demand`)

- Exists only for **procedural logic**: pure algorithms (drafts, round-robin, tie-break cascades, state machines) and multi-model orchestration. A service that only forwards to one model method is forbidden — delete it and call the model instead.
- Services never import the ORM: the transaction boundary is the model's (see §5). The service hands a computed payload to a single model method that persists it atomically.
- Services receive domain types (`z.infer`) and return domain shapes; controllers call them exactly as they would a model.
- **Decision algorithm when adding/changing a resource:** CRUD over one table → no service, four files. The slice needs a pure algorithm, a state machine, or a multi-model cascade → add `<domain>.service.ts` and name the ONE transactional model method it will feed.

```ts
// bracket.service.ts — reads, computes, hands ONE computed payload to ONE model method.
import type { GenerateBracketInput } from "./bracket.schema.js";
import { BracketModel } from "./bracket.model.js";
import { ApiError } from "../../shared/utils/ApiError.js";

export class BracketService {
  /** Pure: deterministic, zero I/O — unit-testable directly (testing.md). */
  static computeSlots(input: GenerateBracketInput, participants: ParticipantSeed[]): ComputedSlot[] {
    // seeding by ranking, half-bracket split, bye distribution ...
    return slots;
  }

  /** Orchestration: fetch → compute → persist through the single transactional method. */
  static async generate(input: GenerateBracketInput) {
    const participants = await BracketModel.listEligiblePlayers(input.tournamentId, input.category);
    if (participants.length < input.seedPlayers)
      throw ApiError.conflict("Not enough participants to generate the bracket");

    const slots = this.computeSlots(input, participants);
    return BracketModel.persistDrawing(input.tournamentId, slots); // the ONLY write
  }
}

// bracket.model.ts — transactional boundary: the service decides WHAT, this decides HOW atomically.
export class BracketModel {
  static async persistDrawing(tournamentId: string, slots: ComputedSlot[]) {
    return prisma.$transaction(async (tx) => {
      // retire the previous version, create the version, insert the slots ...
    });
  }
}

// bracket.controller.ts — the service replaces the model in the call; nothing else changes.
export class BracketController {
  static async putTournamentBracket(req: Request, res: Response) {
    const result = await BracketService.update(req.params.tournamentId, req.body);
    return res.status(200).json({ message: "Bracket updated successfully", data: result });
  }
}
```

## 6. Middleware

Cross-domain middleware lives in `src/shared/middleware/`. Validators are **factory functions** returning a middleware (closure over the Zod schema). Data-attaching middlewares assign to `req` and call `next()`. The full spec of the three validators — body/params/query, Zod 4 generics, field-error packing — lives in **api-contract.md §5**; that section is the single source, this file does not restate it.

Types they attach (`req.validatedQuery`, `req.user`, and future ones) are declared **once** in `src/shared/types/express.d.ts`:

```ts
declare global {
  namespace Express {
    interface Request {
      validatedQuery?: Record<string, unknown>;
    }
  }
}
```

Never add a per-file `declare global` block.

> Auth and ownership/access middleware are deferred to the auth skill — do not invent them now.

## 7. Zod schemas

One schema file per domain, inside the module (`modules/<domain>/<domain>.schema.ts`); cross-domain schemas (e.g. pagination) live in `shared/schemas/`. Compose by picking, not duplicating:

```ts
import z from "zod";

export const budgetSchema = z.object({
  name: z.string().min(1, "Name is required"),
  amount: z.number().positive("Amount must be positive"),
});

export const budgetIdSchema = z.object({ id: z.coerce.number().int("Invalid ID").positive("Invalid ID") });
export const passwordSchema = userSchema.pick({ password: true });
```

- Modern Zod 4 API: `z.email("Invalid email")`, `z.coerce.number()` for IDs, `z.flattenError(err)`. IDs follow the project profile's `idType` (SKILL.md): `int` → `z.coerce.number()`, `uuid` → `z.uuid()` — read the model, never assume.
- Parameter names inside schemas must match route param names (`:id` → `id`).

## 8. Config module

Environment variables are read **once**, validated with Zod, and imported everywhere else:

```ts
// config/env.ts
import "dotenv/config";
import z from "zod";

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3000),
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
});

export const env = envSchema.parse(process.env);
```

Usage: `import { env } from "../config/env.js"` — never `process.env.X!` outside `config/`. On invalid env, fail fast at boot.

`config/db.ts` is the **data seam**: the only place that builds the client, so the rest of the codebase never learns which ORM runs. The project profile's `dbSeam` (SKILL.md) may point elsewhere (e.g. `lib/prisma.ts` when the client already lives there) — only the path changes, never the rules.

```ts
// config/db.ts
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client.js";
import { env } from "./env.js";

const adapter = new PrismaPg({ connectionString: env.DATABASE_URL });
export const prisma = new PrismaClient({ adapter });

export async function connectDB() {
  await prisma.$queryRaw`SELECT 1`;
}
```

Together with `shared/utils/prismaError.ts` (provider errors → `ApiError`, see api-contract.md §6), `config/db.ts` and the `*.model.ts` classes form the **complete, closed list** of files that may import the ORM. Migrating to another ORM rewrites those files only.

## 9. App shape — the single source for `server.ts` / `index.ts`

- `server.ts` builds the Express app in **this exact order**:
  1. `express.json()` — first, everything downstream assumes a parsed body.
  2. **Malformed-JSON translator** — an error-handling middleware that turns `express.json()` parse failures into the `400 VALIDATION_ERROR` envelope (api-contract.md §2), delegating everything else with `next(err)`.
  3. `cors({ origin: <CORS_ORIGINS whitelist>, credentials: true })` — api-contract.md §9.
  4. `cookieParser()` — as soon as the auth module exists; nothing else in the app reads cookies (auth.md).
  5. Each module's router from `modules/<domain>/index.js` under `/api/v1/...`.
  6. **Catch-all 404** — `app.use((req, res) => res.status(404).json({ message: "Route not found", code: "ROUTE_NOT_FOUND", data: null }))` so no client ever sees Express's default HTML 404. After all routers, before the error handler.
  7. `errorHandler` — always last (api-contract.md §6).
- `server.ts` exports both `app` and `startServer()` (listens on `env.PORT`), which logs exactly one line at boot — the format lives here, nowhere else:

```ts
console.log(`Server listening on port ${env.PORT} (${env.NODE_ENV})`);
```

- `index.ts`: connects DB (`config/db.ts`), then calls `startServer()` **only** when `NODE_ENV !== "test"`.
- **Graceful shutdown**: `SIGINT`/`SIGTERM` → `server.close()` → `prisma.$disconnect()`. In-flight requests finish; the process exits cleanly instead of dropping connections.
- Cross-cutting middleware (rate limiter) is defined in `config/` and applied per router where appropriate (auth.md wires it on the auth router).
