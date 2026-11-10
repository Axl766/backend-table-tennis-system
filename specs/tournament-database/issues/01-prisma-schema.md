# 01 — Escribir el esquema Prisma (16 tablas)

Status: resolved
Type: task
Blocked by: —

## Resumen

Crear `prisma/schema.prisma` completo con las 16 entidades del spec (account, tournament, category, modality, modality_gender, player, participant, participant_player, group, match, match_participant, match_game, bracket, podium, tournament_event, audit_log, schedule_image — ver tabla completa en el spec).

## Fuentes normativas (context pointers)

- Spec: `specs/tournament-database/spec.md` (secciones Implementation Decisions e Índices son la fuente de verdad de atributos/constraints).
- Glosario del dominio (normativo para conceptos): `GLOSSARY.md`.
- Convención técnica obligatoria: `.agents/skills/db-design/SKILL.md` (fases 2–3, naming, pk/fk/null-safe) y `.agents/skills/db-design/references/prisma-target.md` (sintaxis Prisma 7, maps, junctions, Timestamptz, constraints nombrados).

## Alcance y reglas clave

- Identificadores en inglés; modelos PascalCase, campos camelCase; DB en snake_case singular vía `@map`/`@@map`; constraints nombrados `uq_*`, `ix_*`, `fk_*`, `ck_*`.
- PKs UUIDv7 app-side en tablas de negocio; `audit_log` con PK BIGINT secuencial (escape hatch justificado).
- Sin claves naturales en `account` ni `player` (decisión del usuario: unicidad por id; dublicados de jugadores se previenen en la importación, fuera de alcance).
- `UNIQUE(head_judge_id, name)` en tournament; `UNIQUE(code)` + `UNIQUE(tournament_id, code)` en category; `UNIQUE(tournament_id, number)` en mesa; `UNIQUE(match_id, game_no)` en match_game; natural única de group/bracket por rama (ver spec); podium con place; `UNIQUE(tournament_id, type)` en tournament_event; PKs compuestas en junctions.
- Uniques con miembros nulables (p. ej. category.tournament_id) se dejan declaradas pensando en resolverlas en migración (ticket 02): documentar el pendiente `NULLS NOT DISTINCT`.
- Timestamps Timestamptz explícitos; soft delete solo `participant.deleted_at`; sin `SetNull` (Restrict/Cascade por el spec).
- generator: `prisma-client` con output a `../src/generated/prisma` (driver adapter `@prisma/adapter-pg`), datasource postgresql; la aplicación real se detalla en ticket 02 (nada de `db push`).
- NO crear `.env` (el DATABASE_URL lo agrega el usuario); para `validate` usar placeholder de env en línea (E.g. en PowerShell: `$env:DATABASE_URL='postgresql://u:p@localhost:5432/db'`). NO crear seeds, NO código de consulta, NO API (fuera de alcance; reportar desvío).

## Aceptación

- `pnpm exec prisma validate --schema prisma/schema.prisma` y `prisma format` pasan sin errores (con placeholder de env).
- El modelo cubre las 16+ entidades y cada decisión del spec; sin deriva puntual contra el spec.
