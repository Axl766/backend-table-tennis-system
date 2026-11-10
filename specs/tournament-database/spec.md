# Espec: Base de datos del sistema de torneos de tenis de mesa

Status: ready-for-agent

## Problem Statement

El equipo del proyecto final necesita empezar a construir la plataforma web que digitaliza el ciclo del torneo de tenis de mesa (inscripción de participantes, grupos y cruces, mesas y cola, arbitraje y resultados, llaves finales y podios). Hoy el repositorio está en fase cero: hay dependencias instaladas (Prisma 7, express, socket.io) pero ningún esquema de base de datos, ningún modelo y ninguna migración. Sin una fuente única de verdad de datos persistente, ninguna de las 25 historias de usuario del Capítulo I puede iniciarse, y el rastro del proceso (sorteo auditable, correcciones con auditación, podios consolidados) no tiene dóndevivir.

## Solution

Crear la capa de datos completa del producto: un esquema de base de datos relacional en Prisma 7 sobre PostgreSQL, entregado como modelo versionado con su migración inicial aplicada (`init_tournament_management`). El esquema modela el dominio definido en `GLOSSARY.md` y en las historias de usuario del Capítulo I: cuentas con los tres perfiles (administrador, juez general, árbitro), torneos con su configuración de formato, catálogos de categorías y modalidades, participantes importados desde planillas, fase de grupos con cruces, control de mesas y cola, arbitraje con asignaciones, resultados jugo a juego, llaves finales con avance automático, podios, eventos de competencia, cronograma anexado y registro de auditación.

## User Stories

1. Como administrador, quiero que las cuentas ytengan roles diferenciados (administrador, juez general, árbitro), para que cada perfil solo alcance sus propios datos.
2. Como administrador, quiero que las cuentas se puedan desactivar sin borrarse, para que el historial y las auditorías conserven quién hizo qué.
3. Como juez general, quiero tener una cuenta propia sobre la que recaen mis torneos, para que la propiedad de cada torneoquede explícita y consultable.
4. Como juez general, quiero dos torneos míos con el mismo nombre no puedan existir, para evitar confusiones entre eventos.
5. Como juez general, quiero que cada torneo lleve su configuración de formato (juegos necesarios para ganar: mejor de 3/5/7), para no repetir la regla en cada partido.
6. Como juez general, quiero catálogos de categoríasbase (IV07–IV19, rangos adultos, TC) disponible para todo torneo, para no recargarla cada vez.
7. Como juez general, quiero registrar categorías adicionales que solo me pertenezcan a mi torneo, para ajustar el certamen al club organizador.
8. Como juez general, quiero las modalidades con sus conformaciones de género (individuales: Damas/Varones; dobles: Damas/Varones/Mixta; equipos: Damas/Varones) afirmadas en catálogo, para que la importación las valide contra reglas reales.
9. Como juez general, quiero que los participantes de mi torneo (jugador suelto, pareja o equipo) me den las inscripciones con su categoría, modalidad y conformación, para consolidar las fichas en una sola fuente.
10. Como juez general, quiero que parejas y equipos lleven su roster con el orden de sus integrantes (2 para dobles, 3–5 para equipos), para que el sorteo y los resultados identifiquen a quién corresponde cada posición.
11. Como juez general, quiero que un jugador disputar simultáneamente individuales, dobles y equipos dentro del mismo torneo, para respetar la práctica real del club.
12. Como juez general, quiero que la baja de un participante antes del sellado sea recuperable (baja lógica), para poder revertir errores de carga.
13. Como juez general, quiero que después de publicar la fase de grupos los participantes no sean prescindibles libremente, para que el sorteo quede íntegro.
14. Como juez general, quiero los cruces estén agrupados por categoría, modalidad y conformación con letra de grupo (A, B…), para que el tablero muestre cada rama de manera inequívoca.
15. Como juez general, quiero que los partidos referencien de forma explícitosus dos enfrentados con su orden (slot 1/2), para que las tablas de cruces y llaves no dependan de texto armado a mano.
16. Como juez general, quiero listar las mesas de mi torneo con número único, para que el tablero didáctico de mesas sea inubicable.
17. Como juez general, quiero reasignar un partido a otra mesa o reordenarlo en su cola, para priorizar la programación durante el campeonato.
18. Como árbitro, quiero que la base impida que yo tenga más de un partido no finalizado simultáneamente, para que nunca me asignen dos partidas activas a la vez.
19. Como árbitro, quiero que la base impida dos partidos concurrentes en la misma mesa, para que la cola de mesa sea confiable.
20. Como árbitro, quiero registrar el marcador juego por juego (puntos de ganador y perdedor repetidos por game), para que la tabla de posiciones calcule ganados, razón de games y razón de puntos con datos reales.
21. Como árbitro, quiero que la base rechace un game con puntaje empatado o negativo, para que no entren basura en posiciones.
22. Como árbitro, quiero finalizar el partido y que el ganador quede fijado en la fila del partido, para que el avance de la llave y las posiciones no se recalculen a mano.
23. Como juez general, quiero un registro de auditación de todas las correcciones y reprogramaciones (quién, cuándo, valor anterior y nuevo, en JSONB), para que el sorteo y los resultados queden auditables.
24. Como juez general,quiero generar la llave final con la cantidad de clasificados por grupo y marcar si habrá tercer puesto, para configurar el cierre sin recurrir a hojas aparte.
25. Como juez general, quiero que el avance del ganador en la llave quede expresado como referencia declarada al partido siguiente, para que el avance automático sea auditable.
26. Como juez general, quiero que el bye sea un partido con un enfrentado ausente (participante NULL), para que se muestre explícito en la llave.
27. Como juez general, quiero publicar la fase de grupos como un evento fechado y único por torneo, para que el sellado tenga evidencia temporal.
28. Como juez general, quiero cerrar el torneo como otro evento único y consolidar los podios por rama (1°–3°), para llenar los resultados finales sin mezclar con el historial.
29. Como espectador, quiero que la vista pública consulte la misma base (grupos, posiciones, partidos, llaves y podios) sin tablas replicadas, para ver la competencia en vivo sin datos divergentes.
30. Como juez general, quiero anexar el cronograma como imagen versionada del torneo, para compartir el programa del día sin abandonar el sistema.
31. Como desarrollador, quiero identificadores en inglés (snake_case en la base vía mapas), para que el esquema sea portable y legible internacionalmente sin perder el vocabulario del glosario.
32. Como desarrollador, quiero claves primarias UUIDv7 (excepto extractivas internas de auditoría), para que los identificadores no se enumeren y la insercción no fragmente índices.
33. Como desarrollador, quiero que los conjuntos evolutivos (estados de partido, tipos de evento, equipos del roster) vivan como CHECK en migración SQL y no como enums congelados, para agregar valiosos con ALTERs triviales.
34. Como desarrollador, quiero fechas de creación/actualización en todo table de neugocios, para mantener trazabilidad temporal uniforme.
35. Como desarrollador, quiero migraciones versionadas revisadas contra el motor real (nunca `db push` sobre base compartida), para evolucionar el esquema sin deriva.

