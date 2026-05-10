-- =============================================================================
-- QUINDIOFLIX - DML DE CARGA INICIAL (Oracle SQL)
-- Cumple mínimos solicitados y respeta constraints + triggers.
-- =============================================================================
-- Minimos objetivo:
--   PLANES(3), USUARIOS(30), PERFILES(50), CATEGORIAS(5), GENEROS(8),
--   CONTENIDO(40), TEMPORADAS(15), EPISODIOS(50), REPRODUCCIONES(200),
--   CALIFICACIONES(60), PAGOS(80), FAVORITOS(40)
--
-- Nota:
-- - Datos asimétricos: distribución desigual por plan y ciudad.
-- - Se insertan también catálogos y tablas de apoyo necesarias por FK.
-- =============================================================================

SET DEFINE OFF;

-- -----------------------------------------------------------------------------
-- 1) CATALOGOS BASE
-- -----------------------------------------------------------------------------
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

INSERT INTO dispositivos (nombre) VALUES ('celular');
INSERT INTO dispositivos (nombre) VALUES ('tablet');
INSERT INTO dispositivos (nombre) VALUES ('TV');
INSERT INTO dispositivos (nombre) VALUES ('computador');

INSERT INTO roles (nombre, descripcion) VALUES ('usuario', 'Rol estandar');
INSERT INTO roles (nombre, descripcion) VALUES ('moderador', 'Gestiona reportes');

INSERT INTO planes (nombre, precio, cantidad_pantallas, max_perfiles)
VALUES ('Basico', 19900, 1, 1);
INSERT INTO planes (nombre, precio, cantidad_pantallas, max_perfiles)
VALUES ('Estandar', 29900, 2, 3);
INSERT INTO planes (nombre, precio, cantidad_pantallas, max_perfiles)
VALUES ('Premium', 42900, 4, 5);

-- -----------------------------------------------------------------------------
-- 2) EMPLEADOS (necesarios para FK de contenido)
-- -----------------------------------------------------------------------------
INSERT INTO empleados (id_departamento, nombre, cargo, id_supervisor)
VALUES ((SELECT id_departamento FROM departamentos WHERE nombre = 'Contenido'),
        'Laura Directora', 'Directora de Contenido', NULL);

INSERT INTO empleados (id_departamento, nombre, cargo, id_supervisor)
VALUES ((SELECT id_departamento FROM departamentos WHERE nombre = 'Contenido'),
        'Carlos Curador', 'Curador Senior',
        (SELECT id_empleado FROM empleados WHERE nombre = 'Laura Directora'));

INSERT INTO empleados (id_departamento, nombre, cargo, id_supervisor)
VALUES ((SELECT id_departamento FROM departamentos WHERE nombre = 'Contenido'),
        'Sofia Productora', 'Productora',
        (SELECT id_empleado FROM empleados WHERE nombre = 'Laura Directora'));

INSERT INTO empleados (id_departamento, nombre, cargo, id_supervisor)
VALUES ((SELECT id_departamento FROM departamentos WHERE nombre = 'Tecnologia'),
        'Andres Tech', 'Ingeniero Plataforma',
        (SELECT id_empleado FROM empleados WHERE nombre = 'Laura Directora'));

INSERT INTO empleados (id_departamento, nombre, cargo, id_supervisor)
VALUES ((SELECT id_departamento FROM departamentos WHERE nombre = 'Marketing'),
        'Valentina MKT', 'Analista Marketing',
        (SELECT id_empleado FROM empleados WHERE nombre = 'Laura Directora'));

-- -----------------------------------------------------------------------------
-- 3) USUARIOS (30) - asimetricos por plan y ciudad
-- -----------------------------------------------------------------------------
DECLARE
    v_plan_basico    NUMBER;
    v_plan_estandar  NUMBER;
    v_plan_premium   NUMBER;
    v_rol_usuario    NUMBER;
