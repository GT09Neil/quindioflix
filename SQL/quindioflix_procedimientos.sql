-- =============================================================================
-- SECCIÓN 4: PROCEDIMIENTOS ALMACENADOS
-- =============================================================================
 
-- -----------------------------------------------------------------------------
-- PROCEDIMIENTO 1: SP_REGISTRAR_USUARIO
-- Registra un nuevo usuario en el sistema con validaciones de negocio:
--   - Email único.
--   - Plan existente.
--   - Referente válido (si aplica).
--   - Crea automáticamente un perfil adulto por defecto.
--   - Si hay referente, registra el beneficio en beneficios_referidos.
-- Parámetros de entrada:
--   p_nombre, p_email, p_telefono, p_fecha_nacimiento,
--   p_ciudad, p_id_plan, p_id_referente (NULL si no aplica)
-- Parámetro de salida:
--   p_id_usuario_nuevo ? ID del usuario creado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_USUARIO (
    p_nombre            IN  usuarios.nombre%TYPE,
    p_email             IN  usuarios.email%TYPE,
    p_telefono          IN  usuarios.telefono%TYPE          DEFAULT NULL,
    p_fecha_nacimiento  IN  usuarios.fecha_nacimiento%TYPE,
    p_ciudad            IN  usuarios.ciudad%TYPE            DEFAULT NULL,
    p_id_plan           IN  usuarios.id_plan%TYPE,
    p_id_referente      IN  usuarios.usuario_referente%TYPE DEFAULT NULL,
    p_id_usuario_nuevo  OUT usuarios.id_usuario%TYPE
) IS
 
    v_plan_existe       NUMBER;
    v_email_existe      NUMBER;
    v_referente_existe  NUMBER;
    v_id_nuevo          usuarios.id_usuario%TYPE;
 
BEGIN
    -- -------------------------------------------------------------------------
    -- VALIDACIONES PREVIAS
    -- -------------------------------------------------------------------------
 
    -- [1] Datos obligatorios presentes
    IF p_nombre IS NULL OR p_email IS NULL OR p_fecha_nacimiento IS NULL THEN
        RAISE_APPLICATION_ERROR(-20006, pkg_quindioflix_excepciones.MSG_DATOS_INCOMPLETOS);
    END IF;
 
    -- [2] El email no debe estar registrado
    SELECT COUNT(*) INTO v_email_existe
    FROM usuarios WHERE email = LOWER(TRIM(p_email));
 
    IF v_email_existe > 0 THEN
        RAISE_APPLICATION_ERROR(-20003, pkg_quindioflix_excepciones.MSG_EMAIL_DUPLICADO);
    END IF;
 
    -- [3] El plan debe existir
    SELECT COUNT(*) INTO v_plan_existe
    FROM planes WHERE id_plan = p_id_plan;
 
    IF v_plan_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20002, pkg_quindioflix_excepciones.MSG_PLAN_NO_EXISTE);
    END IF;
 
    -- [4] Validar referente (si se indica)
    IF p_id_referente IS NOT NULL THEN
        SELECT COUNT(*) INTO v_referente_existe
        FROM usuarios WHERE id_usuario = p_id_referente;
 
        IF v_referente_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20007, pkg_quindioflix_excepciones.MSG_REFERENTE_INVALIDO);
        END IF;
    END IF;
 
    -- -------------------------------------------------------------------------
    -- INSERCIÓN DEL USUARIO
    -- -------------------------------------------------------------------------
    INSERT INTO usuarios (
        id_plan,
        nombre,
        email,
        telefono,
        fecha_nacimiento,
        ciudad,
        fecha_registro,
        usuario_referente
    ) VALUES (
        p_id_plan,
        TRIM(p_nombre),
        LOWER(TRIM(p_email)),
        p_telefono,
        p_fecha_nacimiento,
        p_ciudad,
        SYSDATE,
        p_id_referente
    )
    RETURNING id_usuario INTO v_id_nuevo;
 
    p_id_usuario_nuevo := v_id_nuevo;
 
    -- -------------------------------------------------------------------------
    -- CREAR PERFIL ADULTO POR DEFECTO
    -- -------------------------------------------------------------------------
    INSERT INTO perfiles (id_usuario, nombre, tipo)
    VALUES (v_id_nuevo, 'Principal', 'adulto');
 
    -- -------------------------------------------------------------------------
    -- REGISTRAR BENEFICIO DE REFERIDO (si aplica)
    -- -------------------------------------------------------------------------
    IF p_id_referente IS NOT NULL THEN
        INSERT INTO beneficios_referidos (
            id_usuario_refiere,
            id_usuario_referido,
            tipo_beneficio,
            descripcion,
            fecha_otorgado
        ) VALUES (
            p_id_referente,
            v_id_nuevo,
            'Descuento',
            '10% de descuento en el siguiente mes por referir un nuevo usuario.',
            SYSDATE
        );
    END IF;
 
    COMMIT;
 
    DBMS_OUTPUT.PUT_LINE('? Usuario registrado exitosamente. ID: ' || v_id_nuevo);
 
