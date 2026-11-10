# 02 — Migración inicial `init_tournament_management` (SQL con CHECKs e índices parciales)

Status: ready-for-agent
Type: task
Blocked by: 01

## Resumen

Generar la migración inicial versionada `init_tournament_management` a partir del esquema del ticket 01, editar el SQL generado para añadir lo que Prisma 7 no expresa, y verificarla contra el motor (offline si no hay `DATABASE_URL`).

## Fuentes normativas (context pointers)

- Spec: `specs/tournament-database/spec.md` — Testing Decisions (gate manual) e Implementation Decisions (CHECKs, parciales, NULLS NOT DISTINCT).
- Prisma 7 workflow: `.agents/skills/db-design/references/prisma-target.md` (secciones ENUM vs CHECK, Migration workflow, NULL-safe uniqueness, soft delete & partial indexes).
- Esquema base: `prisma/schema.prisma` ya fusionado en la rama de integración (ticket 01).

## Pasos

1. Generar el DDL completo offline: `pnpm exec prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script`.
2. Crear `prisma/migrations/<timestamp>_init_tournament_management/migration.sql` con ese DDL y `prisma/migrations/migration_lock.toml` (provider `postgresql`).
3. Editar el SQL antes de aplicar: CHECKs con nombre (`ck_*`; estados de match, kind/consistencia de llave, games_to_win ∈ {2,3,4}, slot ∈ {1,2}, roster slot, puntaje de game ganador > perdedor y ≥ 0, rol de account), índices únicos parciales (1 partido no finalizado por árbitro; 1 `en_curso` por mesa; índice parcial `WHERE deleted_at IS NULL` en participant y en su(s) índice(s) de lookup) y `UNIQUE ... NULLS NOT DISTINCT` donde los members sean nulables (p. e. `uq_category_tournament_code`).
4. Verificación contra motor: si hay `DATABASE_URL` (definida por el usuario), aplicar realmente con `prisma migrate dev`; si no la hay (estado actual), respaldo obligatorio del spec: revisión integral del SQL con `prisma migrate diff` y lectura completa del DDL — la aplicación real queda disponible cuando el usuario la provea (no usar `prisma db push` nunca).
5. NO modificar `schema.prisma` salvo lo que la verificación exija para mantener sin deriva el par esquema↔SQL (y reportarlo).

## Aceptación

- Migración versionada en `prisma/migrations/` con el SQL final revisado de arriba a abajo, con CHECKs/parciales/NULLS NOT DISTINCT añadidos y nombrados.
- `prisma validate` sigue pasando; sin deriva esquema↔SQL (o la deriva detectada está reportada).
- Si `DATABASE_URL` estaba disponible: migración aplicada en el motor real en primera pasada.