BEGIN
    SELECT id_plan INTO v_plan_basico   FROM planes WHERE nombre = 'Basico';
    SELECT id_plan INTO v_plan_estandar FROM planes WHERE nombre = 'Estandar';
    SELECT id_plan INTO v_plan_premium  FROM planes WHERE nombre = 'Premium';
    SELECT id_rol  INTO v_rol_usuario   FROM roles  WHERE nombre = 'usuario';

    FOR i IN 1..30 LOOP
        INSERT INTO usuarios (
            id_plan, id_rol, nombre, email, telefono, fecha_nacimiento, ciudad, usuario_referente
        ) VALUES (
            CASE
                WHEN i <= 12 THEN v_plan_basico
                WHEN i <= 24 THEN v_plan_estandar
                ELSE v_plan_premium
            END,
            v_rol_usuario,
            'Usuario ' || TO_CHAR(i),
            'usuario' || TO_CHAR(i) || '@quindioflix.com',
            '300000' || LPAD(i, 4, '0'),
            ADD_MONTHS(DATE '1985-01-01', i * 7),
            CASE
                WHEN i <= 16 THEN 'Armenia'
                WHEN i <= 26 THEN 'Pereira'
                ELSE 'Manizales'
            END,
            CASE WHEN i <= 3 THEN NULL ELSE i - 3 END
        );
    END LOOP;
END;
/

-- Agregamos 2 moderadores (reemplazando rol de usuarios existentes)
UPDATE usuarios
   SET id_rol = (SELECT id_rol FROM roles WHERE nombre = 'moderador')
 WHERE email IN ('usuario1@quindioflix.com', 'usuario2@quindioflix.com');

-- -----------------------------------------------------------------------------
-- 4) PERFILES (50) - respetando trigger de max_perfiles por plan
-- -----------------------------------------------------------------------------
-- Paso A: 1 perfil base para cada usuario (30)
INSERT INTO perfiles (id_usuario, nombre, avatar, tipo)
SELECT u.id_usuario,
       'Principal ' || u.id_usuario,
       'avatar_principal_' || u.id_usuario || '.png',
       'adulto'
  FROM usuarios u;

-- Paso B: +14 perfiles extra en usuarios Estandar (llegan a 2 perfiles)
INSERT INTO perfiles (id_usuario, nombre, avatar, tipo)
SELECT u.id_usuario,
       'Extra Estandar ' || u.id_usuario,
       'avatar_extra_e_' || u.id_usuario || '.png',
       'adulto'
  FROM usuarios u
  JOIN planes p ON p.id_plan = u.id_plan
 WHERE p.nombre = 'Estandar'
   AND u.id_usuario IN (
       SELECT id_usuario
         FROM (
           SELECT u2.id_usuario, ROW_NUMBER() OVER (ORDER BY u2.id_usuario) rn
             FROM usuarios u2
             JOIN planes p2 ON p2.id_plan = u2.id_plan
            WHERE p2.nombre = 'Estandar'
         )
        WHERE rn <= 12
   );

-- Paso C: +6 perfiles extra en usuarios Premium (quedan con 2 perfiles)
INSERT INTO perfiles (id_usuario, nombre, avatar, tipo)
SELECT u.id_usuario,
       'Extra Premium ' || u.id_usuario,
       'avatar_extra_p_' || u.id_usuario || '.png',
       'adulto'
  FROM usuarios u
  JOIN planes p ON p.id_plan = u.id_plan
 WHERE p.nombre = 'Premium';

-- 30 + 14 + 6 = 50

-- -----------------------------------------------------------------------------
-- 5) CONTENIDO (40) + relacion N:M con genero
-- -----------------------------------------------------------------------------
DECLARE
    v_cat_peliculas    NUMBER;
    v_cat_series       NUMBER;
    v_cat_docs         NUMBER;
    v_cat_musica       NUMBER;
    v_cat_podcasts     NUMBER;
    v_emp_count        NUMBER;
    v_emp_id           NUMBER;
