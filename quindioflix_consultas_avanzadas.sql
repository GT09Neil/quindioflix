-- =============================================================================
-- QUINDIOFLIX — COMPONENTE D / NÚCLEO 1
-- Consultas avanzadas, vistas materializadas y particionamiento (Oracle SQL)
-- =============================================================================
-- Prerrequisitos:
--   - Ejecutar antes: quindioflix_ddl.sql, quindioflix_triggers.sql,
--     quindioflix_inserts.sql (u otro juego de datos coherente).
--   - Las consultas parametrizadas (sección 1) están pensadas para SQL*Plus
--     o SQLcl (sustitución & / && / DEFINE). En SQL Developer, activar
--     "Define Substitution Variables" o ejecutar esas sentencias ahí.
--
-- Advertencia (sección 5 — particionamiento):
--   - Renombra REPRODUCCIONES, crea la tabla particionada, copia datos y
--     recrea el trigger trg_repro_perfil_infantil. Requiere CREATE TABLESPACE
--     (suele ser DBA). Ajuste rutas/nombres de DATAFILE según su instalación.
--   - La sección 6 (vistas materializadas) debe ir después de la 5 si ejecuta
--     el script completo; si solo necesita MV sobre tabla no particionada,
--     ejecute las secciones 1–4 y luego la 6 omitiendo la 5.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) CONSULTAS PARAMETRIZADAS (mínimo 3) — &, &&, DEFINE / ACCEPT
-- -----------------------------------------------------------------------------
-- Activar sustitución de variables (SQL*Plus / SQLcl).
SET DEFINE ON;
SET VERIFY OFF;

-- 1a) DEFINE + sustitución simple (&): usuarios filtrados por ciudad.
DEFINE v_ciudad = Armenia

SELECT u.id_usuario,
       u.nombre,
       u.email,
       pl.nombre AS plan_nombre
  FROM usuarios u
  JOIN planes pl ON pl.id_plan = u.id_plan
 WHERE u.ciudad = '&v_ciudad'
 ORDER BY u.id_usuario;

-- 1b) ACCEPT (sustitución &) con prompt interactivo: contenido por categoría.
ACCEPT p_categoria CHAR PROMPT 'Nombre categoria (Peliculas|Series|Documentales|Musica|Podcasts): '

SELECT co.id_contenido,
       co.titulo,
       co.anio_lanzamiento,
       ca.nombre AS categoria
  FROM contenido co
  JOIN categorias ca ON ca.id_categoria = co.id_categoria
 WHERE ca.nombre = '&p_categoria'
 ORDER BY co.titulo;

-- 1c) && (define implícito persistente en la sesión) + umbral numérico:
--     calificaciones con promedio de estrellas >= umbral por contenido.
DEFINE v_min_promedio = 4

SELECT co.id_contenido,
       co.titulo,
       ROUND(AVG(cal.estrellas), 2) AS promedio_estrellas,
       COUNT(*) AS num_calificaciones
  FROM calificaciones cal
  JOIN contenido co ON co.id_contenido = cal.id_contenido
 GROUP BY co.id_contenido, co.titulo
HAVING AVG(cal.estrellas) >= &&v_min_promedio
 ORDER BY promedio_estrellas DESC;

SET VERIFY ON;

-- -----------------------------------------------------------------------------
-- 2) TABLAS DE REFERENCIA CRUZADA — PIVOT (mínimo 2)
-- -----------------------------------------------------------------------------

-- 2a) Reproducciones por tipo de dispositivo (filas) y plan de suscripción (columnas).
SELECT *
  FROM (
        SELECT pl.nombre AS plan_nombre,
               d.nombre  AS dispositivo,
               r.id_reproduccion
          FROM reproducciones r
          JOIN perfiles   pf ON pf.id_perfil = r.id_perfil
          JOIN usuarios    u ON u.id_usuario = pf.id_usuario
          JOIN planes     pl ON pl.id_plan = u.id_plan
          JOIN dispositivos d ON d.id_dispositivo = r.id_dispositivo
       )
 PIVOT (
        COUNT(id_reproduccion)
        FOR plan_nombre IN ('Basico'    AS plan_basico,
                            'Estandar'  AS plan_estandar,
                            'Premium'   AS plan_premium)
       )
 ORDER BY dispositivo;

-- 2b) Cantidad de calificaciones por categoría de contenido y por valor de estrellas (1–5).
SELECT *
  FROM (
        SELECT ca.nombre AS categoria,
               cal.estrellas
          FROM calificaciones cal
          JOIN contenido  co ON co.id_contenido = cal.id_contenido
          JOIN categorias ca ON ca.id_categoria = co.id_categoria
       )
 PIVOT (
        COUNT(estrellas)
        FOR estrellas IN (1 AS s1, 2 AS s2, 3 AS s3, 4 AS s4, 5 AS s5)
       )
 ORDER BY categoria;

