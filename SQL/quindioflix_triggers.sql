-- =============================================================================
-- QUINDIOFLIX - TRIGGERS DE REGLAS DE NEGOCIO (Oracle SQL)
-- =============================================================================
-- Reglas que NO pueden implementarse con CHECK constraints porque requieren
-- consultar datos de otras tablas. Se implementan con TRIGGERS.
-- =============================================================================
-- [T1] Solo Series/Podcasts pueden tener temporadas
-- [T2] Límite de perfiles por usuario según planes.max_perfiles
-- [T3] Perfiles infantiles solo pueden consumir contenido TP, +7, +13
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
