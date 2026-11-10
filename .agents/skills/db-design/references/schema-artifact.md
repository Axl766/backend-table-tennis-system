# Schema artifact - output format & canonical example

Load AFTER the Phase 1 checkpoint passed and the target selection resolved. This file defines what you deliver.

> **Canonical dialect**: the example below is written in **pure PostgreSQL 15+** - `TIMESTAMPTZ` for every instant (including audit timestamps), `NULLS NOT DISTINCT` where uniqueness must ignore NULLs, `--` comments (portable). Engine divergences live in `references/dialects.md`; emit them explicitly, never mixed into this artifact.

## Phase 1 checkpoint template (present BEFORE any schema work)

The Phase 1 checkpoint uses this exact shape - it replaces prose-only summaries and keeps the gate auditable:

- **Entity table** - one row per extracted entity, each tied to the domain source that supports it:

  | Entity | Type | Key attributes | Relationships | Min/Max | Source (doc/section) |
  |---|---|---|---|---|---|
  | `Purchase` | Subject | id (surrogate), paid_at, customer_id | HAS many product_purchase | 1 -> 0..N | docs/03-actors.md L12 |

- **Numbered open questions** - every undecided point as a question the user must answer, numbered (`Q1`, `Q2`, ...) so answers can be quoted back: optional vs mandatory sides, cardinality gaps, lifecycle (who creates/updates/deletes), anything the domain docs left ambiguous. A checkpoint with zero open questions must say so explicitly ("no open questions - confirm to proceed").
- **Confirmation request** - end with one line: what "confirmed" unlocks (loading the target-schema references and starting Phase 2).

## Output format (3 sections, always)

1. **Conceptual ER Model Summary**: entities, attributes, keys (PK/FK, natural vs surrogate - note the **surrogate + natural UNIQUE** rule), relationships with Crow's Foot + Min/Max cardinalities, in tables - plus a compact Mermaid `erDiagram` of the same model, inline as a fenced block. Crow's Foot symbols: `||--||` 1:1, `||--o{` 1 to zero-or-many, `||--|{` 1 to one-or-many, `}o--o{` M:N (red flag - it must have become a junction).

   ```mermaid
   erDiagram
       CUSTOMER ||--o{ PURCHASE : places
       PURCHASE ||--|{ PRODUCT_PURCHASE : contains
       PRODUCT ||--o{ PRODUCT_PURCHASE : "included in"
   ```

2. **Target Schema Artifact**: exactly one of:
   - **Prisma mode**: complete `schema.prisma`, produced and verified per `references/prisma-target.md` (validate + format gate, versioned migration with reviewed SQL).
   - **DDL mode**: executable `CREATE TABLE` statements with explicit types, `CONSTRAINT`-named constraints, FK referential actions, and indices.

3. **Architecture & Trade-off Defense** (the **trade-off defense**): why each data type (DECIMAL not FLOAT, CHAR vs VARCHAR...), the security split (DB-enforced vs app-layer), indexing strategy, soft-delete and migration decisions, the justification for every escape-hatch BIGINT, and the concurrency & idempotency calls (which constraints make duplicates physically impossible, and where a locking/serializable protocol is required instead - Phase 3). Also state the modelling choice when two valid decompositions exist (see the alternative below).

## Canonical DDL example (pattern to imitate)

Domain: "Customers buy products; each purchase lists products with quantity."

Phase 1 nouns: customer, product, purchase, quantity. Verbs: buys / lists. Ownership Test: a customer HAS a purchase (one customer, many purchases -> 1:N, `purchase.customer_id`); a purchase HAS products in quantities; a product can appear in many purchases and a purchase has many products -> M:N -> junction `product_purchase` (alphabetical: product < purchase), carrying `quantity` + `line_price` (M:N with attributes). Alternative: if a product can appear at most once per purchase, re-model as `purchase` + `product_purchase(purchase_id, product_id)` with composite PK - state which applies and why.

```sql
CREATE TABLE customer (
  customer_id   UUID         NOT NULL,  -- mint uuidv7 APP-SIDE before INSERT (default); `DEFAULT uuidv7()` is the PG18+ variant (references/dialects.md)
  email         VARCHAR(320) NOT NULL,
  password_hash VARCHAR(100) NOT NULL,  -- algorithm: bcrypt (hashed app-side); name the algorithm in a SQL comment or COMMENT ON COLUMN
  full_name     VARCHAR(50)  NOT NULL,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_customer        PRIMARY KEY (customer_id),
  CONSTRAINT uq_customer_email  UNIQUE (email)              -- surrogate + natural UNIQUE: no business dupes
);

CREATE TABLE product (
  product_code    CHAR(12)      NOT NULL,     -- natural key: immutable, fixed-length, short
  name            VARCHAR(100)  NOT NULL,
  manufacturer    VARCHAR(50)   DEFAULT NULL, -- nullable member -> uniqueness must be NULL-safe (see uq_product_trade)
  unit_price      DECIMAL(10,2) NOT NULL,
  stock_qty       INT           NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_product        PRIMARY KEY (product_code),
  CONSTRAINT uq_product_trade  UNIQUE (name, manufacturer) NULLS NOT DISTINCT,  -- PG15+: (Hammer, NULL) collides with (Hammer, NULL)
  CONSTRAINT ck_product_price  CHECK (unit_price >= 0)
);

CREATE TABLE purchase (
  purchase_id UUID        NOT NULL,  -- mint uuidv7 app-side; BIGINT IDENTITY only as escape hatch (justified)
  customer_id UUID        NOT NULL,
  paid_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- soft delete decision: physical delete here + audit via 'purchase_archive'
  CONSTRAINT pk_purchase         PRIMARY KEY (purchase_id),
  CONSTRAINT fk_purchase_customer FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE RESTRICT
);

CREATE INDEX ix_purchase_customer ON purchase(customer_id);   -- FK index (not automatic on Postgres/MariaDB)

CREATE TABLE product_purchase (   -- junction: alphabetical (product < purchase), composite PK
  purchase_id UUID    NOT NULL,  -- mint uuidv7 app-side
  product_id  CHAR(12) NOT NULL,
  quantity    INT      NOT NULL CHECK (quantity > 0),
  line_price  DECIMAL(10,2) NOT NULL,          -- unit price at sale time
  CONSTRAINT pk_product_purchase  PRIMARY KEY (purchase_id, product_id),
  CONSTRAINT fk_pp_purchase FOREIGN KEY (purchase_id) REFERENCES purchase(purchase_id)     ON DELETE CASCADE,
  CONSTRAINT fk_pp_product  FOREIGN KEY (product_id)  REFERENCES product(product_code)    ON DELETE RESTRICT
);

CREATE INDEX ix_product_purchase_product ON product_purchase(product_id);  -- FK index (composite PK only covers the purchase side)
```

Notes:
- The composite PK indexes the purchase-side lookups; the reverse lookup (all purchases containing a product) needs the explicit FK index.
- `created_at`/`updated_at` on business tables as `TIMESTAMPTZ` (instants, UTC storage); `purchase` shows the per-table soft-delete decision as a commented owner.
- `uq_product_trade` demonstrates NULL-safe uniqueness: a nullable natural-key member resolved with `NULLS NOT DISTINCT` (PostgreSQL 15+) instead of being left implicitly breakable.
- Every constraint is named; every FK action is explicit.
