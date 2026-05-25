-- =============================================================================
-- QUINDIOFLIX - TRIGGERS DE REGLAS DE NEGOCIO (Oracle SQL)
-- =============================================================================
-- Reglas que NO pueden implementarse con CHECK constraints porque requieren
-- consultar datos de otras tablas. Se implementan con TRIGGERS.
-- =============================================================================
-- [T1] Solo Series/Podcasts pueden tener temporadas
-- [T2] Límite de perfiles por usuario según planes.max_perfiles
-- [T3] Perfiles infantiles solo pueden consumir contenido TP, +7, +13
-- [T4] Validar que reportes.id_moderador sea usuario con rol 'moderador'
-- =============================================================================

-- =============================================================================
-- [T1] TRIGGER: Solo contenidos de categoría 'Series' o 'Podcasts' pueden
--      tener temporadas.
-- =============================================================================
-- Se dispara BEFORE INSERT OR UPDATE en temporadas.
-- Consulta la categoría del contenido asociado y rechaza si no es
-- 'Series' ni 'Podcasts'.
-- =============================================================================
CREATE OR REPLACE TRIGGER trg_temporadas_categoria
BEFORE INSERT OR UPDATE OF id_contenido ON temporadas
FOR EACH ROW
DECLARE
    v_categoria VARCHAR2(50);
BEGIN
    -- Obtener el nombre de la categoría del contenido asociado
    SELECT c.nombre
      INTO v_categoria
      FROM categorias c
      JOIN contenido co ON co.id_categoria = c.id_categoria
     WHERE co.id_contenido = :NEW.id_contenido;

    -- Validar que sea Series o Podcasts
    IF v_categoria NOT IN ('Series', 'Podcasts') THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Error [T1]: Solo contenidos de categoría Series o Podcasts pueden tener temporadas. '
            || 'Categoría actual: ' || v_categoria
            || ' (id_contenido: ' || :NEW.id_contenido || ').'
        );
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20002,
            'Error [T1]: El contenido con id_contenido = ' || :NEW.id_contenido
            || ' no existe.'
        );
END trg_temporadas_categoria;
/

-- =============================================================================
-- [T2] TRIGGER: Límite de perfiles por usuario según planes.max_perfiles.
-- =============================================================================
-- Se dispara BEFORE INSERT en perfiles.
-- Cuenta los perfiles existentes del usuario y los compara con el
-- max_perfiles definido en su plan de suscripción.
-- En UPDATE de id_usuario (cambio de propietario) también se valida.
-- =============================================================================
CREATE OR REPLACE TRIGGER trg_perfiles_limite_plan
BEFORE INSERT OR UPDATE OF id_usuario ON perfiles
FOR EACH ROW
DECLARE
    v_max_perfiles  NUMBER;
    v_count_actual  NUMBER;
BEGIN
    -- Obtener el límite de perfiles del plan del usuario
    SELECT p.max_perfiles
      INTO v_max_perfiles
      FROM planes p
      JOIN usuarios u ON u.id_plan = p.id_plan
     WHERE u.id_usuario = :NEW.id_usuario;

    -- Contar perfiles actuales del usuario
    -- En UPDATE: excluir el perfil que se está modificando para no contarlo doble
    -- En INSERT: contar todos los perfiles existentes del usuario
    IF UPDATING THEN
        SELECT COUNT(*)
          INTO v_count_actual
          FROM perfiles
         WHERE id_usuario = :NEW.id_usuario
           AND id_perfil != :NEW.id_perfil;
    ELSE
        SELECT COUNT(*)
          INTO v_count_actual
          FROM perfiles
         WHERE id_usuario = :NEW.id_usuario;
    END IF;

    -- Validar que no se exceda el límite
    IF v_count_actual >= v_max_perfiles THEN
        RAISE_APPLICATION_ERROR(
            -20010,
            'Error [T2]: El usuario id_usuario = ' || :NEW.id_usuario
            || ' ya tiene ' || v_count_actual || ' perfil(es). '
            || 'Su plan permite un máximo de ' || v_max_perfiles || ' perfiles.'
        );
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20011,
            'Error [T2]: El usuario con id_usuario = ' || :NEW.id_usuario
            || ' no existe o no tiene plan asignado.'
        );
END trg_perfiles_limite_plan;
/

-- =============================================================================
-- [T3] TRIGGER: Perfiles infantiles solo pueden consumir contenido con
--      clasificacion_edad IN ('TP', '+7', '+13').
-- =============================================================================
-- Se aplica en tres tablas: reproducciones, favoritos y calificaciones.
-- Para reproducciones, se debe considerar el XOR contenido/episodio:
--   - Si id_contenido → consultar directamente contenido.clasificacion_edad
--   - Si id_episodio  → navegar episodio → temporada → contenido.clasificacion_edad
-- =============================================================================

-- ---------------------------------------------------------------------------
-- [T3a] TRIGGER en REPRODUCCIONES
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_repro_perfil_infantil
BEFORE INSERT OR UPDATE ON reproducciones
FOR EACH ROW
DECLARE
    v_tipo_perfil       VARCHAR2(10);
    v_clasificacion     VARCHAR2(5);