EXCEPTION
    WHEN pkg_quindioflix_excepciones.ex_datos_incompletos THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error [datos incompletos]: ' || SQLERRM);
        RAISE;
    WHEN pkg_quindioflix_excepciones.ex_email_duplicado THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error [email duplicado]: ' || SQLERRM);
        RAISE;
    WHEN pkg_quindioflix_excepciones.ex_plan_no_existe THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error [plan inválido]: ' || SQLERRM);
        RAISE;
    WHEN pkg_quindioflix_excepciones.ex_referente_invalido THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error [referente inválido]: ' || SQLERRM);
        RAISE;
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error inesperado: ' || SQLERRM);
        RAISE;
END SP_REGISTRAR_USUARIO;
/
 
 
-- -----------------------------------------------------------------------------
-- PROCEDIMIENTO 2: SP_CAMBIAR_PLAN
-- Cambia el plan de suscripción de un usuario existente.
-- Validaciones:
--   - Usuario debe existir.
--   - Nuevo plan debe existir.
--   - El nuevo plan no puede ser el mismo que el actual.
--   - Si el nuevo plan tiene menos perfiles permitidos (downgrade),
--     elimina automáticamente los perfiles excedentes (los más recientes).
--   - Registra el pago correspondiente con el monto calculado por FN_CALCULAR_MONTO.
-- Parámetros:
--   p_id_usuario    ? ID del usuario
--   p_id_plan_nuevo ? ID del nuevo plan
--   p_metodo_pago   ? Método de pago para el primer cobro del nuevo plan
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_CAMBIAR_PLAN (
    p_id_usuario    IN  usuarios.id_usuario%TYPE,
    p_id_plan_nuevo IN  planes.id_plan%TYPE,
    p_metodo_pago   IN  pagos.metodo_pago%TYPE DEFAULT 'tarjeta_credito'
) IS
 
    v_plan_actual       usuarios.id_plan%TYPE;
    v_max_perfiles_new  planes.max_perfiles%TYPE;
    v_perfiles_actuales NUMBER;
    v_monto             NUMBER;
    v_plan_existe       NUMBER;
    v_usuario_existe    NUMBER;
 
    -- Cursor para eliminar perfiles excedentes en downgrade
    CURSOR cur_perfiles_excedentes (p_id_usr NUMBER, p_max NUMBER) IS
        SELECT id_perfil
        FROM (
            SELECT id_perfil,
                   ROW_NUMBER() OVER (ORDER BY id_perfil DESC) AS rn
            FROM perfiles
            WHERE id_usuario = p_id_usr
        )
        WHERE rn > p_max;
 
