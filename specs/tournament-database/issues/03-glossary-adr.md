# 03 — Glosario (4 términos nuevos) + ADR 0001

Status: resolved
Type: task
Blocked by: —

## Resumen

Registrar en `GLOSSARY.md` los términos surgidos del diseño de la base de datos y crear el primer ADR documentando la decisión lingüística del esquema.

## Fuentes normativas (context pointers)

- Spec: `specs/tournament-database/spec.md` — Further Notes (lista los términos y el ADR).
- Formato ADR: `.agents/skills/domain-modeling/ADR-FORMAT.md`.
- Formato glosario: `.agents/skills/domain-modeling/GLOSSARY-FORMAT.md` (el glosario se queda sin detalles de implementación).

## Contenido

1. Añadir a `GLOSSARY.md` (vocabulario de negocio, sin esquema): **Configuración del torneo** (el formato "mejor de X" que el juez fija al crear el torneo), **Match en llave** (partido que pertenece al bracket; el ganador avanza al match siguiente declarado), **Slot de enfrentados** (orden 1/2 con que un participante figura en un match), **Clasificados por grupo** (cantidad que avanza de cada grupo a la llave).
2. Crear `docs/adr/0001-glosario-espanol-esquema-ingles.md`: decisión — el glosario/vocabulario de negocio queda en español (fuente de verdad del dominio) y los identificadores del esquema de base de datos en inglés snake_case; contexto (convención db-design, portabilidad, correspondencia término↔modelo); alternativas (esquema en español) y por qué se descartó; consecuencias (necesidad de correspondencia documentada; @map mantiene la BD convencional).

## Aceptación

- Los 4 términos existen en el glosario con la forma del doc y sin detalles técnicos de esquema.
- ADR 0001 en `docs/adr/` con formato del template.