BEGIN
    SELECT id_categoria INTO v_cat_peliculas FROM categorias WHERE nombre = 'Peliculas';
    SELECT id_categoria INTO v_cat_series    FROM categorias WHERE nombre = 'Series';
    SELECT id_categoria INTO v_cat_docs      FROM categorias WHERE nombre = 'Documentales';
    SELECT id_categoria INTO v_cat_musica    FROM categorias WHERE nombre = 'Musica';
    SELECT id_categoria INTO v_cat_podcasts  FROM categorias WHERE nombre = 'Podcasts';

    SELECT COUNT(*) INTO v_emp_count FROM empleados;

    FOR i IN 1..40 LOOP
        SELECT id_empleado
          INTO v_emp_id
          FROM (
                SELECT e.id_empleado, ROW_NUMBER() OVER (ORDER BY e.id_empleado) rn
                  FROM empleados e
               )
         WHERE rn = MOD(i - 1, v_emp_count) + 1;

        INSERT INTO contenido (
            id_categoria, id_empleado, titulo, anio_lanzamiento,
            duracion, sinopsis, clasificacion_edad, es_original
        ) VALUES (
            CASE
                WHEN i <= 10 THEN v_cat_peliculas
                WHEN i <= 20 THEN v_cat_series
                WHEN i <= 26 THEN v_cat_docs
                WHEN i <= 32 THEN v_cat_musica
                ELSE v_cat_podcasts
            END,
            v_emp_id,
            'Contenido ' || TO_CHAR(i),
            2000 + MOD(i, 25),
            CASE
                WHEN i BETWEEN 11 AND 20 THEN NULL
                WHEN i >= 33 THEN NULL
                ELSE 70 + MOD(i * 7, 95)
            END,
            'Sinopsis del contenido ' || TO_CHAR(i),
            CASE MOD(i, 5)
                WHEN 0 THEN 'TP'
                WHEN 1 THEN '+7'
                WHEN 2 THEN '+13'
                WHEN 3 THEN '+16'
                ELSE '+18'
            END,
            CASE WHEN MOD(i, 4) = 0 THEN 1 ELSE 0 END
        );
    END LOOP;
END;
/

-- Asignacion de generos (2 por contenido => 80 filas)
INSERT INTO contenido_genero (id_contenido, id_genero)
SELECT c.id_contenido,
       g1.id_genero
  FROM contenido c
  JOIN (
        SELECT id_genero, ROW_NUMBER() OVER (ORDER BY id_genero) rn
          FROM generos
       ) g1
    ON g1.rn = MOD(c.id_contenido - 1, 8) + 1;

INSERT INTO contenido_genero (id_contenido, id_genero)
SELECT c.id_contenido,
       g2.id_genero
  FROM contenido c
  JOIN (
        SELECT id_genero, ROW_NUMBER() OVER (ORDER BY id_genero) rn
          FROM generos
       ) g2
    ON g2.rn = MOD(c.id_contenido + 2, 8) + 1
 WHERE NOT EXISTS (
       SELECT 1
         FROM contenido_genero cg
        WHERE cg.id_contenido = c.id_contenido
          AND cg.id_genero = g2.id_genero
 );

-- -----------------------------------------------------------------------------
-- 6) TEMPORADAS (15) y EPISODIOS (50)
-- -----------------------------------------------------------------------------
-- T1 trigger: solo Series/Podcasts
DECLARE
    v_count NUMBER := 0;
BEGIN
    FOR r IN (
        SELECT c.id_contenido
          FROM contenido c
          JOIN categorias cat ON cat.id_categoria = c.id_categoria
         WHERE cat.nombre IN ('Series', 'Podcasts')
         ORDER BY c.id_contenido
    ) LOOP
        EXIT WHEN v_count >= 15;
        INSERT INTO temporadas (id_contenido, numero_temporada)
        VALUES (r.id_contenido, 1);
        v_count := v_count + 1;

        EXIT WHEN v_count >= 15;
        INSERT INTO temporadas (id_contenido, numero_temporada)
        VALUES (r.id_contenido, 2);
        v_count := v_count + 1;
    END LOOP;
END;
/

