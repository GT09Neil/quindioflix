-- =============================================================================
-- QUINDIOFLIX - FRAGMENTACIÓN Y TABLESPACES (Oracle SQL)
-- Núcleo 1: Administración de componentes fundamentales
-- =============================================================================

-- 3.1.5 Fragmentación de tablas — tablespaces y datafiles
-- Justificación de particionamiento: La tabla REPRODUCCIONES es la tabla transaccional
-- de mayor crecimiento. Al fragmentarla por rango de fechas (años), logramos:
-- 1. Mejor rendimiento: Consultas por año escanean solo su partición correspondiente.
-- 2. Facilidad de respaldo: Los años anteriores (ej. 2024) pueden ponerse en modo 
--    Read-Only para acelerar el backup.
-- 3. Purga eficiente: Cuando se necesite borrar data histórica de hace 5 años, se puede 
--    hacer un DROP PARTITION (instantáneo) en vez de un DELETE masivo.

-- Creación de tablespaces usando configuración por defecto de almacenamiento 
-- de Oracle Database para la gestión de datafiles.
CREATE TABLESPACE TS_QUINDIOFLIX_2024
DATAFILE 'qflix_2024_01.dbf' SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

CREATE TABLESPACE TS_QUINDIOFLIX_2025
DATAFILE 'qflix_2025_01.dbf' SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

CREATE TABLESPACE TS_QUINDIOFLIX_2026
DATAFILE 'qflix_2026_01.dbf' SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

CREATE TABLESPACE TS_QUINDIOFLIX_MAX
DATAFILE 'qflix_max_01.dbf' SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

-- NOTA: Estos tablespaces se utilizarán en el particionamiento (PARTITION BY RANGE)
-- de la tabla REPRODUCCIONES en el script quindioflix_ddl.sql
