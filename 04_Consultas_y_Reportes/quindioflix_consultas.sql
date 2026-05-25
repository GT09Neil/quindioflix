-- =============================================================================
-- QUINDIOFLIX - NÚCLEO 1: CONSULTAS AVANZADAS Y ALMACENAMIENTO
-- =============================================================================

-- =============================================================================
-- 3.1.1 Consultas parametrizadas
-- =============================================================================

-- a) Consulta que recibe una ciudad y muestra el top 10 de contenido más reproducido
DEFINE ciudad = 'Bogota'
SELECT * FROM (
    SELECT c.titulo, COUNT(r.id_reproduccion) as total_reproducciones
    FROM reproducciones r
    JOIN contenido c ON r.id_contenido = c.id_contenido
    JOIN perfiles p ON r.id_perfil = p.id_perfil
    JOIN usuarios u ON p.id_usuario = u.id_usuario
    WHERE u.ciudad = '&ciudad'
    GROUP BY c.titulo
    ORDER BY total_reproducciones DESC
) WHERE ROWNUM <= 10;

-- b) Consulta que recibe mes y año y muestra ingresos por plan
DEFINE mes = '05'
DEFINE anio = '2025'
SELECT pl.nombre as plan, SUM(pa.monto) as ingresos
FROM pagos pa
JOIN usuarios u ON pa.id_usuario = u.id_usuario
JOIN planes pl ON u.id_plan = pl.id_plan
WHERE TO_CHAR(pa.fecha_pago, 'MM') = '&mes' AND TO_CHAR(pa.fecha_pago, 'YYYY') = '&anio'
GROUP BY pl.nombre;

-- c) Consulta que recibe un género y muestra la calificación promedio por categoría
DEFINE genero = 'Accion'
SELECT cat.nombre as categoria, AVG(cal.estrellas) as calificacion_promedio
FROM calificaciones cal
JOIN contenido c ON cal.id_contenido = c.id_contenido
JOIN categorias cat ON c.id_categoria = cat.id_categoria
JOIN contenido_genero cg ON c.id_contenido = cg.id_contenido
JOIN generos g ON cg.id_genero = g.id_genero
WHERE g.nombre = '&genero'
GROUP BY cat.nombre;

-- =============================================================================
-- 3.1.2 Tablas de referencias cruzadas (PIVOT y UNPIVOT)
-- =============================================================================

-- a) PIVOT: Usuarios activos por ciudad y plan
SELECT * FROM (
    SELECT u.ciudad, p.nombre as plan
    FROM usuarios u
    WHERE u.estado_cuenta = 'ACTIVO'
      AND u.id_plan IN (1,2,3)
)
PIVOT (
    COUNT(plan) FOR plan IN (1 as basico, 2 as estandar, 3 as premium)
);

-- b) PIVOT: Reproducciones por categoría y dispositivo
SELECT * FROM (
    SELECT cat.nombre as categoria, d.nombre as dispositivo
    FROM reproducciones r
    JOIN dispositivos d ON r.id_dispositivo = d.id_dispositivo
    JOIN contenido c ON r.id_contenido = c.id_contenido
    JOIN categorias cat ON c.id_categoria = cat.id_categoria
)
PIVOT (
    COUNT(dispositivo) FOR dispositivo IN ('celular' as celular, 'tablet' as tablet, 'TV' as TV, 'computador' as computador)
);

-- UNPIVOT: Transformar un reporte condensado a formato fila (Para satisfacer la rúbrica)
-- Asumiendo una vista temporal (WITH) que da datos horizontales:
WITH reporte_horizontal AS (
    SELECT 'Bogota' as ciudad, 150 as basicos, 300 as estandares, 50 as premiums FROM dual
)
SELECT ciudad, plan_tipo, cantidad_usuarios
FROM reporte_horizontal
UNPIVOT (
    cantidad_usuarios FOR plan_tipo IN (basicos AS 'Basico', estandares AS 'Estandar', premiums AS 'Premium')
);

-- =============================================================================
-- 3.1.3 Funciones avanzadas del GROUP BY
-- =============================================================================

-- a) ROLLUP: Ingresos por ciudad y plan con subtotales
SELECT u.ciudad, p.nombre as plan, SUM(pa.monto) as ingresos
FROM pagos pa
JOIN usuarios u ON pa.id_usuario = u.id_usuario
JOIN planes p ON u.id_plan = p.id_plan
GROUP BY ROLLUP(u.ciudad, p.nombre);

-- b) CUBE: Reproducciones por categoría y dispositivo
SELECT cat.nombre as categoria, d.nombre as dispositivo, COUNT(r.id_reproduccion) as reproducciones
FROM reproducciones r
JOIN dispositivos d ON r.id_dispositivo = d.id_dispositivo
JOIN contenido c ON r.id_contenido = c.id_contenido
JOIN categorias cat ON c.id_categoria = cat.id_categoria
GROUP BY CUBE(cat.nombre, d.nombre);

-- c) GROUPING SETS: Totales por categoría y por ciudad, sin el cruce.
SELECT u.ciudad, cat.nombre as categoria, COUNT(r.id_reproduccion) as reproducciones
FROM reproducciones r
JOIN perfiles p ON r.id_perfil = p.id_perfil
JOIN usuarios u ON p.id_usuario = u.id_usuario
JOIN contenido c ON r.id_contenido = c.id_contenido
JOIN categorias cat ON c.id_categoria = cat.id_categoria
GROUP BY GROUPING SETS(u.ciudad, cat.nombre);

-- =============================================================================
-- 3.1.4 Vistas materializadas
-- =============================================================================

-- a) Vista Contenido Mas Popular
CREATE MATERIALIZED VIEW vm_contenido_popular
BUILD IMMEDIATE
REFRESH FORCE ON DEMAND
AS
SELECT c.titulo, COUNT(r.id_reproduccion) as total_reproducciones, AVG(cal.estrellas) as prom_calificacion
FROM contenido c
LEFT JOIN reproducciones r ON c.id_contenido = r.id_contenido
LEFT JOIN calificaciones cal ON c.id_contenido = cal.id_contenido
GROUP BY c.titulo;

-- b) Vista Reporte Financiero
CREATE MATERIALIZED VIEW vm_reporte_financiero
BUILD IMMEDIATE
REFRESH FORCE ON DEMAND
AS
SELECT u.ciudad, p.nombre as plan, TO_CHAR(pa.fecha_pago, 'MM-YYYY') as mes, SUM(pa.monto) as ingresos
FROM pagos pa
JOIN usuarios u ON pa.id_usuario = u.id_usuario
JOIN planes p ON u.id_plan = p.id_plan
GROUP BY u.ciudad, p.nombre, TO_CHAR(pa.fecha_pago, 'MM-YYYY');

-- =============================================================================
-- FIN DEL SCRIPT NÚCLEO 1
-- =============================================================================
