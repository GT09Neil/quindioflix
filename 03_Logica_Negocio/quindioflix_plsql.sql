-- =============================================================================
-- QUINDIOFLIX - PL/SQL: CURSORES, PROCEDIMIENTOS, FUNCIONES Y EXCEPCIONES
-- Núcleo 2: Procedimientos almacenados y disparadores
-- =============================================================================

-- =============================================================================
-- 3.2.1 (a) Cursor: Suscripciones Vencidas
-- =============================================================================
CREATE OR REPLACE PROCEDURE rep_suscripciones_vencidas AS
    CURSOR c_morosos IS
        SELECT u.nombre, u.email, p.nombre as plan_nombre, 
               TRUNC(SYSDATE - (u.fecha_ultimo_pago + 30)) as dias_mora,
               p.precio as monto_adeudado
        FROM usuarios u
        JOIN planes p ON u.id_plan = p.id_plan
        WHERE u.estado_cuenta != 'ACTIVO' OR SYSDATE > (u.fecha_ultimo_pago + 30);
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- REPORTE DE SUSCRIPCIONES VENCIDAS ---');
    FOR r IN c_morosos LOOP
        DBMS_OUTPUT.PUT_LINE('Usuario: ' || r.nombre || ' | Email: ' || r.email || 
                             ' | Plan: ' || r.plan_nombre || ' | Días de mora: ' || 
                             r.dias_mora || ' | Deuda: $' || r.monto_adeudado);
    END LOOP;
END;
/

-- =============================================================================
-- 3.2.1 (b) Cursor: Popularidad del Catálogo (>= 90%)
-- =============================================================================
CREATE OR REPLACE PROCEDURE actualizar_popularidad AS
    CURSOR c_contenido IS
        SELECT c.id_contenido, COUNT(r.id_reproduccion) as repros_completas
        FROM contenido c
        LEFT JOIN reproducciones r ON r.id_contenido = c.id_contenido 
                                   OR r.id_episodio IN (SELECT e.id_episodio FROM episodios e JOIN temporadas t ON e.id_temporada = t.id_temporada WHERE t.id_contenido = c.id_contenido)
        WHERE r.porcentaje_avance >= 90
        GROUP BY c.id_contenido;
BEGIN
    FOR r IN c_contenido LOOP
        UPDATE contenido 
        SET popularidad = r.repros_completas
        WHERE id_contenido = r.id_contenido;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Popularidad del catálogo actualizada con éxito.');
END;
/

-- =============================================================================
-- 3.2.2 (a) y 3.2.4 (a) Procedimiento: Registrar Usuario con Excepciones
-- =============================================================================
CREATE OR REPLACE PROCEDURE sp_registrar_usuario (
    p_nombre       IN VARCHAR2,
    p_email        IN VARCHAR2,
    p_fecha_nac    IN DATE,
    p_id_plan      IN NUMBER
) AS
    v_count NUMBER;
    v_id_usuario NUMBER;
    v_precio NUMBER;
    -- Excepción personalizada para email duplicado
    ex_email_duplicado EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_email_duplicado, -20050);
BEGIN
    -- 1. Validar que el plan exista (Provocará NO_DATA_FOUND si no existe)
    SELECT precio INTO v_precio FROM planes WHERE id_plan = p_id_plan;

    -- 2. Validar email duplicado
    SELECT COUNT(*) INTO v_count FROM usuarios WHERE email = p_email;
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20050, 'Error: El correo electrónico ya está registrado.');
    END IF;

    -- 3. Crear usuario
    INSERT INTO usuarios (id_plan, id_rol, nombre, email, fecha_nacimiento, estado_cuenta)
    VALUES (p_id_plan, 1, p_nombre, p_email, p_fecha_nac, 'INACTIVO')
    RETURNING id_usuario INTO v_id_usuario;

    -- 4. Crear perfil base
    INSERT INTO perfiles (id_usuario, nombre, tipo)
    VALUES (v_id_usuario, 'Perfil Principal', 'adulto');

    -- 5. Registrar primer pago
    INSERT INTO pagos (id_usuario, monto, metodo_pago, estado)
    VALUES (v_id_usuario, v_precio, 'tarjeta_credito', 'aprobado');
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Usuario registrado exitosamente.');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: El plan seleccionado no existe.');
        ROLLBACK;
    WHEN ex_email_duplicado THEN
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
        ROLLBACK;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error general: ' || SQLERRM);
        ROLLBACK;
END;
/

-- =============================================================================
-- 3.2.2 (b) y 3.2.4 (b) Procedimiento: Cambiar Plan
-- =============================================================================
CREATE OR REPLACE PROCEDURE sp_cambiar_plan (
    p_id_usuario IN NUMBER,
    p_nuevo_plan IN NUMBER
) AS
    v_perfiles_actuales NUMBER;
    v_max_perfiles_nuevo NUMBER;
    ex_exceso_perfiles EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_exceso_perfiles, -20051);