-- -----------------------------------------------------------------------------
-- 3) TABLAS DE REFERENCIA CRUZADA — UNPIVOT (mínimo 2)
-- -----------------------------------------------------------------------------

-- 3a) Métricas de cada plan en formato largo (una fila por métrica).
SELECT id_plan,
       nombre AS plan_nombre,
       metrica,
       valor
  FROM planes
 UNPIVOT (
          valor FOR metrica IN (precio             AS 'Precio_mensual_COP',
                                  cantidad_pantallas AS 'Pantallas_simultaneas',
                                  max_perfiles       AS 'Max_perfiles')
         )
 ORDER BY id_plan, metrica;

-- 3b) Conteo de usuarios por ciudad desnormalizado → formato largo (plan × ciudad).
WITH base AS (
    SELECT u.ciudad,
           SUM(CASE WHEN pl.nombre = 'Basico'   THEN 1 ELSE 0 END) AS cnt_basico,
           SUM(CASE WHEN pl.nombre = 'Estandar' THEN 1 ELSE 0 END) AS cnt_estandar,
           SUM(CASE WHEN pl.nombre = 'Premium'  THEN 1 ELSE 0 END) AS cnt_premium
      FROM usuarios u
      JOIN planes pl ON pl.id_plan = u.id_plan
     WHERE u.ciudad IS NOT NULL
     GROUP BY u.ciudad
)
SELECT ciudad,
       plan_nombre,
       num_usuarios
  FROM base
 UNPIVOT (
          num_usuarios FOR plan_nombre IN (cnt_basico   AS 'Basico',
                                            cnt_estandar AS 'Estandar',
                                            cnt_premium  AS 'Premium')
         )
 ORDER BY ciudad, plan_nombre;

-- -----------------------------------------------------------------------------
-- 4) FUNCIONES AVANZADAS DE AGRUPACIÓN (mínimo 4 consultas)
--    ROLLUP, CUBE, GROUPING(), GROUPING SETS
-- -----------------------------------------------------------------------------

-- 4a) ROLLUP: totales parciales por plan y ciudad.
SELECT pl.nombre AS plan_nombre,
       u.ciudad,
       COUNT(*) AS num_usuarios
  FROM usuarios u
  JOIN planes pl ON pl.id_plan = u.id_plan
 GROUP BY ROLLUP (pl.nombre, u.ciudad)
 ORDER BY plan_nombre NULLS LAST, ciudad NULLS LAST;

-- 4b) CUBE: todas las combinaciones de ciudad de usuario y categoría consumida
--     (vía reproducciones de contenido directo).
SELECT u.ciudad,
       ca.nombre AS categoria,
       COUNT(DISTINCT r.id_reproduccion) AS reproducciones
  FROM reproducciones r
  JOIN perfiles   pf ON pf.id_perfil = r.id_perfil
  JOIN usuarios    u ON u.id_usuario = pf.id_usuario
  JOIN contenido  co ON co.id_contenido = r.id_contenido
  JOIN categorias ca ON ca.id_categoria = co.id_categoria
 WHERE r.id_contenido IS NOT NULL
 GROUP BY CUBE (u.ciudad, ca.nombre)
 ORDER BY u.ciudad NULLS LAST, categoria NULLS LAST;

-- 4c) ROLLUP + GROUPING(): banderas por fila (detalle, subtotal por plan, total general).
SELECT pl.nombre AS plan_nombre,
       u.ciudad,
       COUNT(*) AS num_usuarios,
       GROUPING(pl.nombre) AS g_plan,
       GROUPING(u.ciudad) AS g_ciudad
  FROM usuarios u
  JOIN planes pl ON pl.id_plan = u.id_plan
 GROUP BY ROLLUP (pl.nombre, u.ciudad)
 ORDER BY plan_nombre NULLS LAST, ciudad NULLS LAST;

-- 4d) GROUPING SETS: agregados por conjuntos de dimensiones explícitos.
SELECT u.ciudad,
       pl.nombre AS plan_nombre,
       COUNT(*) AS num_usuarios
  FROM usuarios u
  JOIN planes pl ON pl.id_plan = u.id_plan
 GROUP BY GROUPING SETS ((u.ciudad), (pl.nombre), ())
 ORDER BY u.ciudad NULLS LAST, plan_nombre NULLS LAST;

