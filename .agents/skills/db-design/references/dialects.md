# Dialect callouts - per-engine warnings

Load once the target engine is known. Rule of thumb: write the core artifact engine-agnostic; where semantics diverge, emit the per-dialect variant explicitly instead of pretending one script fits all.

## SQLite
- No `CREATE ROLE`/`GRANT` - RBAC handled at app level.
- No real `ON UPDATE` (and limited `ON DELETE` reactivity) unless foreign keys are enabled: `PRAGMA foreign_keys = ON`.
- `DECIMAL` is stored as float/TEXT - keep money in integer minor units (cents, `Int`).
- `TIMESTAMP` has NUMERIC affinity - store ISO-8601 text.
- No ENUM - `CHECK` `IN` lists only.
- `AUTOINCREMENT` / `INTEGER PRIMARY KEY` semantics differ from MySQL's identity columns; UUIDv7 is minted app-side and stored as fixed-length text/BLOB.

## MySQL / MariaDB
- Identifier limit: 64 chars.
- FK requires matching, types-equal indexes on both sides (InnoDB auto-indexes FK columns - still state each index explicitly so the artifact is engine-independent).
- `TIMESTAMP` range starts at 1970 - use `DATETIME` for historical dates.
- **NULL-safe UNIQUE**: no `NULLS NOT DISTINCT` equivalent. Resolve nullable natural-key members with `NOT NULL` / a real `DEFAULT`, or (MySQL 8.0.13+, MariaDB 10.2+ expression indexes) a generated column participating in the UNIQUE.
- Prefer explicit `CONSTRAINT` names everywhere (UG constraints disappear into auto-generated names otherwise).

## PostgreSQL
- Prefer `TIMESTAMPTZ` for instants (plain `TIMESTAMP` does NOT convert). This includes audit timestamps (`created_at`/`updated_at`) - they record real events, not local wall-clock.
- `SERIAL` / `IDENTITY` for sequences; `ENUM` is a real type; partial and functional indexes available; richer `CHECK`-constraint lookup and trigger ecosystem.
- **NULL-safe UNIQUE**: PostgreSQL 15+ supports `UNIQUE ( ...) [table constraint] NULLS NOT DISTINCT` - two rows that differ only by NULL members then collide. Use it (or a partial `CREATE UNIQUE INDEX ... WHERE <condition>`) whenever a natural UNIQUE has nullable members (SKILL.md Phase 2.6); plain UNIQUE lets `(Hammer, NULL)` repeat.
- Partial index for soft delete: `CREATE INDEX ix_purchase_customer ON purchase(customer_id) WHERE deleted_at IS NULL;` - the same pattern scopes a natural UNIQUE to live rows when deletion frees the value (`CREATE UNIQUE INDEX ... WHERE deleted_at IS NULL`).
- Inline `COMMENT '...'` on a column is MySQL-only syntax; in PostgreSQL use `--` operands or `COMMENT ON COLUMN <table>.<column> IS '...'`.
- **DB-side UUIDv7 variant**: `DEFAULT uuidv7()` exists only on PostgreSQL 18+ (e.g., `customer_id UUID NOT NULL DEFAULT uuidv7()`). The default remains **app-side** minting - offer the DB-side variant only when PostgreSQL 18+ is confirmed.
