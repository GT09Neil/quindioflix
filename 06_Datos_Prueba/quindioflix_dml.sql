-- =============================================================================
-- QUINDIOFLIX - DATOS DE PRUEBA ASIMÉTRICOS (DML)
-- =============================================================================
-- Inserción de catálogos fijos
INSERT INTO planes (nombre, precio, cantidad_pantallas, max_perfiles) VALUES ('Basico', 14900, 1, 2);
INSERT INTO planes (nombre, precio, cantidad_pantallas, max_perfiles) VALUES ('Estandar', 24900, 2, 3);
INSERT INTO planes (nombre, precio, cantidad_pantallas, max_perfiles) VALUES ('Premium', 34900, 4, 5);

INSERT INTO categorias (nombre) VALUES ('Peliculas');
INSERT INTO categorias (nombre) VALUES ('Series');
INSERT INTO categorias (nombre) VALUES ('Documentales');
INSERT INTO categorias (nombre) VALUES ('Musica');
INSERT INTO categorias (nombre) VALUES ('Podcasts');

INSERT INTO generos (nombre) VALUES ('Accion');
INSERT INTO generos (nombre) VALUES ('Comedia');
INSERT INTO generos (nombre) VALUES ('Drama');
INSERT INTO generos (nombre) VALUES ('Suspenso');
INSERT INTO generos (nombre) VALUES ('Romance');
INSERT INTO generos (nombre) VALUES ('Ciencia Ficcion');
INSERT INTO generos (nombre) VALUES ('Terror');
INSERT INTO generos (nombre) VALUES ('Infantil');

INSERT INTO departamentos (nombre) VALUES ('Tecnologia');
INSERT INTO departamentos (nombre) VALUES ('Contenido');
INSERT INTO departamentos (nombre) VALUES ('Marketing');
INSERT INTO departamentos (nombre) VALUES ('Soporte');
INSERT INTO departamentos (nombre) VALUES ('Finanzas');

INSERT INTO empleados (id_departamento, nombre, cargo) VALUES (2, 'Director Contenido', 'Jefe');
INSERT INTO empleados (id_departamento, nombre, cargo, id_supervisor) VALUES (2, 'Gestor A', 'Editor', 1);

INSERT INTO roles (nombre, descripcion) VALUES ('usuario', 'Usuario estandar');
INSERT INTO roles (nombre, descripcion) VALUES ('moderador', 'Moderador de reportes');

INSERT INTO dispositivos (nombre) VALUES ('celular');
INSERT INTO dispositivos (nombre) VALUES ('tablet');
INSERT INTO dispositivos (nombre) VALUES ('TV');
INSERT INTO dispositivos (nombre) VALUES ('computador');

COMMIT;

-- Bloque PL/SQL para generación masiva de datos asimétricos
DECLARE
    TYPE t_ciudades IS VARRAY(3) OF VARCHAR2(50);
    v_ciudades t_ciudades := t_ciudades('Bogota', 'Medellin', 'Cali');
    v_id_plan NUMBER;
    v_id_usuario NUMBER;
    v_id_perfil NUMBER;
    v_id_contenido NUMBER;
    v_id_temporada NUMBER;
    v_id_episodio NUMBER;
    v_id_dispositivo NUMBER;
    v_fecha DATE;
    v_rand NUMBER;