-- -----------------------------------------------------------------------------
-- 5) FRAGMENTACIÓN (PARTICIONAMIENTO) DE REPRODUCCIONES POR RANGO DE FECHAS
-- -----------------------------------------------------------------------------
-- JUSTIFICACIÓN (requerimiento académico):
--   La tabla REPRODUCCIONES es de alto volumen y crecimiento continuo (eventos
--   con marca de tiempo fecha_inicio). Particionar por RANGO sobre fecha_inicio
--   permite:
--     (1) Partición por eliminación: archivar o purgar rangos antiguos sin
--         escanear toda la tabla.
--     (2) Mejor localidad de E/S: consultas recientes leen menos bloques si el
--         optimizador aplica partition pruning.
--     (3) Administración: TABLESPACES separados permiten ubicar histórico en
--         discos más económicos y el tráfico reciente en almacenamiento más
--         rápido, según política del DBA.
--   Los límites (2025, 2026, 2027, MAXVALUE) son ejemplos docentes; en producción
--   se calibrarían con INTERVAL partitioning o más particiones según volumen.
-- -----------------------------------------------------------------------------
-- NOTA: Requiere privilegio CREATE TABLESPACE. Ajuste las rutas de DATAFILE.
--       Si DB_CREATE_FILE_DEST está definido, un nombre simple 'archivo.dbf'
--       suele resolverse en ese directorio.
-- -----------------------------------------------------------------------------

CREATE TABLESPACE ts_qf_repro_hist
  DATAFILE 'qf_repro_hist.dbf' SIZE 64M AUTOEXTEND ON NEXT 16M MAXSIZE 2G
  EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO;

CREATE TABLESPACE ts_qf_repro_2025
  DATAFILE 'qf_repro_2025.dbf' SIZE 64M AUTOEXTEND ON NEXT 16M MAXSIZE 2G
  EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO;

CREATE TABLESPACE ts_qf_repro_2026
  DATAFILE 'qf_repro_2026.dbf' SIZE 64M AUTOEXTEND ON NEXT 16M MAXSIZE 2G
  EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO;

CREATE TABLESPACE ts_qf_repro_future
  DATAFILE 'qf_repro_future.dbf' SIZE 64M AUTOEXTEND ON NEXT 16M MAXSIZE UNLIMITED
  EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO;

-- Trigger existente (debe quitarse antes de renombrar/sustituir la tabla).
DROP TRIGGER trg_repro_perfil_infantil;

ALTER TABLE reproducciones RENAME TO reproducciones_heap_bak;

CREATE TABLE reproducciones (
    id_reproduccion     NUMBER GENERATED ALWAYS AS IDENTITY,
    id_perfil           NUMBER          NOT NULL,
    id_contenido        NUMBER,
    id_episodio         NUMBER,
    id_dispositivo      NUMBER          NOT NULL,
    fecha_inicio        TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
    fecha_fin           TIMESTAMP,
    porcentaje_avance   NUMBER(5,2)     DEFAULT 0 NOT NULL,
    CONSTRAINT pk_reproducciones            PRIMARY KEY (id_reproduccion),
    CONSTRAINT fk_repro_perfil              FOREIGN KEY (id_perfil)
        REFERENCES perfiles (id_perfil) ON DELETE CASCADE,
    CONSTRAINT fk_repro_contenido           FOREIGN KEY (id_contenido)
        REFERENCES contenido (id_contenido),
    CONSTRAINT fk_repro_episodio            FOREIGN KEY (id_episodio)
        REFERENCES episodios (id_episodio),
    CONSTRAINT fk_repro_dispositivo         FOREIGN KEY (id_dispositivo)
        REFERENCES dispositivos (id_dispositivo),
    CONSTRAINT ck_repro_contenido_xor_ep    CHECK (
        (id_contenido IS NOT NULL AND id_episodio IS NULL)
        OR
        (id_contenido IS NULL AND id_episodio IS NOT NULL)
    ),
    CONSTRAINT ck_repro_porcentaje          CHECK (porcentaje_avance BETWEEN 0 AND 100),
    CONSTRAINT ck_repro_fechas              CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
)
PARTITION BY RANGE (fecha_inicio) (
    PARTITION p_before_2025 VALUES LESS THAN (TIMESTAMP '2025-01-01 00:00:00')
        TABLESPACE ts_qf_repro_hist,
    PARTITION p_2025 VALUES LESS THAN (TIMESTAMP '2026-01-01 00:00:00')
        TABLESPACE ts_qf_repro_2025,
    PARTITION p_2026 VALUES LESS THAN (TIMESTAMP '2027-01-01 00:00:00')
        TABLESPACE ts_qf_repro_2026,
    PARTITION p_future VALUES LESS THAN (MAXVALUE)
        TABLESPACE ts_qf_repro_future
);