BEGIN
    -- -------------------------------------------------------------------------
    -- VALIDACIONES
    -- -------------------------------------------------------------------------
 
    -- [1] Verificar que el usuario exista y obtener su plan actual
    BEGIN
        SELECT id_plan INTO v_plan_actual
        FROM usuarios WHERE id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, pkg_quindioflix_excepciones.MSG_USUARIO_NO_EXISTE);
    END;
 
    -- [2] Verificar que el nuevo plan exista
    SELECT COUNT(*) INTO v_plan_existe
    FROM planes WHERE id_plan = p_id_plan_nuevo;
 
    IF v_plan_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20002, pkg_quindioflix_excepciones.MSG_PLAN_NO_EXISTE);
    END IF;
 
    -- [3] Verificar que el nuevo plan sea diferente al actual
    IF v_plan_actual = p_id_plan_nuevo THEN
        RAISE_APPLICATION_ERROR(-20004, pkg_quindioflix_excepciones.MSG_PLAN_IGUAL);
    END IF;
 
    -- -------------------------------------------------------------------------
    -- MANEJO DE DOWNGRADE: eliminar perfiles excedentes
    -- -------------------------------------------------------------------------
    SELECT max_perfiles INTO v_max_perfiles_new
    FROM planes WHERE id_plan = p_id_plan_nuevo;
 
    SELECT COUNT(*) INTO v_perfiles_actuales
    FROM perfiles WHERE id_usuario = p_id_usuario;
 
    IF v_perfiles_actuales > v_max_perfiles_new THEN
        DBMS_OUTPUT.PUT_LINE('? Downgrade detectado. Eliminando '
            || (v_perfiles_actuales - v_max_perfiles_new) || ' perfil(es) excedente(s)...');
 
        FOR rec IN cur_perfiles_excedentes(p_id_usuario, v_max_perfiles_new) LOOP
            DELETE FROM perfiles WHERE id_perfil = rec.id_perfil;
            DBMS_OUTPUT.PUT_LINE('  ? Perfil #' || rec.id_perfil || ' eliminado.');
        END LOOP;
    END IF;
 
    -- -------------------------------------------------------------------------
    -- ACTUALIZAR PLAN DEL USUARIO
    -- -------------------------------------------------------------------------
    UPDATE usuarios
    SET id_plan = p_id_plan_nuevo
    WHERE id_usuario = p_id_usuario;
 
    -- -------------------------------------------------------------------------
    -- REGISTRAR EL PAGO DEL NUEVO PLAN
    -- -------------------------------------------------------------------------
    -- Calcula el monto con posibles descuentos (usando la función)
    v_monto := FN_CALCULAR_MONTO(p_id_usuario, 1);
 
    INSERT INTO pagos (id_usuario, fecha_pago, monto, metodo_pago, estado)
    VALUES (p_id_usuario, SYSDATE, v_monto, p_metodo_pago, 'pendiente');
 
    COMMIT;
 
    DBMS_OUTPUT.PUT_LINE('? Plan actualizado correctamente. Monto a cobrar: $'
                         || TO_CHAR(v_monto, 'FM999,999,990.00'));
 
EXCEPTION
    WHEN pkg_quindioflix_excepciones.ex_usuario_no_existe THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error [usuario no existe]: ' || SQLERRM);
        RAISE;
    WHEN pkg_quindioflix_excepciones.ex_plan_no_existe THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error [plan no existe]: ' || SQLERRM);
        RAISE;
    WHEN pkg_quindioflix_excepciones.ex_plan_igual THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error [plan sin cambio]: ' || SQLERRM);
        RAISE;
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Error inesperado: ' || SQLERRM);
        RAISE;