DECLARE
    v_temp_count NUMBER;
    v_temp_id    NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_temp_count FROM temporadas;

    FOR i IN 1..50 LOOP
        SELECT id_temporada
          INTO v_temp_id
          FROM (
                SELECT t.id_temporada, ROW_NUMBER() OVER (ORDER BY t.id_temporada) rn
                  FROM temporadas t
               )
         WHERE rn = MOD(i - 1, v_temp_count) + 1;

        INSERT INTO episodios (id_temporada, titulo, duracion, numero_episodio)
        VALUES (v_temp_id, 'Episodio ' || TO_CHAR(i), 22 + MOD(i * 3, 33), CEIL(i / v_temp_count));
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- 7) FAVORITOS (40)
-- -----------------------------------------------------------------------------
DECLARE
    v_perfil_count NUMBER;
    v_cont_count   NUMBER;
    v_perfil_id    NUMBER;
    v_cont_id      NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_perfil_count FROM perfiles;
    SELECT COUNT(*) INTO v_cont_count FROM contenido;

    FOR i IN 1..40 LOOP
        SELECT id_perfil
          INTO v_perfil_id
          FROM (
                SELECT p.id_perfil, ROW_NUMBER() OVER (ORDER BY p.id_perfil) rn
                  FROM perfiles p
               )
         WHERE rn = MOD(i - 1, v_perfil_count) + 1;

        SELECT id_contenido
          INTO v_cont_id
          FROM (
                SELECT c.id_contenido, ROW_NUMBER() OVER (ORDER BY c.id_contenido) rn
                  FROM contenido c
               )
         WHERE rn = MOD(i * 3, v_cont_count) + 1;

        INSERT INTO favoritos (id_perfil, id_contenido, fecha_agregado)
        VALUES (v_perfil_id, v_cont_id, SYSDATE - MOD(i, 45));
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- 8) CALIFICACIONES (60)
-- -----------------------------------------------------------------------------
DECLARE
    v_perfil_count NUMBER;
    v_cont_count   NUMBER;
    v_perfil_id    NUMBER;
    v_cont_id      NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_perfil_count FROM perfiles;
    SELECT COUNT(*) INTO v_cont_count FROM contenido;

    FOR i IN 1..60 LOOP
        SELECT id_perfil
          INTO v_perfil_id
          FROM (
                SELECT p.id_perfil, ROW_NUMBER() OVER (ORDER BY p.id_perfil) rn
                  FROM perfiles p
               )
         WHERE rn = MOD(i * 2, v_perfil_count) + 1;

        SELECT id_contenido
          INTO v_cont_id
          FROM (
                SELECT c.id_contenido, ROW_NUMBER() OVER (ORDER BY c.id_contenido) rn
                  FROM contenido c
               )
         WHERE rn = MOD(i * 5, v_cont_count) + 1;

        INSERT INTO calificaciones (id_perfil, id_contenido, estrellas, resenia, fecha)
        VALUES (
            v_perfil_id,
            v_cont_id,
            MOD(i, 5) + 1,
            'Resenia automatica #' || TO_CHAR(i),
            SYSDATE - MOD(i, 60)
        );
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- 9) PAGOS (80)
-- -----------------------------------------------------------------------------
DECLARE
    v_usr_count NUMBER;
    v_usr_id    NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_usr_count FROM usuarios;

    FOR i IN 1..80 LOOP
        SELECT id_usuario
          INTO v_usr_id
          FROM (
                SELECT u.id_usuario, ROW_NUMBER() OVER (ORDER BY u.id_usuario) rn
                  FROM usuarios u
               )
         WHERE rn = MOD(i - 1, v_usr_count) + 1;

        INSERT INTO pagos (
            id_usuario, fecha_pago, monto, metodo_pago, estado, referencia
        ) VALUES (
            v_usr_id,
            SYSDATE - MOD(i, 180),
            CASE
                WHEN MOD(i, 6) = 0 THEN 19900
                WHEN MOD(i, 6) = 1 THEN 29900
                ELSE 42900
            END,
            CASE MOD(i, 5)
                WHEN 0 THEN 'tarjeta_credito'
                WHEN 1 THEN 'tarjeta_debito'
                WHEN 2 THEN 'PSE'
                WHEN 3 THEN 'efectivo'
                ELSE 'paypal'
            END,
            CASE
                WHEN MOD(i, 9) = 0 THEN 'rechazado'
                WHEN MOD(i, 13) = 0 THEN 'reembolsado'
                ELSE 'aprobado'
            END,
            'PAY-' || TO_CHAR(100000 + i)
        );
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- 10) REPRODUCCIONES (200) - respetando XOR contenido/episodio
-- -----------------------------------------------------------------------------
DECLARE
    v_perfil_count NUMBER;
    v_cont_count   NUMBER;
    v_epi_count    NUMBER;
    v_disp_count   NUMBER;
    v_perfil_id    NUMBER;
    v_cont_id      NUMBER;
    v_epi_id       NUMBER;
    v_disp_id      NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_perfil_count FROM perfiles;
    SELECT COUNT(*) INTO v_cont_count   FROM contenido;
    SELECT COUNT(*) INTO v_epi_count    FROM episodios;
    SELECT COUNT(*) INTO v_disp_count   FROM dispositivos;

    FOR i IN 1..200 LOOP
        SELECT id_perfil
          INTO v_perfil_id
          FROM (
                SELECT p.id_perfil, ROW_NUMBER() OVER (ORDER BY p.id_perfil) rn
                  FROM perfiles p
               )
         WHERE rn = MOD(i * 3, v_perfil_count) + 1;

        SELECT id_dispositivo
          INTO v_disp_id
          FROM (
                SELECT d.id_dispositivo, ROW_NUMBER() OVER (ORDER BY d.id_dispositivo) rn
                  FROM dispositivos d
               )
         WHERE rn = MOD(i - 1, v_disp_count) + 1;

        IF MOD(i, 4) IN (0, 1) THEN
            -- Reproduccion de contenido directo (id_episodio = NULL)
            SELECT id_contenido
              INTO v_cont_id
              FROM (
                    SELECT c.id_contenido, ROW_NUMBER() OVER (ORDER BY c.id_contenido) rn
                      FROM contenido c
                   )
             WHERE rn = MOD(i * 7, v_cont_count) + 1;

            INSERT INTO reproducciones (
                id_perfil, id_contenido, id_episodio, id_dispositivo,
                fecha_inicio, fecha_fin, porcentaje_avance
            ) VALUES (
                v_perfil_id, v_cont_id, NULL, v_disp_id,
                SYSTIMESTAMP - NUMTODSINTERVAL(MOD(i, 120), 'DAY'),
                SYSTIMESTAMP - NUMTODSINTERVAL(MOD(i, 120), 'DAY')
                    + NUMTODSINTERVAL(15 + MOD(i, 90), 'MINUTE'),
                MOD(i * 9, 101)
            );
        ELSE
            -- Reproduccion de episodio (id_contenido = NULL)
            SELECT id_episodio
              INTO v_epi_id
              FROM (
                    SELECT e.id_episodio, ROW_NUMBER() OVER (ORDER BY e.id_episodio) rn
                      FROM episodios e
                   )
             WHERE rn = MOD(i * 5, v_epi_count) + 1;

            INSERT INTO reproducciones (
                id_perfil, id_contenido, id_episodio, id_dispositivo,
                fecha_inicio, fecha_fin, porcentaje_avance
            ) VALUES (
                v_perfil_id, NULL, v_epi_id, v_disp_id,
                SYSTIMESTAMP - NUMTODSINTERVAL(MOD(i, 90), 'DAY'),
                SYSTIMESTAMP - NUMTODSINTERVAL(MOD(i, 90), 'DAY')
                    + NUMTODSINTERVAL(12 + MOD(i, 75), 'MINUTE'),
                MOD(i * 11, 101)
            );
        END IF;
    END LOOP;
END;
/

COMMIT;

-- -----------------------------------------------------------------------------
-- 11) VALIDACION RAPIDA DE MINIMOS
-- -----------------------------------------------------------------------------
SELECT 'PLANES' tabla, COUNT(*) total FROM planes
UNION ALL SELECT 'USUARIOS', COUNT(*) FROM usuarios
UNION ALL SELECT 'PERFILES', COUNT(*) FROM perfiles
UNION ALL SELECT 'CATEGORIAS', COUNT(*) FROM categorias
UNION ALL SELECT 'GENEROS', COUNT(*) FROM generos
UNION ALL SELECT 'CONTENIDO', COUNT(*) FROM contenido
UNION ALL SELECT 'TEMPORADAS', COUNT(*) FROM temporadas
UNION ALL SELECT 'EPISODIOS', COUNT(*) FROM episodios
UNION ALL SELECT 'REPRODUCCIONES', COUNT(*) FROM reproducciones
UNION ALL SELECT 'CALIFICACIONES', COUNT(*) FROM calificaciones
UNION ALL SELECT 'PAGOS', COUNT(*) FROM pagos
UNION ALL SELECT 'FAVORITOS', COUNT(*) FROM favoritos;