BEGIN
    -- Obtener el tipo de perfil
    SELECT tipo
      INTO v_tipo_perfil
      FROM perfiles
     WHERE id_perfil = :NEW.id_perfil;

    -- Solo validar si el perfil es infantil
    IF v_tipo_perfil = 'infantil' THEN

        IF :NEW.id_contenido IS NOT NULL THEN
            -- Reproducción de contenido directo (película, documental, música)
            SELECT clasificacion_edad
              INTO v_clasificacion
              FROM contenido
             WHERE id_contenido = :NEW.id_contenido;

        ELSIF :NEW.id_episodio IS NOT NULL THEN
            -- Reproducción de episodio: navegar episodio → temporada → contenido
            SELECT co.clasificacion_edad
              INTO v_clasificacion
              FROM contenido co
              JOIN temporadas t ON t.id_contenido = co.id_contenido
              JOIN episodios  e ON e.id_temporada = t.id_temporada
             WHERE e.id_episodio = :NEW.id_episodio;
        END IF;

        -- Restringir clasificaciones no aptas para perfil infantil
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

-- ---------------------------------------------------------------------------
-- [T3b] TRIGGER en FAVORITOS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_fav_perfil_infantil
BEFORE INSERT OR UPDATE ON favoritos
FOR EACH ROW
DECLARE
    v_tipo_perfil       VARCHAR2(10);
    v_clasificacion     VARCHAR2(5);
BEGIN
    -- Obtener el tipo de perfil
    SELECT tipo
      INTO v_tipo_perfil
      FROM perfiles
     WHERE id_perfil = :NEW.id_perfil;

    -- Solo validar si el perfil es infantil
    IF v_tipo_perfil = 'infantil' THEN

        SELECT clasificacion_edad
          INTO v_clasificacion
          FROM contenido
         WHERE id_contenido = :NEW.id_contenido;

        IF v_clasificacion NOT IN ('TP', '+7', '+13') THEN
            RAISE_APPLICATION_ERROR(
                -20021,
                'Error [T3]: Perfil infantil (id_perfil = ' || :NEW.id_perfil
                || ') no puede agregar a favoritos contenido con clasificación '
                || v_clasificacion || '. Solo se permite TP, +7, +13.'
            );
        END IF;

    END IF;
END trg_fav_perfil_infantil;
/

-- ---------------------------------------------------------------------------
-- [T3c] TRIGGER en CALIFICACIONES
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_cal_perfil_infantil
BEFORE INSERT OR UPDATE ON calificaciones
FOR EACH ROW
DECLARE
    v_tipo_perfil       VARCHAR2(10);
    v_clasificacion     VARCHAR2(5);
BEGIN
    -- Obtener el tipo de perfil
    SELECT tipo
      INTO v_tipo_perfil
      FROM perfiles
     WHERE id_perfil = :NEW.id_perfil;

    -- Solo validar si el perfil es infantil
    IF v_tipo_perfil = 'infantil' THEN

        SELECT clasificacion_edad
          INTO v_clasificacion
          FROM contenido
         WHERE id_contenido = :NEW.id_contenido;

        IF v_clasificacion NOT IN ('TP', '+7', '+13') THEN
            RAISE_APPLICATION_ERROR(
                -20022,
                'Error [T3]: Perfil infantil (id_perfil = ' || :NEW.id_perfil
                || ') no puede calificar contenido con clasificación '
                || v_clasificacion || '. Solo se permite TP, +7, +13.'
            );
        END IF;

    END IF;
END trg_cal_perfil_infantil;
/

-- =============================================================================
-- [T4] TRIGGER: Validar que reportes.id_moderador sea un usuario con
--      rol 'moderador'.
-- =============================================================================
-- Se dispara BEFORE INSERT OR UPDATE de id_moderador en reportes.
-- Consulta el rol del usuario asignado como moderador y rechaza si no
-- tiene el rol 'moderador'.
-- Solo se valida cuando id_moderador IS NOT NULL (no se valida cuando
-- el reporte aún no tiene moderador asignado).
-- =============================================================================
CREATE OR REPLACE TRIGGER trg_reportes_moderador_rol
BEFORE INSERT OR UPDATE OF id_moderador ON reportes
FOR EACH ROW
DECLARE
    v_nombre_rol VARCHAR2(50);
BEGIN
    -- Solo validar si se asigna un moderador
    IF :NEW.id_moderador IS NOT NULL THEN

        -- Obtener el rol del usuario asignado como moderador
        SELECT r.nombre
          INTO v_nombre_rol
          FROM roles r
          JOIN usuarios u ON u.id_rol = r.id_rol
         WHERE u.id_usuario = :NEW.id_moderador;

        -- Validar que tenga rol de moderador
        IF v_nombre_rol != 'moderador' THEN
            RAISE_APPLICATION_ERROR(
                -20030,
                'Error [T4]: El usuario id_usuario = ' || :NEW.id_moderador
                || ' no tiene rol de moderador (rol actual: ' || v_nombre_rol
                || '). Solo usuarios con rol moderador pueden gestionar reportes.'
            );
        END IF;

    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20031,
            'Error [T4]: El usuario con id_usuario = ' || :NEW.id_moderador
            || ' no existe.'
        );