END SP_CAMBIAR_PLAN;
/
 
 
-- -----------------------------------------------------------------------------
-- PROCEDIMIENTO 3: SP_REPORTE_CONSUMO
-- Genera un reporte de consumo detallado para un usuario en un rango de fechas:
--   - Resumen del plan y perfiles.
--   - Total de reproducciones, minutos vistos y contenidos únicos.
--   - Top 5 contenidos más reproducidos por el usuario.
--   - Total de pagos realizados en el periodo.
-- Parámetros:
--   p_id_usuario    ? ID del usuario a reportar
--   p_fecha_inicio  ? Inicio del periodo (default: primer día del mes actual)
--   p_fecha_fin     ? Fin del periodo (default: hoy)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_REPORTE_CONSUMO (
    p_id_usuario    IN  usuarios.id_usuario%TYPE,
    p_fecha_inicio  IN  DATE DEFAULT TRUNC(SYSDATE, 'MM'),
    p_fecha_fin     IN  DATE DEFAULT SYSDATE
) IS
 
    -- Variables de cabecera del reporte
    v_nombre_usuario    usuarios.nombre%TYPE;
    v_email             usuarios.email%TYPE;
    v_nombre_plan       planes.nombre%TYPE;
    v_precio_plan       planes.precio%TYPE;
    v_total_perfiles    NUMBER;
    v_fecha_registro    usuarios.fecha_registro%TYPE;
 
    -- Variables de consumo
    v_total_reprod      NUMBER := 0;
    v_minutos_vistos    NUMBER := 0;
    v_contenidos_unicos NUMBER := 0;
    v_total_pagado      NUMBER := 0;
 
    -- Variables para el top de contenido
    v_titulo_cont       contenido.titulo%TYPE;
    v_categoria_cont    categorias.nombre%TYPE;
    v_veces_visto       NUMBER;
 
    -- Cursor: top 5 contenidos más vistos por el usuario en el periodo
    CURSOR cur_top_contenido IS
        SELECT
            c.titulo,
            cat.nombre  AS categoria,
            COUNT(r.id_reproduccion) AS veces
        FROM reproducciones r
        JOIN perfiles per   ON per.id_perfil    = r.id_perfil
        JOIN contenido c    ON c.id_contenido   = r.id_contenido
        JOIN categorias cat ON cat.id_categoria = c.id_categoria
        WHERE per.id_usuario = p_id_usuario
          AND r.id_contenido IS NOT NULL
          AND TRUNC(r.fecha_inicio) BETWEEN p_fecha_inicio AND p_fecha_fin
        GROUP BY c.titulo, cat.nombre
        ORDER BY veces DESC
        FETCH FIRST 5 ROWS ONLY;
 
