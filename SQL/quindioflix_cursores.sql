-- =============================================================================
-- SECCIÓN 2: CURSORES EXPLÍCITOS
-- =============================================================================
 
-- -----------------------------------------------------------------------------
-- CURSOR 1: USUARIOS MOROSOS
-- Identifica usuarios cuyo último pago fue rechazado o llevan más de 30 días
-- sin ningún pago aprobado (es decir, la suscripción está vencida).
-- Se ejecuta como bloque anónimo demostrable; en producción puede encapsularse
-- dentro de un procedimiento de cobranza.
-- -----------------------------------------------------------------------------
DECLARE
    -- Tipo de registro para almacenar la información del usuario moroso
    TYPE t_usuario_moroso IS RECORD (
        id_usuario      usuarios.id_usuario%TYPE,
        nombre          usuarios.nombre%TYPE,
        email           usuarios.email%TYPE,
        plan_actual     planes.nombre%TYPE,
        ultimo_pago     DATE,
        estado_pago     pagos.estado%TYPE,
        dias_vencido    NUMBER
    );
 
    v_usuario   t_usuario_moroso;
    v_contador  NUMBER := 0;
 
    -- Cursor explícito: usuarios con suscripción vencida o con pago rechazado
    CURSOR cur_usuarios_morosos IS
        SELECT
            u.id_usuario,
            u.nombre,
            u.email,
            p.nombre                        AS plan_actual,
            MAX(pg.fecha_pago)              AS ultimo_pago,
            MAX(pg.estado) KEEP (DENSE_RANK LAST ORDER BY pg.fecha_pago) AS estado_pago,
            TRUNC(SYSDATE - MAX(pg.fecha_pago)) AS dias_vencido
        FROM usuarios u
        JOIN planes p    ON p.id_plan   = u.id_plan
        LEFT JOIN pagos pg ON pg.id_usuario = u.id_usuario
        GROUP BY u.id_usuario, u.nombre, u.email, p.nombre
        HAVING
            -- Sin ningún pago aprobado en los últimos 30 días
            MAX(CASE WHEN pg.estado = 'aprobado' THEN pg.fecha_pago END) < SYSDATE - 30
            OR
            -- Último pago con estado rechazado
            MAX(pg.estado) KEEP (DENSE_RANK LAST ORDER BY pg.fecha_pago) = 'rechazado'
            OR
            -- Nunca realizaron un pago
            MAX(pg.fecha_pago) IS NULL
        ORDER BY dias_vencido DESC NULLS LAST;
 
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== REPORTE DE USUARIOS MOROSOS ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('ID', 6) || RPAD('NOMBRE', 30) || RPAD('EMAIL', 35)
                         || RPAD('PLAN', 12) || RPAD('ÚLTIMO PAGO', 14)
                         || RPAD('ESTADO', 12) || 'DÍAS VENCIDO');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 115, '-'));
 
    OPEN cur_usuarios_morosos;
    LOOP
        FETCH cur_usuarios_morosos INTO v_usuario;
        EXIT WHEN cur_usuarios_morosos%NOTFOUND;
 
        v_contador := v_contador + 1;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_usuario.id_usuario, 6)
            || RPAD(v_usuario.nombre, 30)
            || RPAD(v_usuario.email, 35)
            || RPAD(v_usuario.plan_actual, 12)
            || RPAD(NVL(TO_CHAR(v_usuario.ultimo_pago, 'DD/MM/YYYY'), 'N/A'), 14)
            || RPAD(NVL(v_usuario.estado_pago, 'Sin pago'), 12)
            || NVL(TO_CHAR(v_usuario.dias_vencido), 'N/A')
        );
    END LOOP;
    CLOSE cur_usuarios_morosos;
 
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 115, '-'));
    DBMS_OUTPUT.PUT_LINE('Total usuarios morosos: ' || v_contador);