## Implementation Decisions

- **Alcance**: solo capa de datos (modelo Prisma 7 + migración inicial versionada). API, servicios, Zod/DTOs, seeds y seeds de datos están explícitamente fuera de alcance ( reporting el desvío si ocurre).
- **Motor y tooling**: PostgreSQL con adapter de driver ya instalado (`@prisma/adapter-pg`); Prisma 7 con generator `prisma-client` y salida generada importable; gestor de paquetes pnpm (lockfile existente). El `DATABASE_URL` lo aporta el usuario.
- **Identificadores**: en inglés, `PascalCase` para modelos y `camelCase` para campos; identificadores de base en `snake_case` singular vía `@map`/`@@map`; constraints nombrados explícitamente (`uq_*`, `ix_*`, `fk_*`, `ck_*`). El glosario queda en español: la correspondencia glosario↔esquema se registra en un ADR (0001).
- **Claves**: PK UUIDv7 (uuid nativo, generada app-side con `@default(uuid(7))`) en todas las tablas de negocio; escape hatch justificado: PK BIGINT secuencial solo en el log de auditación (tabla interna de alto volumen polimórfica, sin exposición). Sin claves naturales en `account` ni `player`: la unicidad la cubre el surrogate; la prevención de duplicados de jugadores vive en la validación de la importación (aplicación). `UNIQUE(head_judge_id, name)` en cualquier; `UNIQUE(code)` global + `UNIQUE(tournament_id, code)` en categoría; `UNIQUE(tournament_id, number)` en mesa; `UNIQUE(match_id, game_no)` en games; la natural de grupo incluye la letra del grupo: `UNIQUE(tournament_id, category_id, modality_id, conformation, group_letter)` en grupo (`tournament_group`); en llave (`bracket`) la natural es `UNIQUE(tournament_id, category_id, modality_id, conformation)` — sin letra, una sola llave por rama; `UNIQUE(modality.name)` en el catálogo de modalidades (`uq_modality_name`); `UNIQUE(tournament_id, category_id, modality_id, conformation, place)` en podium; `UNIQUE(tournament_id, type)` en eventos de competencia; `UNIQUE(tournament_id, version)` en cronograma (`schedule_image`); PK compuesta `(participant_id, player_id)` en roster y `(match_id, slot)` en enfrentados. Uniques con miembros nulables se resuelven en la migración SQL (`UNIQUE ... NULLS NOT DISTINCT`), nunca dejadas implícitas.
- **Modelo de entidades** (18 tablas; la contabilidad original omitía la mesa del torneo, `tournament_table`): `account` (rol con CHECK; árbitro con `tournament_id` NOT NULL), `tournament` (con `games_to_win` CHECK ∈ {2,3,4} — mejor de 3/5/7; puntos 11 con diferencia de 2 es regla de aplicación, no de base), `category` (catálogo global base + adicionales por torneo con `tournament_id` nulo), `modality` + `modality_gender` (junction compuesta que pide campañas de genero por modalidad), `player` (por torneo: `full_name` obligatorio, género y edad complementarias), `participant` (inscripto por torneo+modalidad+categoría+conformación; baja lógica `deleted_at` solo previa al sellado; los participantes entran siempre por importación, Excel o PDF), `participant_player` (roster con `slot`; la obligación de 2/3–5 integrantes se defiende en aplicación), `group` (rama + letra de grupo, natural única), `match` (partidos de fase de grupos y de llave unificados: `kind`, estado `pendiente`/`en_curso`/`finalizado` con CHECK, `table_id` Restrict, `queue_position`, `referee_id`, `winner_participant_id`, `next_match_id` autoreferenciado, `bye` como participante-faltante, `is_third_place` marcado), `match_participant` (slot 1/2 con CHECK), `match_game` (puntos por game; CHECK ganador > perdedor, ambos ≥ 0), `bracket` (llave por rama: `classified_per_group`, `has_third_place`), `podium` (cierre: puestos 1°–3° por rama), `tournament_event` (`publish_groups`/`close_tournament`, snapshot JSONB), `audit_log` (quién, cuándo, `entity`+`entity_id` polimórfico sin FK, `old_value`/`new_value` JSONB), `schedule_image` (cronograma anexado, versiones apiladas).
- **Integridad y concurrencia** (protección a nivel del motor, no solo aplicación): índice único parcial que impide a un árbitro tener más de un partido NO finalizado; índice único parcial que impide dos partidos `en_curso` en la misma mesa; CHECKs de consistencia (`kind='bracket'` ⇒ `bracket_id` y `round_no` presentes); `ON DELETE` explícito por FK (Restrict en relaciones de competencia sellada: torneo, mesa, participantes, resultados; Cascade en dependencias estructurales: roster, games, bracket; SetNull no se usa). El sellado (no editar participantes tras publicar) y la regla de diferencia de 2 en el game se aplican en código de aplicación; queda documentado como protocolo de runtime en la defensa de trade-offs — sin triggers en modo Prisma.
- **Timestamps**: `created_at`/`updated_at` Timestamptz explícito en todas las tablas de negocio (`@default(now())` y `@updatedAt`, mantenidas por la aplicación — una sola mechanism per target).
- **Índices**: B-Tree sobre toda FK usada en consultas y sobre columnas de filtrado caliente (partidos por estado por mesa, cola por mesa, participantes activos con índice parcial `WHERE deleted_at IS NULL`).
- **Decisiones del review (2026-11-09)**: los bytes del cronograma se persisten en la base para el MVP (`schedule_image.image_data` como BYTEA) con versiones apiladas por torneo vía `uq_schedule_image_tournament_version`; los CHECKs adicionales de integridad que exija la revisión quedan dentro del alcance "CHECKs de consistencia" ya declarado en este spec.
- **Denormalización**: ninguna. Posiciones, desempates (PG → razón de games → razón de puntos → enfrentamiento directo) y clasificados se calculan en runtime; la vista pública consulta las mismas tablas vía eventos en socket.io.