BEGIN
    -- Contar perfiles actuales del usuario
    SELECT COUNT(*) INTO v_perfiles_actuales FROM perfiles WHERE id_usuario = p_id_usuario;
    
    -- Obtener máximo permitido en el nuevo plan
    SELECT max_perfiles INTO v_max_perfiles_nuevo FROM planes WHERE id_plan = p_nuevo_plan;
    
    IF v_perfiles_actuales > v_max_perfiles_nuevo THEN
        RAISE_APPLICATION_ERROR(-20051, 'Error: No puede bajar a un plan de ' || v_max_perfiles_nuevo || ' perfiles porque actualmente tiene ' || v_perfiles_actuales || '.');
    END IF;
    
    UPDATE usuarios SET id_plan = p_nuevo_plan WHERE id_usuario = p_id_usuario;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Plan cambiado exitosamente.');
EXCEPTION
    WHEN ex_exceso_perfiles THEN
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
        ROLLBACK;
END;
/

-- =============================================================================
-- 3.2.2 (c) Procedimiento: Reporte Consumo
-- =============================================================================
CREATE OR REPLACE PROCEDURE sp_reporte_consumo (
    p_id_usuario IN NUMBER,
    p_fecha_ini IN DATE,
    p_fecha_fin IN DATE
) AS
    CURSOR c_reporte IS
        SELECT p.nombre as perfil, cat.nombre as categoria, SUM(r.porcentaje_avance) as tiempo_simulado
        FROM reproducciones r
        JOIN perfiles p ON r.id_perfil = p.id_perfil
        LEFT JOIN contenido c ON r.id_contenido = c.id_contenido
        LEFT JOIN episodios e ON r.id_episodio = e.id_episodio
        LEFT JOIN temporadas t ON e.id_temporada = t.id_temporada
        LEFT JOIN contenido c2 ON t.id_contenido = c2.id_contenido
        JOIN categorias cat ON cat.id_categoria = NVL(c.id_categoria, c2.id_categoria)
        WHERE p.id_usuario = p_id_usuario
          AND CAST(r.fecha_inicio AS DATE) BETWEEN p_fecha_ini AND p_fecha_fin
        GROUP BY p.nombre, cat.nombre;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- REPORTE DE CONSUMO ---');
    FOR r IN c_reporte LOOP
        DBMS_OUTPUT.PUT_LINE('Perfil: ' || r.perfil || ' | Cat: ' || r.categoria || ' | Tiempo relativo consumido: ' || r.tiempo_simulado);
    END LOOP;
END;
/

-- =============================================================================
-- 3.2.3 (a) Función: Calcular Monto (Considerando reglas de negocio)
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_calcular_monto (
    p_id_usuario IN NUMBER
) RETURN NUMBER AS
    v_meses_antiguedad NUMBER;
    v_precio_base NUMBER;
    v_referidos NUMBER;
    v_monto_final NUMBER;
BEGIN
    -- Obtener meses de antigüedad y precio base
    SELECT MONTHS_BETWEEN(SYSDATE, u.fecha_registro), p.precio
      INTO v_meses_antiguedad, v_precio_base
      FROM usuarios u
      JOIN planes p ON u.id_plan = p.id_plan
     WHERE u.id_usuario = p_id_usuario;
     
    -- Descuentos por antigüedad
    IF v_meses_antiguedad > 24 THEN
        v_monto_final := v_precio_base * 0.85; -- 15% desc
    ELSIF v_meses_antiguedad > 12 THEN
        v_monto_final := v_precio_base * 0.90; -- 10% desc
    ELSE
        v_monto_final := v_precio_base;
    END IF;
    
    -- Regla 1.5: Descuento si tiene referido activo (asumiremos $5000 fijos de descuento acumulable)
    SELECT COUNT(*) INTO v_referidos FROM usuarios WHERE usuario_referente = p_id_usuario AND estado_cuenta = 'ACTIVO';
    IF v_referidos > 0 THEN
        v_monto_final := v_monto_final - 5000;
        IF v_monto_final < 0 THEN v_monto_final := 0; END IF;
    END IF;
    
    RETURN v_monto_final;
END;
/

-- =============================================================================
-- 3.2.3 (b) Función: Contenido Recomendado
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_contenido_recomendado (
    p_id_perfil IN NUMBER
) RETURN VARCHAR2 AS
    v_titulo VARCHAR2(300);
BEGIN
    -- Busca el contenido con más popularidad que comparta el género más visto por el perfil
    SELECT c.titulo INTO v_titulo
    FROM contenido c
    JOIN contenido_genero cg ON c.id_contenido = cg.id_contenido
    WHERE cg.id_genero = (
        SELECT id_genero FROM (
            SELECT cg2.id_genero, COUNT(*) 
            FROM reproducciones r
            JOIN contenido c2 ON r.id_contenido = c2.id_contenido
            JOIN contenido_genero cg2 ON c2.id_contenido = cg2.id_contenido
            WHERE r.id_perfil = p_id_perfil
            GROUP BY cg2.id_genero
            ORDER BY COUNT(*) DESC
        ) WHERE ROWNUM = 1
    )
    ORDER BY c.popularidad DESC
    FETCH FIRST 1 ROWS ONLY;
    
    RETURN v_titulo;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'Ninguna recomendación (falta de datos)';
END;
/
