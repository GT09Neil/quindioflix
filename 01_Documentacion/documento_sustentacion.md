# Documento 10: Documento de Sustentación Técnica - QuindioFlix

Este documento fundamenta y justifica ante el cuerpo docente las decisiones arquitectónicas, el diseño físico y las estrategias de optimización aplicadas a la base de datos de QuindioFlix.

## 1. Estructura del Proyecto y Cumplimiento de Requerimientos

El proyecto se estructuró en 6 carpetas temáticas para aislar responsabilidades operativas y demostrar el dominio técnico de cada núcleo exigido en la rúbrica oficial (*Proyecto_QuindioFlix.pdf*). A continuación se desglosa el mapeo entre las carpetas y los requisitos:

### 📁 01_Documentacion
**Propósito:** Alojar los entregables teóricos y de justificación de diseño.
- **Cumplimiento:** Satisface el **Entregable 1** (Documento de modelo de negocio, actores, procesos, reglas de negocio y restricciones) y el **Entregable 10** (Este documento analítico de sustentación técnica, diseño y concurrencia).

### 📁 02_Modelo_Datos
**Propósito:** Definir la arquitectura base y el modelo físico en 3FN.
- **`quindioflix_tablespaces.sql`**: **Cumple con 3.1.5 (Fragmentación)**. Define contenedores físicos a nivel de disco, separando la data transaccional por rango de fechas (2024, 2025, 2026).
- **`quindioflix_ddl.sql`**: **Cumple con 2.4 (Modelo Físico)**. Contiene la creación de tablas, todos los constraints obligatorios (`CHECK`, `PK`, `FK`, `UNIQUE`), comentarios en diccionarios de datos y la declaración de `PARTITION BY RANGE` para la tabla `REPRODUCCIONES`.

### 📁 03_Logica_Negocio
**Propósito:** Agrupar la programación PL/SQL avanzada (**Núcleo 2 y Núcleo 3**).
- **`quindioflix_triggers.sql`**: **Cumple con 3.2.5 (Disparadores)**. Alberga los 4 triggers requeridos para lógicas pasivas: validación de cuenta activa antes de reproducir, límite máximo de perfiles por plan, regla estricta de calificación solo al superar 50% de avance, y actualización de estado de cuenta tras efectuar pagos exitosos.
- **`quindioflix_plsql.sql`**: **Cumple con 3.2.1, 3.2.2, 3.2.3 y 3.2.4**. Contiene 2 cursores explícitos (morosos y popularidad), 3 procedimientos dinámicos (registro, cambio de plan, reporte), 2 funciones (descuentos compuestos y motor de recomendación) y las excepciones definidas por usuario (`-20050`, `-20051`) manejadas mediante `PRAGMA`.
- **`quindioflix_transacciones.sql`**: **Cumple con 3.3.1 y 3.3.2**. Define 3 transacciones atómicas completas usando control manual de `COMMIT`/`ROLLBACK`, implementa bloqueos lógicos con `SAVEPOINT` en las rutinas de facturación, y documenta la demostración de concurrencia obligatoria usando la cláusula bloqueante `SELECT FOR UPDATE`.

### 📁 04_Consultas_y_Reportes
**Propósito:** Resolver los requerimientos de Inteligencia de Negocios y extracción masiva (**Núcleo 1 y Núcleo 4**).
- **`quindioflix_consultas.sql`**: **Cumple con todo el apartado 3.1 (Consultas avanzadas)**. Desarrolla 3 consultas interactivas con variables de sustitución, reportes de cruce multidimensional empleando tanto `PIVOT` como `UNPIVOT` (exigencia estricta), agrupaciones jerárquicas con funciones OLAP (`ROLLUP`, `CUBE`, `GROUPING SETS`), y el despliegue de 2 Vistas Materializadas.
- **`quindioflix_indices.sql`**: **Cumple con 3.4 (Índices y Análisis)**. Genera 4 índices para escenarios reales (búsquedas por correo, historial de perfiles compuesto) e incluye las notas de justificación sobre cómo reducen el Costo Total utilizando planes de ejecución.

### 📁 05_Seguridad
**Propósito:** Administrar la gobernanza, privilegios y protección de datos (**Núcleo 5**).
- **`quindioflix_seguridad.sql`**: **Cumple con 3.5.1 y 3.5.2**. Define el `PROFILE` que blinda a la base de datos limitando recursos (intentos fallidos, tiempo de inactividad, sesiones), crea el catálogo de roles (`ROL_ADMIN`, `ROL_ANALISTA`, `ROL_SOPORTE`, `ROL_CONTENIDO`) y vincula a los usuarios mediante instrucciones `GRANT`.

### 📁 06_Datos_Prueba
**Propósito:** Inyectar volumen masivo para garantizar que los reportes sean evaluables.
- **`quindioflix_dml.sql`**: **Cumple con 4 (Datos de Prueba)**. Sustituye la inserción manual clásica por un script asimétrico impulsado por paquetes como `DBMS_RANDOM` que garantiza volúmenes pesados (30 usuarios, 50 perfiles, 200 reproducciones, 80 pagos). Asegura que herramientas como el `CUBE` muestren diferencias reales de volumen y que la fragmentación en tablas opere dinámicamente poblando las particiones de los años correspondientes.

---