## Testing Decisions

- **Gate manual (decisión del usuario, sin tests automatizados)**: la verificación es un gate de aplicación, no una suite: (1) `prisma validate` + `prisma format` sin errores; (2) la migración inicial se aplica con `prisma migrate dev` contra la base real señalada en `DATABASE_URL`; (3) el SQL generado se revisa integralmente (CHECKs e índices parciales añadidos como SQL custom) y se contrasta contra el motor — `prisma migrate diff` como respaldo si no hay base desechable disponible.
- Qué hace un buen gate: la migración aplicaDe primera sobre una base PostgreSQL real del motor de la versión objetivo, y el SQL final coincide con el esquema declarado (sin deriva).
- No se escribirán pruebas de repositorio ni código de consulta: el seam de pruebas futuro para la aplicación será el esquema ya migrado, no este entregable.

## Out of Scope

- API HTTP, rutas, controladores, middleware, servicios, validación Zod/DTOs y contratos REST (siguiente esfuerzo, con su propia skill).
- Código de consulta contra el cliente generado (Prisma Client), seeds y datos de demostración.
- El parser de importación de Excel/PDF y sus reglas de negocio de duplicados (vive en la capa de aplicación; la base modela sus resultados).
- Cálculo de posiciones/desempates, generación del sorteo y avance de llaves (lógica de aplicación sobre estas tablas).
- Vista pública en tiempo real (socket.io) y su frontend.

## Further Notes

- Fuente de dominio: `GLOSSARY.md` (normativo para el vocabulario) y el último documento modificado del proyecto, `Capitulo_I_Producto_Digital.docx` (HU001–HU025), en la carpeta `docs` del proyecto final.
- El glosario se mantiene en español y el esquema en inglés; crear **ADR 0001** documentando esa correspondencia al implementar.
- Términos nuevos surgidos en el diseño y a registrar en `GLOSSARY.md`: *configuración del torneo* (mejor de X), *match en llave*, *slot de enfrentados*, *clasificados por grupo*.
- Prisma 7 no expresa CHECK ni índices parciales en el esquema: nacen como SQL custom editado dentro del directorio de la migración antes de aplicarla.
- Nunca `prisma db push` contra la base del usuario; la evolución posterior va por migraciones versionadas.
