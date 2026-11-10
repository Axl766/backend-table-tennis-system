-- =====================================================================
-- init_tournament_management — initial migration (ticket 02)
--
-- Base DDL: generated OFFLINE with `prisma migrate diff --from-empty
-- --to-schema <worktree>/prisma/schema.prisma --script`, then edited
-- manually (reviewed top-to-bottom) to add what Prisma 7 cannot express
-- in the schema language (per specs/tournament-database/spec.md and the
-- pending-SQL header documented in prisma/schema.prisma):
--
-- CHECK constraints (ck_*):
--   ck_account_role                  role ∈ {administrator, head_judge, referee}
--   ck_account_referee_tournament    referee accounts are tournament-scoped
--   ck_tournament_games_to_win       games_to_win ∈ {2,3,4}  (best of 3/5/7)
--   ck_modality_gender_conformation  modality_gender.conformation ∈ {damas, varones, mixta}
--   ck_player_gender                 player.gender ∈ {femenino, masculino} (NULL allowed — optional import data)
--   ck_participant_conformation      participant.conformation ∈ {damas, varones, mixta}
--   ck_tournament_table_number       number >= 1
--   ck_group_letter                  group_letter is 1–2 uppercase ASCII letters (A, B…; SIMILAR TO
--                                    — PostgreSQL LIKE has no character classes)
--   ck_match_kind                    kind ∈ {group, bracket}
--   ck_match_status                  status ∈ {pendiente, en_curso, finalizado}
--   ck_match_group_kind              kind='group' ⇒ group_id IS NOT NULL
--   ck_match_bracket_kind            kind='bracket' ⇒ bracket_id IS NOT NULL AND round_no IS NOT NULL
--   ck_match_participant_slot        slot ∈ {1,2}
--   ck_match_game_winner_slot        winner_slot ∈ {1,2}
--   ck_match_game_points             winner_points > loser_points AND both >= 0
--   ck_participant_player_slot       roster slot 1..5 (2 for doubles / 3–5 for teams; exact count in app)
--   ck_podium_place                  place ∈ 1..3 (3 only when a third place was activated — app protocol)
--   ck_tournament_event_type         type ∈ {publish_groups, close_tournament}
--   (audit_log has no action column and no CHECK — polymorphic entity/entity_id by design, documented N/A)
--
-- Partial unique indexes (engine-level concurrency, never app-only guards):
--   uq_match_referee_active  one NON-finalized match per referee
--   uq_match_table_active    one 'en_curso' match per table
--
-- Partial lookup index (soft delete, spec "Índices"):
--   ix_participant_active    participants of a tournament WHERE deleted_at IS NULL
--
-- NULL-safe uniqueness (PostgreSQL 15+):
--   uq_category_tournament_code  rewritten as a NULLS NOT DISTINCT unique
--     index: for the global catalog (tournament_id IS NULL) the same code may
--     never be duplicated across two NULL-scope rows; the global code key
--     (uq_category_code) already covers cross-scope collisions, so (NULL,code)
--     vs (tournament_id,code) may not clash — NULLS NOT DISTINCT gives
--     corner-case semantics matching the declared intent with no extra filter.
--
-- Sealed-competition protocol stays in application code (no triggers in
-- Prisma mode): participants immutable after 'publish_groups'; the 2-point
-- gap beyond 11 in a game is an application rule (spec decision: points
-- CHECK only rejects ties/negatives).
-- =====================================================================

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "account" (
    "id" UUID NOT NULL,
    "role" VARCHAR(20) NOT NULL,
    "tournament_id" UUID,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "account_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tournament" (
    "id" UUID NOT NULL,
    "head_judge_id" UUID NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "games_to_win" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "tournament_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tournament_table" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "number" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "tournament_table_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "category" (
    "id" UUID NOT NULL,
    "code" VARCHAR(12) NOT NULL,
    "name" VARCHAR(60) NOT NULL,
    "tournament_id" UUID,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "category_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "modality" (
    "id" UUID NOT NULL,
    "name" VARCHAR(30) NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "modality_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "modality_gender" (
    "modality_id" UUID NOT NULL,
    "conformation" VARCHAR(10) NOT NULL,

    CONSTRAINT "modality_gender_pkey" PRIMARY KEY ("modality_id","conformation")
);

-- CreateTable
CREATE TABLE "player" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "full_name" VARCHAR(100) NOT NULL,
    "gender" VARCHAR(10),
    "age" INTEGER,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "player_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "participant" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "modality_id" UUID NOT NULL,
    "conformation" VARCHAR(10) NOT NULL,
    "deleted_at" TIMESTAMPTZ,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "participant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "participant_player" (
    "participant_id" UUID NOT NULL,
    "player_id" UUID NOT NULL,
    "slot" INTEGER NOT NULL,

    CONSTRAINT "participant_player_pkey" PRIMARY KEY ("participant_id","player_id")
);