BEGIN
    -- 1. Crear 30 Usuarios (Distribuidos en 3 ciudades y 3 planes asimétricamente)
    FOR i IN 1..30 LOOP
        v_id_plan := TRUNC(DBMS_RANDOM.VALUE(1, 4)); -- Plan 1 a 3
        INSERT INTO usuarios (id_plan, id_rol, nombre, email, fecha_nacimiento, ciudad, fecha_registro, estado_cuenta, fecha_ultimo_pago)
        VALUES (v_id_plan, 1, 'Usuario ' || i, 'user'||i||'@test.com', TO_DATE('1990-01-01', 'YYYY-MM-DD') + DBMS_RANDOM.VALUE(1, 3650),
                v_ciudades(TRUNC(DBMS_RANDOM.VALUE(1, 4))), SYSDATE - DBMS_RANDOM.VALUE(30, 700), 'ACTIVO', SYSDATE - DBMS_RANDOM.VALUE(1, 25))
        RETURNING id_usuario INTO v_id_usuario;
        
        -- 2. Crear Perfiles para el usuario (Entre 1 y el maximo de su plan)
        FOR j IN 1..TRUNC(DBMS_RANDOM.VALUE(1, v_id_plan + 2)) LOOP
            INSERT INTO perfiles (id_usuario, nombre, tipo)
            VALUES (v_id_usuario, 'Perfil ' || j || ' (U' || i || ')', CASE WHEN j=1 THEN 'adulto' ELSE 'infantil' END)
            RETURNING id_perfil INTO v_id_perfil;
        END LOOP;
        
        -- 3. Crear Pagos históricos (Entre 2 y 5 pagos por usuario)
        FOR k IN 1..TRUNC(DBMS_RANDOM.VALUE(2, 6)) LOOP
            INSERT INTO pagos (id_usuario, monto, metodo_pago, estado, fecha_pago)
            VALUES (v_id_usuario, CASE v_id_plan WHEN 1 THEN 14900 WHEN 2 THEN 24900 ELSE 34900 END,
                    'tarjeta_credito', 'aprobado', SYSDATE - DBMS_RANDOM.VALUE(30, 300));
        END LOOP;
    END LOOP;

    -- 4. Crear 40 Contenidos
    FOR i IN 1..40 LOOP
        v_rand := TRUNC(DBMS_RANDOM.VALUE(1, 6)); -- Categoria
        INSERT INTO contenido (id_categoria, id_empleado, titulo, anio_lanzamiento, duracion, clasificacion_edad, es_original)
        VALUES (v_rand, 2, 'Titulo ' || i, TRUNC(DBMS_RANDOM.VALUE(2010, 2025)),
                CASE WHEN v_rand IN (2, 5) THEN NULL ELSE TRUNC(DBMS_RANDOM.VALUE(90, 150)) END,
                CASE TRUNC(DBMS_RANDOM.VALUE(1, 4)) WHEN 1 THEN 'TP' WHEN 2 THEN '+13' ELSE '+18' END,
                CASE WHEN DBMS_RANDOM.VALUE(0, 1) > 0.5 THEN 1 ELSE 0 END)
        RETURNING id_contenido INTO v_id_contenido;
        
        -- Asociar un genero
        INSERT INTO contenido_genero (id_contenido, id_genero) VALUES (v_id_contenido, TRUNC(DBMS_RANDOM.VALUE(1, 9)));
        
        -- Si es serie o podcast, crear temporadas y episodios
        IF v_rand IN (2, 5) THEN
            FOR t IN 1..TRUNC(DBMS_RANDOM.VALUE(1, 3)) LOOP
                INSERT INTO temporadas (id_contenido, numero_temporada) VALUES (v_id_contenido, t) RETURNING id_temporada INTO v_id_temporada;
                FOR e IN 1..TRUNC(DBMS_RANDOM.VALUE(2, 5)) LOOP
                    INSERT INTO episodios (id_temporada, titulo, duracion, numero_episodio)
                    VALUES (v_id_temporada, 'Epi ' || e, TRUNC(DBMS_RANDOM.VALUE(20, 60)), e);
                END LOOP;
            END LOOP;
        END IF;
    END LOOP;

    -- 5. Crear Reproducciones asimetricas (200)
    FOR i IN 1..200 LOOP
        v_id_perfil := TRUNC(DBMS_RANDOM.VALUE(1, 51)); -- Asumiendo al menos 50 perfiles creados
        v_id_dispositivo := TRUNC(DBMS_RANDOM.VALUE(1, 5));
        
        -- Distribuir en 2024, 2025, 2026 para que el particionamiento funcione
        v_rand := DBMS_RANDOM.VALUE(1, 100);
        IF v_rand < 30 THEN
            v_fecha := TO_DATE('2024-06-01', 'YYYY-MM-DD') + DBMS_RANDOM.VALUE(1, 200);
        ELSIF v_rand < 70 THEN
            v_fecha := TO_DATE('2025-06-01', 'YYYY-MM-DD') + DBMS_RANDOM.VALUE(1, 200);
        ELSE
            v_fecha := TO_DATE('2026-01-01', 'YYYY-MM-DD') + DBMS_RANDOM.VALUE(1, 100);
        END IF;
        
        -- Determinar si es directo (1,3,4) o episodio (2,5)
        IF DBMS_RANDOM.VALUE(0, 1) > 0.5 THEN
            -- Pelicula/Doc
            BEGIN
                SELECT id_contenido INTO v_id_contenido FROM (SELECT id_contenido FROM contenido WHERE id_categoria IN (1,3,4) AND clasificacion_edad IN ('TP', '+13') ORDER BY DBMS_RANDOM.VALUE) WHERE ROWNUM = 1;
                
                INSERT INTO reproducciones (id_perfil, id_contenido, id_episodio, id_dispositivo, fecha_inicio, fecha_fin, porcentaje_avance)
                VALUES (v_id_perfil, v_id_contenido, NULL, v_id_dispositivo, CAST(v_fecha AS TIMESTAMP), CAST(v_fecha + 1/24 AS TIMESTAMP), DBMS_RANDOM.VALUE(10, 100));
            EXCEPTION WHEN OTHERS THEN NULL; -- Ignorar fallos de restriccion para script aleatorio
            END;
        ELSE
            -- Serie
            BEGIN
                SELECT id_episodio INTO v_id_episodio FROM (
                    SELECT e.id_episodio FROM episodios e
                    JOIN temporadas t ON e.id_temporada = t.id_temporada
                    JOIN contenido c ON t.id_contenido = c.id_contenido
                    WHERE c.clasificacion_edad IN ('TP', '+13') ORDER BY DBMS_RANDOM.VALUE
                ) WHERE ROWNUM = 1;
                
                INSERT INTO reproducciones (id_perfil, id_contenido, id_episodio, id_dispositivo, fecha_inicio, fecha_fin, porcentaje_avance)
                VALUES (v_id_perfil, NULL, v_id_episodio, v_id_dispositivo, CAST(v_fecha AS TIMESTAMP), CAST(v_fecha + 1/24 AS TIMESTAMP), DBMS_RANDOM.VALUE(10, 100));
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
    END LOOP;

    COMMIT;
END;
/