END trg_reportes_moderador_rol;
/

-- =============================================================================
-- [T5] TRIGGER: Verificar cuenta activa al insertar REPRODUCCIONES
-- =============================================================================
-- Se dispara BEFORE INSERT en reproducciones.
-- Verifica que el usuario dueño del perfil tenga la cuenta en estado 'ACTIVO'.
-- =============================================================================
CREATE OR REPLACE TRIGGER trg_repro_cuenta_activa
BEFORE INSERT ON reproducciones
FOR EACH ROW
DECLARE
    v_estado_cuenta VARCHAR2(20);
BEGIN
    SELECT u.estado_cuenta
      INTO v_estado_cuenta
      FROM usuarios u
      JOIN perfiles p ON p.id_usuario = u.id_usuario
     WHERE p.id_perfil = :NEW.id_perfil;

    IF v_estado_cuenta != 'ACTIVO' THEN
        RAISE_APPLICATION_ERROR(
            -20040,
            'Error [T5]: El usuario dueño del perfil id_perfil = ' || :NEW.id_perfil
            || ' no tiene una cuenta ACTIVA. Estado actual: ' || v_estado_cuenta || '.'
        );
    END IF;
END trg_repro_cuenta_activa;
/

-- =============================================================================
-- [T6] TRIGGER: Verificar reproducción del 50% antes de CALIFICACIONES
-- =============================================================================
-- Se dispara BEFORE INSERT ON calificaciones.
-- Verifica en reproducciones que el avance sea al menos 50% para el perfil y
-- el contenido (o sus episodios).
-- =============================================================================
CREATE OR REPLACE TRIGGER trg_cal_repro_50
BEFORE INSERT ON calificaciones
FOR EACH ROW
DECLARE
    v_max_avance NUMBER;
BEGIN
    SELECT NVL(MAX(r.porcentaje_avance), 0)
      INTO v_max_avance
      FROM reproducciones r
      LEFT JOIN episodios e ON r.id_episodio = e.id_episodio
      LEFT JOIN temporadas t ON e.id_temporada = t.id_temporada
     WHERE r.id_perfil = :NEW.id_perfil
       AND (r.id_contenido = :NEW.id_contenido OR t.id_contenido = :NEW.id_contenido);

    IF v_max_avance < 50 THEN
        RAISE_APPLICATION_ERROR(
            -20041,
            'Error [T6]: El perfil id_perfil = ' || :NEW.id_perfil
            || ' debe reproducir al menos el 50% del contenido ' || :NEW.id_contenido
            || ' antes de poder calificarlo. Avance actual: ' || v_max_avance || '%.'
        );
    END IF;
END trg_cal_repro_50;
/

-- =============================================================================
-- [T7] TRIGGER: Actualizar estado de cuenta después de insertar PAGOS
-- =============================================================================
-- Se dispara AFTER INSERT ON pagos (FOR EACH ROW, opción recomendada).
-- Si el pago es exitoso ('aprobado'), actualiza el estado del usuario a 'ACTIVO'
-- y la fecha_ultimo_pago a la fecha del pago.
-- =============================================================================
CREATE OR REPLACE TRIGGER trg_pagos_actualizar_estado
AFTER INSERT ON pagos
FOR EACH ROW
BEGIN
    IF :NEW.estado = 'aprobado' THEN
        UPDATE usuarios
           SET estado_cuenta = 'ACTIVO',
               fecha_ultimo_pago = :NEW.fecha_pago
         WHERE id_usuario = :NEW.id_usuario;
    END IF;
END trg_pagos_actualizar_estado;
/

-- =============================================================================
-- FIN DE TRIGGERS — QUINDIOFLIX
-- =============================================================================
-- Resumen de triggers implementados:
--
--   trg_temporadas_categoria   [T1] → temporadas (BEFORE INSERT/UPDATE)
--   trg_perfiles_limite_plan   [T2] → perfiles   (BEFORE INSERT/UPDATE)
--   trg_repro_perfil_infantil  [T3a] → reproducciones (BEFORE INSERT/UPDATE)
--   trg_fav_perfil_infantil    [T3b] → favoritos      (BEFORE INSERT/UPDATE)
--   trg_cal_perfil_infantil    [T3c] → calificaciones  (BEFORE INSERT/UPDATE)
--   trg_reportes_moderador_rol [T4] → reportes   (BEFORE INSERT/UPDATE)
--   trg_repro_cuenta_activa    [T5] → reproducciones (BEFORE INSERT)
--   trg_cal_repro_50           [T6] → calificaciones (BEFORE INSERT)
--   trg_pagos_actualizar_est   [T7] → pagos          (AFTER INSERT FOR EACH ROW)
--
-- Total: 9 triggers para 7 reglas de negocio.
-- Códigos de error: -20001 a -20041 (rango reservado para la aplicación).
-- =============================================================================