END;
/
 
 
-- -----------------------------------------------------------------------------
-- CURSOR 2: CÁLCULO DE POPULARIDAD DE CONTENIDO
-- Popularidad = ponderación de: reproducciones (peso 40%), calificaciones (30%),
-- favoritos (20%) y reportes negativos (penalización 10%).
-- Normalizado en una escala de 0 a 100.
-- -----------------------------------------------------------------------------
DECLARE
    TYPE t_popularidad IS RECORD (
        id_contenido        contenido.id_contenido%TYPE,
        titulo              contenido.titulo%TYPE,
        categoria           categorias.nombre%TYPE,
        total_reproducciones NUMBER,
        promedio_estrellas   NUMBER,
        total_favoritos      NUMBER,
        total_reportes       NUMBER,
        score_popularidad    NUMBER
    );
 
    v_item          t_popularidad;
    v_contador      NUMBER := 0;
 
    -- Subquery con métricas crudas por contenido
    CURSOR cur_popularidad IS
        WITH metricas AS (
            SELECT
                c.id_contenido,
                c.titulo,
                cat.nombre                          AS categoria,
                COUNT(DISTINCT r.id_reproduccion)   AS total_rep,
                ROUND(AVG(cal.estrellas), 2)         AS avg_stars,
                COUNT(DISTINCT f.id_perfil)          AS total_fav,
                COUNT(DISTINCT rpt.id_reporte)       AS total_rep_neg
            FROM contenido c
            JOIN categorias cat ON cat.id_categoria = c.id_categoria
            LEFT JOIN reproducciones r
                ON r.id_contenido = c.id_contenido
            LEFT JOIN calificaciones cal
                ON cal.id_contenido = c.id_contenido
            LEFT JOIN favoritos f
                ON f.id_contenido = c.id_contenido
            LEFT JOIN reportes rpt
                ON rpt.id_contenido = c.id_contenido
               AND rpt.estado NOT IN ('rechazado')
            GROUP BY c.id_contenido, c.titulo, cat.nombre
        ),
        maximos AS (
            SELECT
                MAX(total_rep)      AS max_rep,
                MAX(avg_stars)      AS max_stars,
                MAX(total_fav)      AS max_fav,
                MAX(total_rep_neg)  AS max_rep_neg
            FROM metricas
        )
        SELECT
            m.id_contenido,
            m.titulo,
            m.categoria,
            m.total_rep,
            NVL(m.avg_stars, 0)    AS avg_stars,
            m.total_fav,
            m.total_rep_neg,
            ROUND(
                -- Reproducciones: 40%
                (CASE WHEN mx.max_rep > 0    THEN (m.total_rep     / mx.max_rep)    ELSE 0 END * 40)
                -- Calificaciones: 30%
              + (CASE WHEN mx.max_stars > 0  THEN (NVL(m.avg_stars,0) / mx.max_stars) ELSE 0 END * 30)
                -- Favoritos: 20%
              + (CASE WHEN mx.max_fav > 0    THEN (m.total_fav     / mx.max_fav)    ELSE 0 END * 20)
                -- Penalización reportes: -10%
              - (CASE WHEN mx.max_rep_neg > 0 THEN (m.total_rep_neg / mx.max_rep_neg) ELSE 0 END * 10),
            2) AS score_popularidad
        FROM metricas m
        CROSS JOIN maximos mx
        ORDER BY score_popularidad DESC;
 
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ÍNDICE DE POPULARIDAD DE CONTENIDO ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('ID', 6) || RPAD('TÍTULO', 40) || RPAD('CATEGORÍA', 15)
                         || RPAD('REPROD.', 9) || RPAD('ESTRELLAS', 11)
                         || RPAD('FAVORITOS', 11) || RPAD('REPORTES', 10) || 'SCORE');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 110, '-'));
 
    OPEN cur_popularidad;
    LOOP
        FETCH cur_popularidad INTO v_item;
        EXIT WHEN cur_popularidad%NOTFOUND;
 
        v_contador := v_contador + 1;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_item.id_contenido, 6)
            || RPAD(SUBSTR(v_item.titulo, 1, 38), 40)
            || RPAD(v_item.categoria, 15)
            || RPAD(v_item.total_reproducciones, 9)
            || RPAD(NVL(TO_CHAR(v_item.promedio_estrellas), '0'), 11)
            || RPAD(v_item.total_favoritos, 11)
            || RPAD(v_item.total_reportes, 10)
            || v_item.score_popularidad
        );
    END LOOP;
    CLOSE cur_popularidad;
 
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 110, '-'));
    DBMS_OUTPUT.PUT_LINE('Contenidos evaluados: ' || v_contador);
END;