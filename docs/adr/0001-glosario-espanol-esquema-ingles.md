# Glosario en español, esquema de base de datos en inglés

El vocabulario de negocio del proyecto vive en español en `GLOSSARY.md`, que es la fuente de verdad del dominio, mientras que los identificadores del esquema de base de datos se escriben en inglés en `snake_case`. Seguimos así la convención db-design del repositorio: la base queda portable y legible internacionalmente sin que el equipo abandone el vocabulario con el que piensa y se comunica el dominio. La traducción término↔modelo se mantiene como correspondencia documentada.

## Considered Options

- **Esquema también en español**: descartada por la convención db-design del repositorio; rompería la consistencia con identificadores internacionales y obligaría a traducir nombre por nombre cada concepto en código, SQL y migraciones.

## Consequences

- Cada vez que el dominio cambie de vocabulario, la correspondencia glosario↔esquema debe quedar documentada en el mismo cambio; no se aceptan identificadores que no rinden cuenta en el glosario.
- Los mapas de Prisma (`@map`/`@@map`) mantienen la base de datos convencional en inglés `snake_case` mientras el modelo conserva el vocabulario del dominio; la doble escritura es deliberada y no debe "limpiarse" hacia un solo idioma.