BEGIN
    -- -------------------------------------------------------------------------
    -- VALIDAR USUARIO
    -- -------------------------------------------------------------------------
    BEGIN
        SELECT
            u.nombre,
            u.email,
            p.nombre,
            p.precio,
            u.fecha_registro
        INTO
            v_nombre_usuario,
            v_email,
            v_nombre_plan,
            v_precio_plan,
            v_fecha_registro
        FROM usuarios u
        JOIN planes p ON p.id_plan = u.id_plan
        WHERE u.id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, pkg_quindioflix_excepciones.MSG_USUARIO_NO_EXISTE);
    END;
 
    -- -------------------------------------------------------------------------
    -- VALIDAR RANGO DE FECHAS
    -- -------------------------------------------------------------------------
    IF p_fecha_inicio > p_fecha_fin THEN
        RAISE_APPLICATION_ERROR(-20006,
            'La fecha de inicio no puede ser posterior a la fecha fin.');
    END IF;
 
    -- -------------------------------------------------------------------------
    -- DATOS DE PERFILES
    -- -------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_total_perfiles
    FROM perfiles WHERE id_usuario = p_id_usuario;
 
    -- -------------------------------------------------------------------------
    -- MÉTRICAS DE CONSUMO EN EL PERIODO
    -- -------------------------------------------------------------------------
    SELECT
        COUNT(r.id_reproduccion),
        -- Minutos estimados: porcentaje_avance aplicado sobre duración del contenido
        NVL(SUM(ROUND(c.duracion * r.porcentaje_avance / 100)), 0),
        COUNT(DISTINCT r.id_contenido)
    INTO v_total_reprod, v_minutos_vistos, v_contenidos_unicos
    FROM reproducciones r
    JOIN perfiles per   ON per.id_perfil    = r.id_perfil
    LEFT JOIN contenido c ON c.id_contenido = r.id_contenido
    WHERE per.id_usuario = p_id_usuario
      AND r.id_contenido IS NOT NULL
      AND TRUNC(r.fecha_inicio) BETWEEN p_fecha_inicio AND p_fecha_fin;
 
    -- -------------------------------------------------------------------------
    -- PAGOS EN EL PERIODO
    -- -------------------------------------------------------------------------
    SELECT NVL(SUM(CASE WHEN estado = 'aprobado' THEN monto ELSE 0 END), 0)
    INTO v_total_pagado
    FROM pagos
    WHERE id_usuario = p_id_usuario
      AND fecha_pago BETWEEN p_fecha_inicio AND p_fecha_fin;
 
    -- -------------------------------------------------------------------------
    -- IMPRIMIR REPORTE
    -- -------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('?          REPORTE DE CONSUMO — QUINDIOFLIX            ?');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('? Usuario    : ' || RPAD(v_nombre_usuario, 38) || '?');
    DBMS_OUTPUT.PUT_LINE('? Email      : ' || RPAD(v_email, 38)          || '?');
    DBMS_OUTPUT.PUT_LINE('? Plan       : ' || RPAD(v_nombre_plan, 38)    || '?');
    DBMS_OUTPUT.PUT_LINE('? Precio     : $' || RPAD(TO_CHAR(v_precio_plan, 'FM999,990.00'), 37) || '?');
    DBMS_OUTPUT.PUT_LINE('? Registrado : ' || RPAD(TO_CHAR(v_fecha_registro, 'DD/MM/YYYY'), 38) || '?');
    DBMS_OUTPUT.PUT_LINE('? Perfiles   : ' || RPAD(v_total_perfiles, 38) || '?');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('? PERIODO    : ' || TO_CHAR(p_fecha_inicio, 'DD/MM/YYYY')
                         || ' al ' || TO_CHAR(p_fecha_fin, 'DD/MM/YYYY') || RPAD(' ', 20) || '?');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('? Total reproducciones   : ' || RPAD(v_total_reprod, 27)    || '?');
    DBMS_OUTPUT.PUT_LINE('? Minutos consumidos     : ' || RPAD(v_minutos_vistos, 27)  || '?');
    DBMS_OUTPUT.PUT_LINE('? Contenidos únicos      : ' || RPAD(v_contenidos_unicos, 27) || '?');
    DBMS_OUTPUT.PUT_LINE('? Total pagado (aprobado): $' || RPAD(TO_CHAR(v_total_pagado, 'FM999,990.00'), 26) || '?');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('?          TOP 5 CONTENIDOS MÁS VISTOS                ?');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
 
    OPEN cur_top_contenido;
    LOOP
        FETCH cur_top_contenido INTO v_titulo_cont, v_categoria_cont, v_veces_visto;
        EXIT WHEN cur_top_contenido%NOTFOUND;
 
        DBMS_OUTPUT.PUT_LINE('? • ' || RPAD(SUBSTR(v_titulo_cont, 1, 30), 32)
                             || RPAD('[' || v_categoria_cont || ']', 14)
                             || RPAD(v_veces_visto || ' vez(ces)', 7) || '?');
    END LOOP;
    CLOSE cur_top_contenido;
 
    IF cur_top_contenido%ROWCOUNT = 0 THEN
        DBMS_OUTPUT.PUT_LINE('?  Sin reproducciones en el periodo seleccionado.      ?');
    END IF;
 
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('');
 
EXCEPTION
    WHEN pkg_quindioflix_excepciones.ex_usuario_no_existe THEN
        DBMS_OUTPUT.PUT_LINE('? Error [usuario no existe]: ' || SQLERRM);
        RAISE;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('? Error inesperado en SP_REPORTE_CONSUMO: ' || SQLERRM);
        RAISE;
END SP_REPORTE_CONSUMO;