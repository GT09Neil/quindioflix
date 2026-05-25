-- =============================================================================
-- QUINDIOFLIX - ÍNDICES Y OPTIMIZACIÓN (Oracle SQL)
-- Núcleo 4: Elementos que influyen en la calidad
-- =============================================================================

-- 3.4.1 (a) Índice en REPRODUCCIONES
-- Justificación: Muy útil para generar reportes del historial de un perfil ordenado
-- cronológicamente, ya que a menudo se busca: WHERE id_perfil = X ORDER BY fecha_inicio DESC.
CREATE INDEX idx_repro_perfil_fecha ON reproducciones(id_perfil, fecha_inicio);

-- 3.4.1 (b) Índice en USUARIOS(email)
-- Justificación: Es la columna que se usa para el Login de los usuarios. Las búsquedas
-- por email son sumamente frecuentes. 
-- Nota: En nuestra tabla 'usuarios', el campo 'email' ya tiene una restricción 
-- CONSTRAINT uq_usuarios_email UNIQUE (email), la cual CREA AUTOMÁTICAMENTE un 
-- índice único en Oracle. Esta sentencia se incluye de manera demostrativa o para 
-- el caso donde la restricción Unique se creara apoyada en un índice preexistente.
-- CREATE UNIQUE INDEX idx_usuarios_email ON usuarios(email);

-- 3.4.1 (c) Índice en CONTENIDO
-- Justificación: Las búsquedas en el catálogo frecuentemente combinan filtros como:
-- "Mostrar películas (id_categoria=1) del año 2024". Este índice compuesto optimiza esto.
CREATE INDEX idx_contenido_cat_anio ON contenido(id_categoria, anio_lanzamiento);

-- 3.4.1 (d) Índice Adicional
-- Justificación: En la tabla PAGOS, los reportes financieros agrupan pagos por usuario
-- y rango de fechas. Un índice en el id_usuario y la fecha_pago permite que las 
-- sumatorias (SUM) con WHERE id_usuario = X y fecha_pago BETWEEN Y AND Z sean muy rápidas.
CREATE INDEX idx_pagos_usuario_fecha ON pagos(id_usuario, fecha_pago);

-- =============================================================================
-- 3.4.2 Análisis de Rendimiento (EXPLAIN PLAN)
-- =============================================================================
/*
-- ESCENARIO: Consultar las últimas reproducciones de un perfil en un mes específico.

-- ANTES DE CREAR EL ÍNDICE (idx_repro_perfil_fecha):
EXPLAIN PLAN FOR
SELECT id_reproduccion, id_contenido, id_episodio
  FROM reproducciones
 WHERE id_perfil = 150
   AND fecha_inicio >= TO_DATE('2026-01-01', 'YYYY-MM-DD');

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- El plan mostrará un "TABLE ACCESS FULL" sobre la tabla REPRODUCCIONES, ya que
-- tiene que escanear toda la tabla para encontrar el id_perfil y la fecha. 
-- El costo (Cost) será alto (ej. Cost: 500) y leerá todos los bloques de la tabla.

-- DESPUÉS DE CREAR EL ÍNDICE:
-- Al ejecutar el mismo EXPLAIN PLAN después de ejecutar CREATE INDEX idx_repro_perfil_fecha...
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- El plan ahora mostrará un "INDEX RANGE SCAN" utilizando 'IDX_REPRO_PERFIL_FECHA'.
-- El motor irá directamente al índice, buscará el id_perfil=150 y saltará a las 
-- fechas deseadas. Luego hará un "TABLE ACCESS BY INDEX ROWID". 
-- El costo bajará drásticamente (ej. Cost: 4), reduciendo I/O y CPU.
*/