## 2. Justificación de Decisiones de Diseño y Normalización (3FN)
El modelo relacional fue diseñado desde cero garantizando el cumplimiento de la Tercera Forma Normal (3FN), eliminando de raíz las anomalías de inserción, actualización y borrado:
- **Ausencia de Dependencias Transitivas:** Ningún campo no-clave depende de otro campo no-clave. Por ejemplo, en lugar de guardar redundante la "Ciudad" en la tabla de facturación (`pagos`), el reporte financiero (`quindioflix_consultas.sql`) lee la ciudad cruzando a través del `id_usuario`, preservando la atomicidad.
- **Resolución Estructural Contenido vs. Episodio:** Un reto arquitectónico del streaming es unificar películas (sin capítulos) y series (con capítulos) sin poblar la tabla principal de valores `NULL`. La solución consistió en aislar las propiedades jerárquicas en las tablas `temporadas` y `episodios`, exigiendo mediante un Trigger (T1) que solo las Series tuvieran acceso a dicha jerarquía, mientras las películas se modelan de forma plana.
- **Tablas Puente Puristas:** Se diseñaron tablas intermedias puras como `contenido_genero` y `favoritos`. Al combinar dos Claves Foráneas (FK) como su Clave Primaria compuesta (PK), se descarta nativamente la duplicación de inserciones.

## 3. Estrategia de Índices y Análisis de Rendimiento (EXPLAIN PLAN)
En plataformas de streaming, la tabla de mayor congestión es `REPRODUCCIONES`. Debido a las exigencias de gerencia de auditar consumos filtrados por perfil y fechas de manera cronológica, se creó el índice `idx_repro_perfil_fecha` compuesto por `(id_perfil, fecha_inicio)`.

**Análisis de Optimización:**
* **Antes del Índice (`TABLE ACCESS FULL`)**: Al interrogar a Oracle por el historial mensual de un perfil sin el índice activo, el Optimizador Basado en Costos (CBO) generaba un plan de ejecución alarmante (e.g. `Cost: 600+`). El motor escaneaba a fuerza bruta todos los bloques físicos de la tabla, desperdiciando CPU e I/O en descartar filas inútiles.
* **Después del Índice (`INDEX RANGE SCAN`)**: Tras ejecutar el código disponible en la carpeta `04_Consultas_y_Reportes`, el B-Tree permite que el motor viaje instantáneamente a la rama del `id_perfil` solicitado y aplique un barrido de rango por la fecha. Concluye con un `TABLE ACCESS BY INDEX ROWID` directo al disco físico. Esta técnica desploma el costo de cómputo (e.g. `Cost: 4`), volviendo sostenible la reportería en tiempo real.

## 4. Escenario de Concurrencia de Datos (El problema de la Fila Sombra)
**Planteamiento del Escenario:**
Un usuario contacta telefónicamente exigiendo un Upgrade a "Plan Premium". Un *Agente A* abre la ficha en el sistema. Inmediatamente, la esposa del usuario contacta por chat pidiendo un cambio a "Plan Estándar", y el *Agente B* abre la misma ficha. Ambos leen en su pantalla: *Plan Básico*. Si no hubiese control de concurrencia transaccional, el agente que diera clic a guardar en segundo lugar sobreescribiría lo que hizo el primero, arruinando la facturación.

**La Solución Implementada (`SELECT ... FOR UPDATE`):**
Aplicamos cerrojos pesados a nivel de fila (Row-Level Locks).
- El *Agente A* inicia su transacción disparando: `SELECT id_plan FROM usuarios WHERE id_usuario = 15 FOR UPDATE;`
- Si el *Agente B* intenta emitir la misma sentencia simultáneamente, Oracle **congela** la sesión del Agente B en estado *Wait* porque reconoce que hay una transacción activa sin confirmar.
- Cuando el Agente A finaliza su factura y emite el `COMMIT`, el cerrojo se desvanece.
- Inmediatamente, la consulta encolada del Agente B se dispara, pero ahora Oracle le devuelve la foto actualizada (Plan Premium). El sistema del Agente B aborta lógicamente su cambio porque la versión que estaba editando ya es obsoleta.

## 5. Fragmentación Física de Datos (Tablespaces)
Acatando las normativas corporativas exigidas en el requerimiento *3.1.5*, decidimos fragmentar la tabla `REPRODUCCIONES` utilizando **Particionamiento por Rangos** (`PARTITION BY RANGE`). No solo particionamos la tabla lógica, sino que creamos contenedores físicos aislados en el disco (`TS_QUINDIOFLIX_2024`, `TS_QUINDIOFLIX_2025`).

**Justificación de Diseño Físico:**
1. **Reducción Abismal de Respaldo:** El tablespace del año anterior (2024) puede marcarse a nivel de base de datos como *Read-Only*. Al correr backups empresariales nocturnos, la herramienta RMAN omitirá respaldar este archivo pues tiene garantía de que no se ha modificado. Esto ahorra horas y terabytes.
2. **Purga Quirúrgica (Drop Partition):** Cuando la normativa exija destruir historiales viejos (ej. de hace 5 años), ejecutar un `DELETE FROM reproducciones WHERE año = 2020` demoraría horas en los *Logs de UNDO*. En contraste, Oracle nos permite ejecutar un simple DDL: `ALTER TABLE reproducciones DROP PARTITION p_2020;`. Esto simplemente destruye el puntero a los metadatos y en fracción de segundos purga millones de registros sin penalizar el rendimiento del servidor central.
