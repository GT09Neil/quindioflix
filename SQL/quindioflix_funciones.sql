-- =============================================================================
-- SECCIÓN 3: FUNCIONES
-- =============================================================================
 
-- -----------------------------------------------------------------------------
-- FUNCIÓN 1: FN_CALCULAR_MONTO
-- Calcula el monto que debe pagar un usuario según su plan y aplica descuentos:
--   - 10% descuento si tiene más de 3 referidos activos.
--   - 5%  descuento si el usuario lleva más de 12 meses registrado.
--   - Ambos descuentos son acumulables (máximo 15%).
-- Parámetros:
--   p_id_usuario  ? ID del usuario
--   p_meses       ? Cantidad de meses a calcular (default 1)
-- Retorna: Monto final con descuentos aplicados (NUMBER(10,2))
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_CALCULAR_MONTO (
    p_id_usuario    IN  usuarios.id_usuario%TYPE,
    p_meses         IN  NUMBER DEFAULT 1
) RETURN NUMBER IS
 
    v_precio_base       planes.precio%TYPE;
    v_meses_registro    NUMBER;
    v_total_referidos   NUMBER;
    v_descuento         NUMBER := 0;
    v_monto_final       NUMBER;
 
BEGIN
    -- Validar que el usuario exista y obtener precio de su plan
    BEGIN
        SELECT p.precio,
               MONTHS_BETWEEN(SYSDATE, u.fecha_registro),
               (SELECT COUNT(*) FROM usuarios ref
                WHERE ref.usuario_referente = u.id_usuario)
        INTO v_precio_base, v_meses_registro, v_total_referidos
        FROM usuarios u
        JOIN planes p ON p.id_plan = u.id_plan
        WHERE u.id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, pkg_quindioflix_excepciones.MSG_USUARIO_NO_EXISTE);
    END;
 
    -- Validar cantidad de meses
    IF p_meses IS NULL OR p_meses <= 0 THEN
        RAISE_APPLICATION_ERROR(-20006, pkg_quindioflix_excepciones.MSG_DATOS_INCOMPLETOS);
    END IF;
 
    -- Aplicar descuento por referidos (>3 referidos activos ? 10%)
    IF v_total_referidos > 3 THEN
        v_descuento := v_descuento + 0.10;
    END IF;
 
    -- Aplicar descuento por antigüedad (>12 meses ? 5%)
    IF v_meses_registro > 12 THEN
        v_descuento := v_descuento + 0.05;
    END IF;
 
    -- Calcular monto final
    v_monto_final := ROUND(v_precio_base * p_meses * (1 - v_descuento), 2);
 
    RETURN v_monto_final;
 
EXCEPTION
    WHEN OTHERS THEN
        -- Re-lanzar cualquier excepción no controlada
        RAISE;
END FN_CALCULAR_MONTO;
/
 
 
-- -----------------------------------------------------------------------------
-- FUNCIÓN 2: FN_CONTENIDO_RECOMENDADO
-- Devuelve el ID del contenido más recomendado para un usuario basándose en:
--   1. Los géneros que más ha consumido (reproducciones del perfil activo).
--   2. Contenido que aún no ha reproducido.
--   3. Ordenado por score de popularidad (usa la misma lógica del cursor 2).
-- Parámetros:
--   p_id_usuario  ? ID del usuario
--   p_id_perfil   ? ID del perfil activo (para filtrar infantil/adulto)
-- Retorna: id_contenido (NUMBER) del contenido más recomendado.
--          Retorna NULL si no hay recomendaciones disponibles.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_CONTENIDO_RECOMENDADO (
    p_id_usuario    IN  usuarios.id_usuario%TYPE,
    p_id_perfil     IN  perfiles.id_perfil%TYPE
) RETURN NUMBER IS
 
    v_id_contenido_rec  NUMBER;
    v_tipo_perfil       perfiles.tipo%TYPE;
    v_perfil_existe     NUMBER;
    v_usuario_existe    NUMBER;
 
BEGIN
    -- Validar usuario
    SELECT COUNT(*) INTO v_usuario_existe
    FROM usuarios WHERE id_usuario = p_id_usuario;
 
    IF v_usuario_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, pkg_quindioflix_excepciones.MSG_USUARIO_NO_EXISTE);
    END IF;
 
    -- Validar perfil y obtener tipo
    BEGIN
        SELECT tipo INTO v_tipo_perfil
        FROM perfiles
        WHERE id_perfil = p_id_perfil
          AND id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20006,
                'El perfil no existe o no pertenece al usuario indicado.');
    END;
 
    -- Buscar el contenido más relevante aún no visto por el perfil,
    -- priorizando géneros consumidos por el perfil y popularidad general.
    SELECT id_contenido
    INTO v_id_contenido_rec
    FROM (
        WITH generos_favoritos AS (
            -- Géneros más consumidos por el perfil (top 3)
            SELECT cg.id_genero, COUNT(*) AS veces
            FROM reproducciones r
            JOIN contenido_genero cg ON cg.id_contenido = r.id_contenido
            WHERE r.id_perfil = p_id_perfil
            GROUP BY cg.id_genero
            ORDER BY veces DESC
            FETCH FIRST 3 ROWS ONLY
        ),
        contenido_candidato AS (
            SELECT
                c.id_contenido,
                c.titulo,
                c.clasificacion_edad,
                -- Número de géneros coincidentes con los favoritos del perfil
                COUNT(DISTINCT gf.id_genero) AS match_generos,
                -- Popularidad básica: reproducciones totales + calificaciones
                COUNT(DISTINCT r2.id_reproduccion) AS reproducciones_totales,
                AVG(cal.estrellas)                  AS avg_estrellas
            FROM contenido c
            LEFT JOIN contenido_genero cg2   ON cg2.id_contenido = c.id_contenido
            LEFT JOIN generos_favoritos gf   ON gf.id_genero = cg2.id_genero
            LEFT JOIN reproducciones r2      ON r2.id_contenido = c.id_contenido
            LEFT JOIN calificaciones cal     ON cal.id_contenido = c.id_contenido
            WHERE
                -- Excluir contenido ya visto por el perfil
                c.id_contenido NOT IN (
                    SELECT r3.id_contenido
                    FROM reproducciones r3
                    WHERE r3.id_perfil = p_id_perfil
                      AND r3.id_contenido IS NOT NULL
                )
                -- Filtro de clasificación para perfiles infantiles
                AND (
                    v_tipo_perfil = 'adulto'
                    OR (v_tipo_perfil = 'infantil'
                        AND c.clasificacion_edad IN ('TP', '+7', '+13'))
                )
            GROUP BY c.id_contenido, c.titulo, c.clasificacion_edad
        )
        SELECT id_contenido
        FROM contenido_candidato
        ORDER BY
            match_generos           DESC,   -- Primero los que coinciden con gustos
            reproducciones_totales  DESC,   -- Luego los más reproducidos
            NVL(avg_estrellas, 0)   DESC    -- Finalmente mejor calificados
        FETCH FIRST 1 ROW ONLY
    );
 
    RETURN v_id_contenido_rec;
 
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- No hay contenido disponible para recomendar
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE;
END FN_CONTENIDO_RECOMENDADO;