COMMENT ON TABLE reproducciones IS
'Reproducciones particionadas por rango de fecha_inicio (Componente D).';

INSERT INTO reproducciones (
    id_perfil, id_contenido, id_episodio, id_dispositivo,
    fecha_inicio, fecha_fin, porcentaje_avance
)
SELECT id_perfil, id_contenido, id_episodio, id_dispositivo,
       fecha_inicio, fecha_fin, porcentaje_avance
  FROM reproducciones_heap_bak;

DROP TABLE reproducciones_heap_bak;

CREATE OR REPLACE TRIGGER trg_repro_perfil_infantil
BEFORE INSERT OR UPDATE ON reproducciones
FOR EACH ROW
DECLARE
    v_tipo_perfil       VARCHAR2(10);
    v_clasificacion     VARCHAR2(5);
BEGIN
    SELECT tipo
      INTO v_tipo_perfil
      FROM perfiles
     WHERE id_perfil = :NEW.id_perfil;

    IF v_tipo_perfil = 'infantil' THEN

        IF :NEW.id_contenido IS NOT NULL THEN
            SELECT clasificacion_edad
              INTO v_clasificacion
              FROM contenido
             WHERE id_contenido = :NEW.id_contenido;

        ELSIF :NEW.id_episodio IS NOT NULL THEN
            SELECT co.clasificacion_edad
              INTO v_clasificacion
              FROM contenido co
              JOIN temporadas t ON t.id_contenido = co.id_contenido
              JOIN episodios  e ON e.id_temporada = t.id_temporada
             WHERE e.id_episodio = :NEW.id_episodio;
        END IF;

        IF v_clasificacion NOT IN ('TP', '+7', '+13') THEN
            RAISE_APPLICATION_ERROR(
                -20020,
                'Error [T3]: Perfil infantil (id_perfil = ' || :NEW.id_perfil
                || ') no puede reproducir contenido con clasificación '
                || v_clasificacion || '. Solo se permite TP, +7, +13.'
            );
        END IF;

    END IF;
END trg_repro_perfil_infantil;
/

-- -----------------------------------------------------------------------------
-- 6) VISTAS MATERIALIZADAS (mínimo 2)
-- -----------------------------------------------------------------------------
-- Debe ejecutarse después de la sección 5: renombrar REPRODUCCIONES invalidaría
-- cualquier MV creada antes sobre ese nombre.
-- Refresco bajo demanda (COMPLETE). Ejemplo tras nuevas cargas:
--   EXEC DBMS_MVIEW.REFRESH('MV_QF_REPRO_MES_DISPOSITIVO','C');

BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_qf_repro_mes_dispositivo';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -12003 THEN RAISE; END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_qf_contenido_calif_resumen';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -12003 THEN RAISE; END IF;
END;
/

CREATE MATERIALIZED VIEW mv_qf_repro_mes_dispositivo
  BUILD IMMEDIATE
  REFRESH COMPLETE ON DEMAND
AS
SELECT TRUNC(r.fecha_inicio, 'MM') AS mes_inicio,
       d.nombre                    AS dispositivo,
       COUNT(*)                    AS total_reproducciones,
       ROUND(AVG(r.porcentaje_avance), 2) AS avance_promedio
  FROM reproducciones r
  JOIN dispositivos d ON d.id_dispositivo = r.id_dispositivo
 GROUP BY TRUNC(r.fecha_inicio, 'MM'), d.nombre;

COMMENT ON MATERIALIZED VIEW mv_qf_repro_mes_dispositivo IS
'Resumen de reproducciones por mes natural y dispositivo (Componente D).';

CREATE MATERIALIZED VIEW mv_qf_contenido_calif_resumen
  BUILD IMMEDIATE
  REFRESH COMPLETE ON DEMAND
AS
SELECT co.id_contenido,
       co.titulo,
       ca.nombre AS categoria,
       COUNT(cal.id_perfil) AS num_calificaciones,
       ROUND(AVG(cal.estrellas), 2) AS estrellas_promedio,
       MIN(cal.fecha) AS primera_calificacion,
       MAX(cal.fecha) AS ultima_calificacion
  FROM contenido co
  JOIN categorias    ca  ON ca.id_categoria = co.id_categoria
  LEFT JOIN calificaciones cal ON cal.id_contenido = co.id_contenido
 GROUP BY co.id_contenido, co.titulo, ca.nombre;

COMMENT ON MATERIALIZED VIEW mv_qf_contenido_calif_resumen IS
'Agregado de calificaciones por título/categoría para informes (Componente D).';

COMMIT;