-- CreateTable
CREATE TABLE "tournament_group" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "modality_id" UUID NOT NULL,
    "conformation" VARCHAR(10) NOT NULL,
    "group_letter" VARCHAR(2) NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "tournament_group_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bracket" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "modality_id" UUID NOT NULL,
    "conformation" VARCHAR(10) NOT NULL,
    "classified_per_group" INTEGER NOT NULL,
    "has_third_place" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "bracket_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "match" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "kind" VARCHAR(10) NOT NULL,
    "status" VARCHAR(10) NOT NULL,
    "group_id" UUID,
    "bracket_id" UUID,
    "round_no" INTEGER,
    "table_id" UUID,
    "queue_position" INTEGER,
    "referee_id" UUID,
    "winner_participant_id" UUID,
    "next_match_id" UUID,
    "is_third_place" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "match_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "match_participant" (
    "match_id" UUID NOT NULL,
    "slot" INTEGER NOT NULL,
    "participant_id" UUID,

    CONSTRAINT "match_participant_pkey" PRIMARY KEY ("match_id","slot")
);

-- CreateTable
CREATE TABLE "match_game" (
    "id" UUID NOT NULL,
    "match_id" UUID NOT NULL,
    "game_no" INTEGER NOT NULL,
    "winner_slot" INTEGER NOT NULL,
    "winner_points" INTEGER NOT NULL,
    "loser_points" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "match_game_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "podium" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "modality_id" UUID NOT NULL,
    "conformation" VARCHAR(10) NOT NULL,
    "place" INTEGER NOT NULL,
    "participant_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "podium_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tournament_event" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "type" VARCHAR(20) NOT NULL,
    "occurred_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "snapshot" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "tournament_event_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "schedule_image" (
    "id" UUID NOT NULL,
    "tournament_id" UUID NOT NULL,
    "version" INTEGER NOT NULL,
    "image_data" BYTEA NOT NULL,
    "mime_type" VARCHAR(100) NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "schedule_image_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_log" (
    "id" BIGSERIAL NOT NULL,
    "actor_account_id" UUID NOT NULL,
    "entity" VARCHAR(50) NOT NULL,
    "entity_id" UUID NOT NULL,
    "old_value" JSONB,
    "new_value" JSONB,
    "occurred_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ix_account_tournament" ON "account"("tournament_id");

-- CreateIndex
CREATE INDEX "ix_tournament_head_judge" ON "tournament"("head_judge_id");

-- CreateIndex
CREATE UNIQUE INDEX "uq_tournament_head_judge_name" ON "tournament"("head_judge_id", "name");

-- CreateIndex
CREATE INDEX "ix_tournament_table_tournament" ON "tournament_table"("tournament_id");

-- CreateIndex
CREATE UNIQUE INDEX "uq_tournament_table_number" ON "tournament_table"("tournament_id", "number");

-- CreateIndex
CREATE UNIQUE INDEX "uq_category_code" ON "category"("code");

-- CreateIndex
CREATE UNIQUE INDEX "uq_category_tournament_code" ON "category"("tournament_id", "code") NULLS NOT DISTINCT;

-- CreateIndex
CREATE INDEX "ix_player_tournament" ON "player"("tournament_id");

-- CreateIndex
CREATE INDEX "ix_participant_tournament" ON "participant"("tournament_id");

-- CreateIndex
CREATE INDEX "ix_participant_category" ON "participant"("category_id");

-- CreateIndex
CREATE INDEX "ix_participant_modality" ON "participant"("modality_id");

-- CreateIndex
CREATE INDEX "ix_participant_player_player" ON "participant_player"("player_id");

-- CreateIndex
CREATE UNIQUE INDEX "uq_tournament_group_branch_letter" ON "tournament_group"("tournament_id", "category_id", "modality_id", "conformation", "group_letter");

-- CreateIndex
CREATE UNIQUE INDEX "uq_bracket_branch" ON "bracket"("tournament_id", "category_id", "modality_id", "conformation");

-- CreateIndex
CREATE INDEX "ix_match_tournament" ON "match"("tournament_id");

-- CreateIndex
CREATE INDEX "ix_match_tournament_status" ON "match"("tournament_id", "status");

-- CreateIndex
CREATE INDEX "ix_match_group" ON "match"("group_id");

-- CreateIndex
CREATE INDEX "ix_match_bracket" ON "match"("bracket_id");

-- CreateIndex
CREATE INDEX "ix_match_table" ON "match"("table_id");

-- CreateIndex
CREATE INDEX "ix_match_referee" ON "match"("referee_id");

-- CreateIndex
CREATE INDEX "ix_match_winner_participant" ON "match"("winner_participant_id");

-- CreateIndex
CREATE INDEX "ix_match_next_match" ON "match"("next_match_id");

-- CreateIndex
CREATE INDEX "ix_match_participant_participant" ON "match_participant"("participant_id");

-- CreateIndex
CREATE UNIQUE INDEX "uq_match_game_match_no" ON "match_game"("match_id", "game_no");

-- CreateIndex
CREATE INDEX "ix_podium_participant" ON "podium"("participant_id");

-- CreateIndex
CREATE UNIQUE INDEX "uq_podium_branch_place" ON "podium"("tournament_id", "category_id", "modality_id", "conformation", "place");

-- CreateIndex
CREATE UNIQUE INDEX "uq_tournament_event_tournament_type" ON "tournament_event"("tournament_id", "type");

-- CreateIndex
CREATE UNIQUE INDEX "uq_schedule_image_tournament_version" ON "schedule_image"("tournament_id", "version");

-- CreateIndex
CREATE INDEX "ix_audit_log_entity" ON "audit_log"("entity", "entity_id");

-- AddForeignKey
ALTER TABLE "account" ADD CONSTRAINT "fk_account_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tournament" ADD CONSTRAINT "fk_tournament_head_judge" FOREIGN KEY ("head_judge_id") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tournament_table" ADD CONSTRAINT "fk_tournament_table_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "category" ADD CONSTRAINT "fk_category_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "modality_gender" ADD CONSTRAINT "fk_modality_gender_modality" FOREIGN KEY ("modality_id") REFERENCES "modality"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "player" ADD CONSTRAINT "fk_player_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "participant" ADD CONSTRAINT "fk_participant_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "participant" ADD CONSTRAINT "fk_participant_category" FOREIGN KEY ("category_id") REFERENCES "category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "participant" ADD CONSTRAINT "fk_participant_modality" FOREIGN KEY ("modality_id") REFERENCES "modality"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "participant_player" ADD CONSTRAINT "fk_participant_player_participant" FOREIGN KEY ("participant_id") REFERENCES "participant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "participant_player" ADD CONSTRAINT "fk_participant_player_player" FOREIGN KEY ("player_id") REFERENCES "player"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tournament_group" ADD CONSTRAINT "fk_tournament_group_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tournament_group" ADD CONSTRAINT "fk_tournament_group_category" FOREIGN KEY ("category_id") REFERENCES "category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tournament_group" ADD CONSTRAINT "fk_tournament_group_modality" FOREIGN KEY ("modality_id") REFERENCES "modality"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bracket" ADD CONSTRAINT "fk_bracket_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bracket" ADD CONSTRAINT "fk_bracket_category" FOREIGN KEY ("category_id") REFERENCES "category"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bracket" ADD CONSTRAINT "fk_bracket_modality" FOREIGN KEY ("modality_id") REFERENCES "modality"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match" ADD CONSTRAINT "fk_match_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match" ADD CONSTRAINT "fk_match_group" FOREIGN KEY ("group_id") REFERENCES "tournament_group"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match" ADD CONSTRAINT "fk_match_bracket" FOREIGN KEY ("bracket_id") REFERENCES "bracket"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match" ADD CONSTRAINT "fk_match_table" FOREIGN KEY ("table_id") REFERENCES "tournament_table"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match" ADD CONSTRAINT "fk_match_referee" FOREIGN KEY ("referee_id") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match" ADD CONSTRAINT "fk_match_winner_participant" FOREIGN KEY ("winner_participant_id") REFERENCES "participant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match" ADD CONSTRAINT "fk_match_next_match" FOREIGN KEY ("next_match_id") REFERENCES "match"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match_participant" ADD CONSTRAINT "fk_match_participant_match" FOREIGN KEY ("match_id") REFERENCES "match"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match_participant" ADD CONSTRAINT "fk_match_participant_participant" FOREIGN KEY ("participant_id") REFERENCES "participant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "match_game" ADD CONSTRAINT "fk_match_game_match" FOREIGN KEY ("match_id") REFERENCES "match"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "podium" ADD CONSTRAINT "fk_podium_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "podium" ADD CONSTRAINT "fk_podium_category" FOREIGN KEY ("category_id") REFERENCES "category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "podium" ADD CONSTRAINT "fk_podium_modality" FOREIGN KEY ("modality_id") REFERENCES "modality"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "podium" ADD CONSTRAINT "fk_podium_participant" FOREIGN KEY ("participant_id") REFERENCES "participant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tournament_event" ADD CONSTRAINT "fk_tournament_event_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "schedule_image" ADD CONSTRAINT "fk_schedule_image_tournament" FOREIGN KEY ("tournament_id") REFERENCES "tournament"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_log" ADD CONSTRAINT "fk_audit_log_actor" FOREIGN KEY ("actor_account_id") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================================
-- Custom SQL #1 — CHECK constraints (ck_*), after all tables and FKs.
-- Prisma 7 cannot express CHECKs; the set of evolvable values (match states,
-- event types, gender conformations) lives as CHECK, never as a frozen enum
-- (spec HU033: additions become trivial ALTERs).
-- ============================================================================

-- account: role set and referee scoping
ALTER TABLE "account" ADD CONSTRAINT "ck_account_role" CHECK ("role" IN ('administrator', 'head_judge', 'referee'));
ALTER TABLE "account" ADD CONSTRAINT "ck_account_referee_tournament" CHECK ("role" <> 'referee' OR "tournament_id" IS NOT NULL);

-- tournament: format configuration (2 = best of 3, 3 = best of 5, 4 = best of 7)
ALTER TABLE "tournament" ADD CONSTRAINT "ck_tournament_games_to_win" CHECK ("games_to_win" IN (2, 3, 4));

-- tournament_table: numbering starts at 1
ALTER TABLE "tournament_table" ADD CONSTRAINT "ck_tournament_table_number" CHECK ("number" >= 1);

-- category/modality/participant: gender conformation vocabulary is evolvable (HU033)
ALTER TABLE "modality_gender" ADD CONSTRAINT "ck_modality_gender_conformation" CHECK ("conformation" IN ('damas', 'varones', 'mixta'));
ALTER TABLE "participant" ADD CONSTRAINT "ck_participant_conformation" CHECK ("conformation" IN ('damas', 'varones', 'mixta'));

-- player: optional import data; NULL stays allowed (worksheet may omit it)
ALTER TABLE "player" ADD CONSTRAINT "ck_player_gender" CHECK ("gender" IN ('femenino', 'masculino'));

-- tournament_group: letter of the group is 1–2 uppercase ASCII letters
-- (PostgreSQL LIKE has no character classes; SIMILAR TO does)
ALTER TABLE "tournament_group" ADD CONSTRAINT "ck_group_letter" CHECK ("group_letter" SIMILAR TO '[A-Z]' OR "group_letter" SIMILAR TO '[A-Z][A-Z]');

-- match: unified group/bracket matches — kind, state and kind↔link consistency
ALTER TABLE "match" ADD CONSTRAINT "ck_match_kind" CHECK ("kind" IN ('group', 'bracket'));
ALTER TABLE "match" ADD CONSTRAINT "ck_match_status" CHECK ("status" IN ('pendiente', 'en_curso', 'finalizado'));
ALTER TABLE "match" ADD CONSTRAINT "ck_match_group_kind" CHECK ("kind" <> 'group' OR "group_id" IS NOT NULL);
ALTER TABLE "match" ADD CONSTRAINT "ck_match_bracket_kind" CHECK ("kind" <> 'bracket' OR ("bracket_id" IS NOT NULL AND "round_no" IS NOT NULL));

-- match_participant: facing slots are exactly 1 or 2
ALTER TABLE "match_participant" ADD CONSTRAINT "ck_match_participant_slot" CHECK ("slot" IN (1, 2));

-- match_game: scoreboard sanity — winner strictly above loser, both non-negative
ALTER TABLE "match_game" ADD CONSTRAINT "ck_match_game_winner_slot" CHECK ("winner_slot" IN (1, 2));
ALTER TABLE "match_game" ADD CONSTRAINT "ck_match_game_points" CHECK ("winner_points" >= 0 AND "loser_points" >= 0 AND "winner_points" > "loser_points");

-- participant_player: roster slot in 1..5 (2 = doubles, 3–5 = teams; exact count in app)
ALTER TABLE "participant_player" ADD CONSTRAINT "ck_participant_player_slot" CHECK ("slot" BETWEEN 1 AND 5);

-- podium: official places 1..3 (3 only when a third place was activated — app protocol)
ALTER TABLE "podium" ADD CONSTRAINT "ck_podium_place" CHECK ("place" BETWEEN 1 AND 3);

-- tournament_event: the two seal/closure moment types; unique per tournament (uq_*)
ALTER TABLE "tournament_event" ADD CONSTRAINT "ck_tournament_event_type" CHECK ("type" IN ('publish_groups', 'close_tournament'));

-- ============================================================================
-- Custom SQL #2 — partial unique indexes (engine-level concurrency guards).
-- The guard covers the nullable column with its WHERE predicate; both indexes
-- go at the end together with the other indexes.
-- ============================================================================

-- One referee may not hold more than one non-finalized match (HU018)
CREATE UNIQUE INDEX "uq_match_referee_active" ON "match"("referee_id") WHERE "referee_id" IS NOT NULL AND "status" <> 'finalizado';

-- One table may not have two matches 'en_curso' at the same time (HU019)
CREATE UNIQUE INDEX "uq_match_table_active" ON "match"("table_id") WHERE "table_id" IS NOT NULL AND "status" = 'en_curso';

-- ============================================================================
-- Custom SQL #3 — partial lookup index for active participants (HU012):
-- rosters list and draw inputs filter on deleted_at IS NULL.
-- ============================================================================

CREATE INDEX "ix_participant_active" ON "participant"("tournament_id") WHERE "deleted_at" IS NULL;
