# Prisma Target - mechanics

Load when the target selection resolved to Prisma. Version baseline: Prisma 7 (detect the project's version from `package.json` - Prisma 7 vs 8+ changes the CHECK / partial-index syntax below); dialect notes target PostgreSQL unless stated.

## Conventions detection (resolve before writing any schema)
Every project is different - detect its local setup before emitting a schema. Documented project conventions (AGENTS.md, steering files, docs/) OVERRIDE everything below.

- **Tooling**: pick the package manager from the lockfile (`pnpm-lock.yaml` -> pnpm, `package-lock.json` -> npm, ...); run Prisma as `<pm> exec prisma <command>`, or prefer existing `package.json` scripts when they exist.
- **Prisma version & generator**: check the version and the generator block of `schema.prisma`. With `prisma-client` the client is imported from the generated output directory - NOT from `@prisma/client` (that is the legacy `prisma-client-js` shape). Never change the generator/output without checking existing imports.
- **ESM vs CJS**: `"type": "module"` changes import syntax (extensions, no `require`); match the project.
- **Migration state**: if `prisma/migrations/` already exists, deliver incremental migrations only; if it does not, the first migration is the INITIAL one - name it `init_<domain_snake_case>`.
- **Driver adapter**: match whatever the project installed (`@prisma/adapter-pg`, `@prisma/adapter-...`).
- Skill delegation: driver-adapter wiring -> `prisma-driver-adapter-implementation`; CLI flags/troubleshooting -> `prisma-cli`; provider specifics -> `prisma-postgres` - delegate to those skills **when installed**; otherwise handle inline from Prisma's official docs.

## Naming: idiomatic Prisma code, conventional database
- Models: `PascalCase`, singular, English (`model Purchase`), mapped to the DB with `@@map("purchase")`.
- Fields: `camelCase`, English, mapped with `@map("snake_case")` (`paidAt @map("paid_at")`).
- Phase 2 rules (snake_case, singular, no reserved words, <64 chars) apply to the **mapped DB identifiers** - verify those, not just the Prisma names.
- Name meaningful constraints explicitly where supported: `@unique(map: "uq_customer_email")`, `@@unique([...], map: "uq_product_trade")`, `@@index([...], map: "ix_purchase_customer")`.

## Primary keys (syntax map - the policy's single source of truth is SKILL.md Phase 2)
- Surrogate default: `id Uuid @id @default(uuid(7))` (app-side; rationale and natural-key rule: SKILL.md Phase 2). DB-side variant: `@default(dbgenerated("uuidv7()"))` - PostgreSQL 18+ only (see `references/dialects.md`); document that raw-SQL/third-party writers must mint the ID when generation is app-side.
- Native `uuid` type always (`Uuid` scalar; `String @db.Uuid` also valid) - never `TEXT`.
- Natural: `productCode String @id @db.Char(12)` - and **surrogate + natural UNIQUE** still holds: surrogate PK requires `@unique` on the natural identifying attributes.
- **NULL-safe uniqueness**: nullable members of a `@unique`/`@@unique` silently break the guarantee (NULL never collides with NULL). The Prisma schema language has NO `NULLS NOT DISTINCT` equivalent (7 or 8) - resolve it in the migration SQL: edit the generated constraint/index to `NULLS NOT DISTINCT` (PostgreSQL 15+), swap it for a partial `CREATE UNIQUE INDEX ... WHERE <condition>`, or make the field `NOT NULL` / give it a real `Default(name(...))`. State the choice in the trade-off defense.
- Escape hatch: `id BigInt @id @default(autoincrement())` - same semantics as SKILL.md Phase 2; justify in the trade-off defense.
- Junction composite PK: `@@id([purchaseId, productId])` - FK scalars are `Uuid` when parents use the UUIDv7 default.
- Time-ordered pagination: composite cursor `(createdAt, id)` - SKILL.md Phase 2 explains why.

## Type mapping (PostgreSQL)
| Phase 3 rule | Prisma |
|---|---|
| `DECIMAL(p,s)` money | `Decimal @db.Decimal(p, s)` |
| `INT` / `BIGINT` | `Int` / `BigInt` |
| `CHAR(n)` fixed code | `String @db.Char(n)` |
| `VARCHAR(n)` | `String @db.VarChar(n)` |
| `TEXT` large | `String @db.Text` |
| `DATE` | `DateTime @db.Date` |
| `TIMESTAMP WITH TIME ZONE` (instants) | `DateTime @db.Timestamptz` |
| `TIMESTAMP` without TZ (local) | `DateTime @db.Timestamp(3)` |
| `FLOAT/DOUBLE` (science only) | `Float` (Postgres double precision) |
| `BOOLEAN` | `Boolean` |

MySQL/SQLite divergences: MySQL `DATETIME` -> `@db.DateTime(3)`; SQLite has no native Decimal - money in integer minor units (`Int`, cents).

Audit timestamps on PostgreSQL: `created_at`/`updated_at` are instants -> declare `DateTime @db.Timestamptz` explicitly (Prisma's bare `DateTime` maps to `timestamp(3)` without timezone, contradicting the TIMESTAMPTZ policy in `dialects.md`).

## Relations & referential actions
- 1:N: scalar FK on the many side + `@relation(fields: [customerId], references: [id], onDelete: Restrict)`. Every Phase 3 decision (RESTRICT/CASCADE/SET NULL) maps to `onDelete`/`onUpdate` explicitly.
- 1:1: FK on the optional side + `@unique` on the FK scalar.
- M:N: **explicit junction model ALWAYS** - never implicit many-to-many. Implicit relations do not support referential actions, auto-name the join table, and cannot carry extra attributes - all three violate Phase 2/3 rules.

## ENUM vs CHECK (same policy as DDL mode)
- Frozen sets -> native `enum PurchaseStatus { ... }`.
- Evolvable sets -> CHECK constraint. **Prisma 7 cannot express CHECK in the schema language**: generate the migration, then add the CHECK as custom SQL inside `prisma/migrations/<name>/migration.sql` before applying (official unsupported-features workflow).
- **Prisma 8+ projects**: use native `@@check(expression: "...")` and partial indexes `@@index([...], where: "...")` directly in the schema instead of migration SQL.

## Soft delete & partial indexes
- `deletedAt DateTime? @map("deleted_at")` + lookup indexes need `WHERE deleted_at IS NULL`. Prisma 7: add as custom SQL in the migration. Prisma 8+: native `@@index(..., where: ...)`.

## Audit columns
- `createdAt DateTime @default(now()) @map("created_at")`
- `updatedAt DateTime @updatedAt @map("updated_at")` - application-maintained by Prisma Client; document that choice (DDL mode maintains it via triggers - never mix).

## Migration workflow (finish line - this skill ends here)
1. Write the complete `schema.prisma`.
2. **Gate**: run `<pm> exec prisma validate` and `<pm> exec prisma format`; fix everything they flag before showing the schema to the user.
3. `<pm> exec prisma migrate dev --name <snake_case_name>` (e.g. `init_inventory`; if `prisma/migrations/` does not exist yet, this is the initial migration - name it `init_<domain_snake_case>`).
4. **Review and edit the generated SQL** in `prisma/migrations/<name>/migration.sql` BEFORE applying - this is where CHECKs, partial indexes and `NULLS NOT DISTINCT` are added or reworked on Prisma 7 (the schema language cannot express them).
5. **Verification gate**: apply the migration to a disposable/shadow database (local container, branch DB). Validate+format alone prove nothing about whether the migration applies; at minimum, review the final SQL top-to-bottom engine-side (`prisma migrate diff` against the real engine is the fallback when no disposable DB exists).
6. Never `prisma db push` against a shared or migrated database.

CLI flags, troubleshooting, drift resolution -> delegate to the `prisma-cli` skill when installed; otherwise consult Prisma's official migration docs.

## Canonical example (Prisma target)

Same domain as the DDL example in SKILL.md: customers buy products; each purchase lists products with quantity; junction `product_purchase` (alphabetical: product < purchase). Surrogate PKs use the UUIDv7 default (`Uuid @id @default(uuid(7))`); `product` keeps its natural key.

```prisma
model Customer {
  id           Uuid     @id @default(uuid(7)) // surrogate PK - UUIDv7 default, app-side generation
  email        String   @db.VarChar(320) @unique(map: "uq_customer_email") // surrogate + natural uniqueness
  passwordHash String   @map("password_hash") @db.VarChar(100) // algorithm: bcrypt, hashed app-side
  fullName     String   @map("full_name") @db.VarChar(50)
  createdAt    DateTime @default(now()) @map("created_at") @db.Timestamptz // instant, UTC storage (audit clock, not the UUID bits)
  updatedAt    DateTime @updatedAt @map("updated_at") @db.Timestamptz
  purchases    Purchase[]
  @@map("customer")
}

model Product {
  productCode   String  @id @db.Char(12) // natural key: immutable, fixed-length
  name          String  @db.VarChar(100)
  manufacturer  String? @db.VarChar(50)
  unitPrice     Decimal @map("unit_price") @db.Decimal(10, 2) // unit_price >= 0 -> CHECK as custom SQL in migration (Prisma 7)
  stockQty      Int     @default(0) @map("stock_qty")
  createdAt     DateTime @default(now()) @map("created_at") @db.Timestamptz
  purchaseItems ProductPurchase[]
  @@unique([name, manufacturer], map: "uq_product_trade") // nullable member -> deliver as NULLS NOT DISTINCT / partial unique in migration SQL (Prisma cannot express it)
  @@map("product")
}

model Purchase {
  id         Uuid     @id @default(uuid(7))
  customerId Uuid     @map("customer_id")
  customer   Customer @relation(fields: [customerId], references: [id], onDelete: Restrict, map: "fk_purchase_customer")
  paidAt     DateTime @default(now()) @map("paid_at") @db.Timestamptz
  // soft delete decision: physical delete here + audit via 'purchase_archive'
  items      ProductPurchase[]
  @@index([customerId], map: "ix_purchase_customer")
  @@map("purchase")
}

model ProductPurchase {
  purchaseId Uuid     @map("purchase_id")
  productId  String   @map("product_id") @db.Char(12)
  quantity   Int
  purchase   Purchase @relation(fields: [purchaseId], references: [id], onDelete: Cascade)
  product    Product  @relation(fields: [productId], references: [productCode], onDelete: Restrict)
  @@id([purchaseId, productId]) // composite PK of both FKs
  @@map("product_purchase")
}
```
