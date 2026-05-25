-- =============================================================================
-- QUINDIOFLIX - TRANSACCIONES Y CONCURRENCIA (Oracle SQL)
-- Núcleo 3: Administración de componentes fundamentales
-- =============================================================================

-- =============================================================================
-- 3.3.1 (a) Transacción de registro completo
-- =============================================================================
-- Crear usuario + perfil + primer pago.
-- Todo o nada (COMMIT al final, ROLLBACK si falla algo).
CREATE OR REPLACE PROCEDURE sp_registro_completo (
    p_id_plan             IN NUMBER,
    p_id_rol              IN NUMBER,
    p_nombre_usuario      IN VARCHAR2,
    p_email               IN VARCHAR2,
    p_fecha_nacimiento    IN DATE,
    p_nombre_perfil       IN VARCHAR2,
    p_tipo_perfil         IN VARCHAR2,
    p_monto_pago          IN NUMBER,
    p_metodo_pago         IN VARCHAR2
) AS
    v_id_usuario NUMBER;
BEGIN
    -- Inicia transacción implícitamente

    -- 1. Crear Usuario
    INSERT INTO usuarios (id_plan, id_rol, nombre, email, fecha_nacimiento, estado_cuenta)
    VALUES (p_id_plan, p_id_rol, p_nombre_usuario, p_email, p_fecha_nacimiento, 'INACTIVO')
    RETURNING id_usuario INTO v_id_usuario;

    -- 2. Crear Perfil Principal
    INSERT INTO perfiles (id_usuario, nombre, tipo)
    VALUES (v_id_usuario, p_nombre_perfil, p_tipo_perfil);

    -- 3. Registrar Primer Pago (Activa el usuario vía Trigger T7)
    INSERT INTO pagos (id_usuario, monto, metodo_pago, estado)
    VALUES (v_id_usuario, p_monto_pago, p_metodo_pago, 'aprobado');

    -- Confirmar transacción
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Registro completo exitoso. Usuario ID: ' || v_id_usuario);

EXCEPTION
    WHEN OTHERS THEN
        -- Revertir toda la transacción si falla cualquier paso
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error en el registro. Transacción abortada. Detalle: ' || SQLERRM);
END sp_registro_completo;
/

-- =============================================================================
-- 3.3.1 (b) Transacción de renovación mensual
-- =============================================================================
-- Renovar pago para todos los usuarios activos. Usando SAVEPOINT.
CREATE OR REPLACE PROCEDURE sp_renovacion_mensual AS
    CURSOR c_usuarios IS
        SELECT u.id_usuario, p.precio
        FROM usuarios u
        JOIN planes p ON u.id_plan = p.id_plan
        WHERE u.estado_cuenta = 'ACTIVO';
    
    v_procesados NUMBER := 0;
    v_fallidos   NUMBER := 0;
BEGIN
    FOR r_usuario IN c_usuarios LOOP
        -- Establecer un SAVEPOINT para cada iteración de usuario
        SAVEPOINT sp_inicio_renovacion;
        
        BEGIN
            -- Insertar el pago mensual (aprobado automáticamente para el ejemplo)
            INSERT INTO pagos (id_usuario, monto, metodo_pago, estado)
            VALUES (r_usuario.id_usuario, r_usuario.precio, 'tarjeta_credito', 'aprobado');
            
            v_procesados := v_procesados + 1;
        EXCEPTION
            WHEN OTHERS THEN
                -- Si este pago en específico falla, revertir solo este usuario
                ROLLBACK TO sp_inicio_renovacion;
                v_fallidos := v_fallidos + 1;
                DBMS_OUTPUT.PUT_LINE('Fallo al renovar usuario ID ' || r_usuario.id_usuario || ': ' || SQLERRM);
        END;
    END LOOP;
    
    -- Confirmar los que sí fueron exitosos
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Renovación finalizada. Procesados: ' || v_procesados || ', Fallidos: ' || v_fallidos);
END sp_renovacion_mensual;
/

-- =============================================================================
-- 3.3.1 (c) Transacción de eliminación de cuenta
-- =============================================================================
-- Eliminar calificaciones, favoritos, reproducciones, perfiles, pagos y usuario.
CREATE OR REPLACE PROCEDURE sp_eliminar_cuenta (
    p_id_usuario IN NUMBER
) AS
BEGIN
    -- Debido a que algunas tablas tienen ON DELETE CASCADE, el borrado de perfiles
    -- eliminará calificaciones, favoritos y reproducciones asociadas.
    -- Pagos y reportes no tienen ON DELETE CASCADE, deben borrarse manualmente.
    
    -- Borrar reportes donde fue moderador o creador
    DELETE FROM reportes WHERE id_usuario = p_id_usuario OR id_moderador = p_id_usuario;
    
    -- Borrar beneficios de referidos
    DELETE FROM beneficios_referidos WHERE id_usuario_refiere = p_id_usuario OR id_usuario_referido = p_id_usuario;
    
    -- Borrar pagos
    DELETE FROM pagos WHERE id_usuario = p_id_usuario;
    
    -- Borrar perfiles (se lleva favoritos, calificaciones, reproducciones por CASCADE)
    DELETE FROM perfiles WHERE id_usuario = p_id_usuario;
    
    -- Finalmente, borrar el usuario
    DELETE FROM usuarios WHERE id_usuario = p_id_usuario;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Cuenta de usuario ' || p_id_usuario || ' eliminada exitosamente.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error al eliminar la cuenta. Se ha revertido la operación. ' || SQLERRM);
END sp_eliminar_cuenta;
/

-- =============================================================================
-- 3.3.2 Escenario de Concurrencia de Datos (SELECT FOR UPDATE)
-- =============================================================================
-- Escenario: Dos sesiones de atención al cliente intentan cambiar el plan de un
-- mismo usuario. Si no se usa bloqueo, pueden sobreescribir datos inconsistentes.
-- El uso de SELECT ... FOR UPDATE bloquea la fila del usuario hasta el COMMIT.
--
-- Sesión 1:
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- SELECT id_plan FROM usuarios WHERE id_usuario = 1 FOR UPDATE;
-- -- Modifica el plan a Premium
-- UPDATE usuarios SET id_plan = 3 WHERE id_usuario = 1;
-- 
-- Sesión 2 (ejecuta simultáneamente):
-- -- Esta consulta se quedará "colgada" esperando a que Sesión 1 haga COMMIT/ROLLBACK
-- SELECT id_plan FROM usuarios WHERE id_usuario = 1 FOR UPDATE; 
-- 
-- Sesión 1:
-- COMMIT; -- Libera el bloqueo
--
-- Sesión 2:
-- -- Automáticamente avanza, lee el nuevo id_plan (3) y continúa.
-- -- Se da cuenta de que ya es Premium y no lo cambia de nuevo.
-- COMMIT;
-- =============================================================================
