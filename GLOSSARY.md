# Gestión y control de torneos de tenis de mesa

Contexto único del producto: plataforma web para gestionar torneos de tenis de mesa, desde la carga de inscriptos hasta los podios del cierre. Vocabulario derivado del Capítulo I del proyecto final.

## Language

### Perfiles

**Administrador**:
Responsable de crear las cuentas de jueces generales. Único perfil sobre el cual no existe vía de creación en la plataforma.
_Avoid_: superusuario, root.

**Juez general**:
Organizador con derechos sobre sus torneos: crea torneos, gestiona participantes, grupos, mesas, árbitros y llaves, y ejecuta el cierre.
_Avoid_: organizador (en la plataforma, el organizador es siempre el juez general).

**Árbitro**:
Perfil por torneo (no global) que dirige los partidos que le asignan y registra sus resultados. Autenticado con usuario y clave definida por el juez general.
_Avoid_: árbitro de mesa (sinónimo coloquial), referee.

### Competencia

**Torneo**:
Competencia creada por un juez general. No tiene etapas de estado: se gestiona desde su dashboard; solo existen eventos de la competencia (publicar fase de grupos, cerrar torneo).
_Avoid_: campeonato (colocar solo en contexto de difusión), evento.

**Participante**:
Inscripto en un torneo: jugador individual, pareja o equipo según la modalidad.
_Avoid_: inscripción (es el acta, no la persona).

**Jugador**:
Persona inscrita. Puede disputar simultáneamente individuales, dobles y equipos dentro del mismo torneo.

**Pareja**:
Dúo de la modalidad dobles: dos jugadoras (Damas), dos jugadores (Varones) o un varón y una dama (Mixta).

**Equipo**:
Conjunto de 3 a 5 integrantes que compite en la modalidad equipos.

**Categoría**:
División de edad/nivel del catálogo del tenis de mesa: IV07–IV19 (IV varones / ID damas), rangos adultos de 20-29 a 80+, y Tercera Categoría (TC), más las adicionales del torneo.

**Modalidad**:
Tipo de juego disputado: individuales, dobles o equipos.

**Conformación de género**:
Rama por la que disputa una inscripción: Damas, Varones o Mixta (solo dobles). La pareja mixta se inscribe con el código de categoría elegido para la pareja (p. ej., IV17), independiente de las categorías individuales de sus integrantes, y no crea una rama nueva en el catálogo.

### Fase de grupos

**Fase de grupos**:
Etapa posterior a la carga de participantes en la que se disputan partidos dentro de grupos por categoría, género y modalidad.

**Cruce**:
Enfrentamiento entre dos participantes del mismo grupo. La tabla de cruces es la lista de todos los enfrentamientos del grupo.
_Avoid_: matchup, cruce de grupos (reservado para el emparejamiento de la llave).

**Publicar la fase de grupos**:
Acontecimiento por el que el juez general sella el sorteo: queda auditable, los participantes dejan de editarse y los partidos de grupo pasan a programarse.
_Avoid_: activar, iniciar.

**Sellado**:
Estado de los datos (participantes, cruces) que ya no admiten edición libre; correcciones solo por el flujo con auditación.

### Programación y arbitraje

**Cola de mesa**:
Orden de partidos asignados a una mesa. No hay horarios digitados: cada mesa juega su cola en orden.
_Avoid_: cronograma (el cronograma es la imagen anexada, HU015), agenda.

**Reprogramación**:
Mover o reordenar un partido dentro de su cola, o a otra mesa, antes de que inicie. Queda auditada.

**Tablero didáctico de mesas**:
Vista SVG en vivo: por cada mesa, el partido en curso, jugadores, árbitro de turno y avance de la cola.
_Avoid_: mapa de mesas, dashboard de mesas (el dashboard es el conjunto general de pestañas).

**Estado del árbitro**:
Disponible o asignado, calculado por sus asignaciones de partidos activos. Un árbitro no puede tener partidos activos en dos mesas a la vez.

### Resultados y llaves

**Partido finalizado**:
Partido cuyo resultado completo fue registrado; determina ganador automáticamente y libera la cola de su mesa.

**Desempate**:
Orden de la tabla de posiciones: más PG → mayor razón de games → mayor razón de puntos → enfrentamiento directo.

**Llave final**:
Bracket de eliminación generado con los clasificados de la fase de grupos, por rondas.
_Avoid_: llave final única (la llave también admite bye y tercer puesto).

**Bye**:
Avance directo de un clasificado cuando la cantidad no completa la primera ronda. Se muestra explícito en la llave.

**Cerrar el torneo**:
Acción del juez general que consolida los podios por categoría y modalidad y llena la pestaña de resultados finales. Es una acción, no un estado de la plataforma.
_Avoid_: finalizar (rondas), expirar.

**Podio**:
Conjunto oficial de primeros puestos (1°, 2° y 3°, este solo si el juez lo activó) consolidado en el cierre.

**Auditación**:
Registro obligatorio de las correcciones y reprogramaciones: quién, cuándo y cuál era el valor anterior.
_Avoid_: log (en el glosario de negocio).

### Vista pública

**Vista pública**:
Consulta en vivo, sin autenticación, de grupos, posiciones, partidos, llaves y podios (HU025). Solo lectura; no expone datos personales adicionales a los ya difundidos.
_Avoid_: pantalla pública, modo espectador.
