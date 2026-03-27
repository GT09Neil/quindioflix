-- =============================================================================
-- QUINDIOFLIX - DDL CORREGIDO (Oracle SQL)
-- Plataforma de Streaming
-- Modelo Relacional en 3FN Estricta
-- =============================================================================
-- Autor:       Anderson Neil
-- Fecha:       2026-03-27
-- Versión:     3.0 (Auditoría y correcciones aplicadas)
-- Motor:       Oracle Database
-- Convenciones: snake_case, constraints explícitas, comentarios técnicos
-- =============================================================================
--
-- CORRECCIONES APLICADAS EN ESTA VERSIÓN:
-- ----------------------------------------
-- [C1] Moderadores ahora son usuarios con rol, NO empleados.
--      FK reportes.id_moderador → usuarios (antes apuntaba a empleados).
-- [C2] Nueva tabla: roles. Permite diferenciar usuarios normales y moderadores.
--      FK usuarios.id_rol → roles.
-- [C3] Nueva tabla: pagos. Registra pagos de suscripción con CHECKs de
--      método de pago, estado y monto > 0.
-- [C4] Documentación completa de reglas que requieren TRIGGER:
--      - Perfiles infantiles solo pueden consumir contenido TP, +7, +13
--      - Solo series/podcasts pueden tener temporadas
--      - Límite de perfiles según max_perfiles del plan
-- [C5] Constraint adicional en reportes: si estado = 'resuelto' o 'rechazado',
--      id_moderador y fecha_resolucion deben estar informados.
-- [C6] CHECK mejorado en contenido.duracion para aceptar NULL (series/podcasts)
--      o valor > 0 (películas, docs, música).
-- =============================================================================

-- =============================================================================
-- 0. LIMPIEZA — DROP TABLES EN ORDEN INVERSO DE DEPENDENCIAS
-- =============================================================================

-- Tablas dependientes (hojas) primero, tablas padre al final
DROP TABLE calificaciones       CASCADE CONSTRAINTS;
DROP TABLE favoritos            CASCADE CONSTRAINTS;
DROP TABLE reproducciones       CASCADE CONSTRAINTS;
DROP TABLE reportes             CASCADE CONSTRAINTS;
DROP TABLE pagos                CASCADE CONSTRAINTS;
DROP TABLE episodios            CASCADE CONSTRAINTS;
DROP TABLE temporadas           CASCADE CONSTRAINTS;
DROP TABLE contenido_genero     CASCADE CONSTRAINTS;
DROP TABLE relacion_contenido   CASCADE CONSTRAINTS;
DROP TABLE beneficios_referidos CASCADE CONSTRAINTS;
DROP TABLE perfiles             CASCADE CONSTRAINTS;
DROP TABLE contenido            CASCADE CONSTRAINTS;
DROP TABLE usuarios             CASCADE CONSTRAINTS;
DROP TABLE empleados            CASCADE CONSTRAINTS;
DROP TABLE departamentos        CASCADE CONSTRAINTS;
DROP TABLE generos              CASCADE CONSTRAINTS;
DROP TABLE categorias           CASCADE CONSTRAINTS;
DROP TABLE planes               CASCADE CONSTRAINTS;
DROP TABLE dispositivos         CASCADE CONSTRAINTS;
DROP TABLE roles                CASCADE CONSTRAINTS;

-- =============================================================================
-- 1. CATEGORIAS
-- =============================================================================
-- Catálogo cerrado de tipos de contenido.
-- Se restringe con CHECK para garantizar solo valores válidos del negocio.
CREATE TABLE categorias (
    id_categoria    NUMBER GENERATED ALWAYS AS IDENTITY,
    nombre          VARCHAR2(50)    NOT NULL,
    CONSTRAINT pk_categorias        PRIMARY KEY (id_categoria),
    CONSTRAINT uq_categorias_nombre UNIQUE (nombre),
    CONSTRAINT ck_categorias_nombre CHECK (
        nombre IN ('Peliculas', 'Series', 'Documentales', 'Musica', 'Podcasts')
    )
);

COMMENT ON TABLE  categorias            IS 'Catálogo de categorías de contenido: Películas, Series, Documentales, Música, Podcasts.';
COMMENT ON COLUMN categorias.id_categoria IS 'PK autoincremental (IDENTITY) de la categoría.';
COMMENT ON COLUMN categorias.nombre       IS 'Nombre de la categoría. Restringido por CHECK a valores del negocio.';

-- =============================================================================
-- 2. GENEROS
-- =============================================================================
-- Catálogo de géneros cinematográficos / musicales.
-- Relación N:M con contenido a través de contenido_genero.
CREATE TABLE generos (
    id_genero   NUMBER GENERATED ALWAYS AS IDENTITY,
    nombre      VARCHAR2(50)    NOT NULL,
    CONSTRAINT pk_generos           PRIMARY KEY (id_genero),
    CONSTRAINT uq_generos_nombre    UNIQUE (nombre)
);

COMMENT ON TABLE  generos           IS 'Catálogo de géneros (Acción, Comedia, Drama, Terror, Ciencia Ficción, etc.).';
COMMENT ON COLUMN generos.id_genero IS 'PK autoincremental del género.';
COMMENT ON COLUMN generos.nombre    IS 'Nombre único del género.';

-- =============================================================================
-- 3. DEPARTAMENTOS
-- =============================================================================
-- Departamentos internos de la organización.
CREATE TABLE departamentos (
    id_departamento NUMBER GENERATED ALWAYS AS IDENTITY,
    nombre          VARCHAR2(100)   NOT NULL,
    CONSTRAINT pk_departamentos         PRIMARY KEY (id_departamento),
    CONSTRAINT uq_departamentos_nombre  UNIQUE (nombre),
    CONSTRAINT ck_departamentos_nombre  CHECK (
        nombre IN ('Tecnologia', 'Contenido', 'Marketing', 'Soporte', 'Finanzas')
    )
);

COMMENT ON TABLE  departamentos                IS 'Departamentos de la empresa: Tecnología, Contenido, Marketing, Soporte, Finanzas.';
COMMENT ON COLUMN departamentos.id_departamento IS 'PK autoincremental del departamento.';
COMMENT ON COLUMN departamentos.nombre          IS 'Nombre del departamento. Restringido por CHECK a valores del negocio.';

-- =============================================================================
-- 4. EMPLEADOS
-- =============================================================================
-- Relación reflexiva: id_supervisor → empleados (jerarquía).
-- Todo contenido requiere un empleado responsable de publicación.
CREATE TABLE empleados (
    id_empleado     NUMBER GENERATED ALWAYS AS IDENTITY,
    id_departamento NUMBER          NOT NULL,
    nombre          VARCHAR2(150)   NOT NULL,
    cargo           VARCHAR2(100)   NOT NULL,
    id_supervisor   NUMBER,  -- NULL para empleados de nivel más alto (gerente general)
    CONSTRAINT pk_empleados             PRIMARY KEY (id_empleado),
    CONSTRAINT fk_empleados_depto       FOREIGN KEY (id_departamento)
        REFERENCES departamentos (id_departamento),
    CONSTRAINT fk_empleados_supervisor  FOREIGN KEY (id_supervisor)
        REFERENCES empleados (id_empleado)
);

COMMENT ON TABLE  empleados                IS 'Empleados de QuindioFlix. Relación reflexiva para jerarquía de supervisión.';
COMMENT ON COLUMN empleados.id_empleado     IS 'PK autoincremental del empleado.';
COMMENT ON COLUMN empleados.id_departamento IS 'FK al departamento al que pertenece el empleado.';
COMMENT ON COLUMN empleados.nombre          IS 'Nombre completo del empleado.';
COMMENT ON COLUMN empleados.cargo           IS 'Cargo o rol del empleado dentro de la organización.';
COMMENT ON COLUMN empleados.id_supervisor   IS 'FK reflexiva: supervisor directo. NULL si no tiene supervisor (nivel más alto).';

-- =============================================================================
-- 5. CONTENIDO
-- =============================================================================
-- Tabla central del catálogo. Unifica películas, series, documentales, música, podcasts.
-- Cada registro pertenece a UNA categoría y tiene UN empleado responsable de publicación.
-- clasificacion_edad con CHECK para valores del negocio.
-- es_original: 1 = producción original de QuindioFlix, 0 = licenciado.
--
-- [C6] CHECK de duracion permite NULL (para series/podcasts cuya duración es por
--      episodio) pero si tiene valor, debe ser > 0.
CREATE TABLE contenido (
    id_contenido        NUMBER GENERATED ALWAYS AS IDENTITY,
    id_categoria        NUMBER          NOT NULL,
    id_empleado         NUMBER          NOT NULL,  -- Responsable de publicación
    titulo              VARCHAR2(300)   NOT NULL,
    anio_lanzamiento    NUMBER(4)       NOT NULL,
    duracion            NUMBER,         -- En minutos. NULL para series/podcasts (duración por episodio)
    sinopsis            CLOB,
    clasificacion_edad  VARCHAR2(5)     NOT NULL,
    fecha_agregado      DATE            DEFAULT SYSDATE NOT NULL,
    es_original         NUMBER(1)       DEFAULT 0 NOT NULL,
    CONSTRAINT pk_contenido                 PRIMARY KEY (id_contenido),
    CONSTRAINT fk_contenido_categoria       FOREIGN KEY (id_categoria)
        REFERENCES categorias (id_categoria),
    CONSTRAINT fk_contenido_empleado        FOREIGN KEY (id_empleado)
        REFERENCES empleados (id_empleado),
    CONSTRAINT ck_contenido_clasificacion   CHECK (
        clasificacion_edad IN ('TP', '+7', '+13', '+16', '+18')
    ),
    CONSTRAINT ck_contenido_es_original     CHECK (es_original IN (0, 1)),
    CONSTRAINT ck_contenido_anio            CHECK (anio_lanzamiento BETWEEN 1888 AND 2100),
    -- [C6] Permite NULL (series/podcasts) o > 0 (películas, docs, música)
    CONSTRAINT ck_contenido_duracion        CHECK (duracion IS NULL OR duracion > 0)
);

COMMENT ON TABLE  contenido                     IS 'Catálogo central de contenido de la plataforma (películas, series, documentales, música, podcasts).';
COMMENT ON COLUMN contenido.id_contenido        IS 'PK autoincremental del contenido.';
COMMENT ON COLUMN contenido.id_categoria        IS 'FK a categorías. Define el tipo de contenido.';
COMMENT ON COLUMN contenido.id_empleado         IS 'FK al empleado responsable de la publicación del contenido.';
COMMENT ON COLUMN contenido.titulo              IS 'Título del contenido.';
COMMENT ON COLUMN contenido.anio_lanzamiento    IS 'Año de lanzamiento original. Validado entre 1888 y 2100.';
COMMENT ON COLUMN contenido.duracion            IS 'Duración en minutos. NULL para contenidos con episodios (series, podcasts). Si tiene valor, debe ser > 0.';
COMMENT ON COLUMN contenido.sinopsis            IS 'Descripción o sinopsis del contenido (CLOB para textos extensos).';
COMMENT ON COLUMN contenido.clasificacion_edad  IS 'Clasificación etaria: TP, +7, +13, +16, +18.';
COMMENT ON COLUMN contenido.fecha_agregado      IS 'Fecha en que se agregó el contenido a la plataforma. Default SYSDATE.';
COMMENT ON COLUMN contenido.es_original         IS 'Indica si es producción original de QuindioFlix (1) o licenciado (0).';

-- =============================================================================
-- 6. CONTENIDO_GENERO (N:M)
-- =============================================================================
-- Tabla puente entre contenido y géneros.
-- Un contenido puede tener múltiples géneros y un género agrupa múltiples contenidos.
CREATE TABLE contenido_genero (
    id_contenido    NUMBER NOT NULL,
    id_genero       NUMBER NOT NULL,
    CONSTRAINT pk_contenido_genero      PRIMARY KEY (id_contenido, id_genero),
    CONSTRAINT fk_cg_contenido          FOREIGN KEY (id_contenido)
        REFERENCES contenido (id_contenido) ON DELETE CASCADE,
    CONSTRAINT fk_cg_genero             FOREIGN KEY (id_genero)
        REFERENCES generos (id_genero) ON DELETE CASCADE
);

COMMENT ON TABLE  contenido_genero              IS 'Relación N:M entre contenido y géneros.';
COMMENT ON COLUMN contenido_genero.id_contenido IS 'FK al contenido.';
COMMENT ON COLUMN contenido_genero.id_genero    IS 'FK al género.';

-- =============================================================================
-- 7. RELACION_CONTENIDO (Reflexiva N:M con atributo)
-- =============================================================================
-- Relación reflexiva entre contenidos: secuelas, precuelas, remakes, spin-offs, etc.
-- PK surrogate + UNIQUE compuesto (origen, relacionado, tipo_relacion) para permitir
-- que dos contenidos tengan múltiples tipos de relación simultáneamente.
-- CHECK restringe los tipos de relación a valores válidos del negocio.
CREATE TABLE relacion_contenido (
    id_relacion                 NUMBER GENERATED ALWAYS AS IDENTITY,
    id_contenido_origen         NUMBER          NOT NULL,
    id_contenido_relacionado    NUMBER          NOT NULL,
    tipo_relacion               VARCHAR2(30)    NOT NULL,
    CONSTRAINT pk_relacion_contenido        PRIMARY KEY (id_relacion),
    CONSTRAINT uq_relacion_contenido        UNIQUE (id_contenido_origen, id_contenido_relacionado, tipo_relacion),
    CONSTRAINT fk_rc_origen                 FOREIGN KEY (id_contenido_origen)
        REFERENCES contenido (id_contenido) ON DELETE CASCADE,
    CONSTRAINT fk_rc_relacionado            FOREIGN KEY (id_contenido_relacionado)
        REFERENCES contenido (id_contenido) ON DELETE CASCADE,
    CONSTRAINT ck_rc_tipo_relacion          CHECK (
        tipo_relacion IN ('secuela', 'precuela', 'remake', 'spin-off', 'adaptacion', 'crossover')
    ),
    -- Evitar que un contenido se relacione consigo mismo
    CONSTRAINT ck_rc_no_auto_relacion       CHECK (id_contenido_origen <> id_contenido_relacionado)
);

COMMENT ON TABLE  relacion_contenido                        IS 'Relación reflexiva N:M entre contenidos con tipo de relación (secuela, precuela, remake, spin-off, etc.).';
COMMENT ON COLUMN relacion_contenido.id_relacion            IS 'PK autoincremental de la relación.';
COMMENT ON COLUMN relacion_contenido.id_contenido_origen    IS 'FK al contenido origen de la relación.';
COMMENT ON COLUMN relacion_contenido.id_contenido_relacionado IS 'FK al contenido destino de la relación.';
COMMENT ON COLUMN relacion_contenido.tipo_relacion          IS 'Tipo de relación: secuela, precuela, remake, spin-off, adaptacion, crossover.';

-- =============================================================================
-- 8. TEMPORADAS
-- =============================================================================
-- Solo aplica para contenidos tipo Series y Podcasts.
--
-- *** REGLA DE NEGOCIO NO IMPLEMENTABLE CON CHECK [C4] ***
-- La restricción de que solo contenidos de categoría 'Series' o 'Podcasts'
-- puedan tener temporadas NO se puede implementar con un CHECK constraint
-- (no puede referenciar otra tabla).
-- >>> DEBE IMPLEMENTARSE CON UN TRIGGER BEFORE INSERT/UPDATE que valide:
--     SELECT nombre FROM categorias WHERE id_categoria =
--       (SELECT id_categoria FROM contenido WHERE id_contenido = :NEW.id_contenido)
--     y rechace si el resultado no es 'Series' ni 'Podcasts'.
-- *******************************************************************
CREATE TABLE temporadas (
    id_temporada        NUMBER GENERATED ALWAYS AS IDENTITY,
    id_contenido        NUMBER      NOT NULL,
    numero_temporada    NUMBER(3)   NOT NULL,
    CONSTRAINT pk_temporadas            PRIMARY KEY (id_temporada),
    CONSTRAINT fk_temporadas_contenido  FOREIGN KEY (id_contenido)
        REFERENCES contenido (id_contenido) ON DELETE CASCADE,
    -- Un contenido no puede tener dos temporadas con el mismo número
    CONSTRAINT uq_temporadas_numero     UNIQUE (id_contenido, numero_temporada),
    CONSTRAINT ck_temporadas_numero     CHECK (numero_temporada > 0)
);

COMMENT ON TABLE  temporadas                    IS 'Temporadas de contenidos tipo Serie o Podcast. FK a contenido. TRIGGER requerido: solo Series/Podcasts pueden tener temporadas.';
COMMENT ON COLUMN temporadas.id_temporada       IS 'PK autoincremental de la temporada.';
COMMENT ON COLUMN temporadas.id_contenido       IS 'FK al contenido al que pertenece la temporada.';
COMMENT ON COLUMN temporadas.numero_temporada   IS 'Número secuencial de la temporada dentro del contenido. Debe ser > 0.';

-- =============================================================================
-- 9. EPISODIOS
-- =============================================================================
-- Cada episodio pertenece a una temporada.
-- titulo y duracion son atributos propios del episodio (no del contenido padre).
CREATE TABLE episodios (
    id_episodio         NUMBER GENERATED ALWAYS AS IDENTITY,
    id_temporada        NUMBER          NOT NULL,
    titulo              VARCHAR2(300)   NOT NULL,
    duracion            NUMBER          NOT NULL,  -- En minutos
    numero_episodio     NUMBER(4)       NOT NULL,
    CONSTRAINT pk_episodios             PRIMARY KEY (id_episodio),
    CONSTRAINT fk_episodios_temporada   FOREIGN KEY (id_temporada)
        REFERENCES temporadas (id_temporada) ON DELETE CASCADE,
    -- Un episodio no puede repetir número dentro de la misma temporada
    CONSTRAINT uq_episodios_numero      UNIQUE (id_temporada, numero_episodio),
    CONSTRAINT ck_episodios_duracion    CHECK (duracion > 0),
    CONSTRAINT ck_episodios_numero      CHECK (numero_episodio > 0)
);

COMMENT ON TABLE  episodios                 IS 'Episodios dentro de una temporada. Lleva título, duración y número propios.';
COMMENT ON COLUMN episodios.id_episodio     IS 'PK autoincremental del episodio.';
COMMENT ON COLUMN episodios.id_temporada    IS 'FK a la temporada a la que pertenece el episodio.';
COMMENT ON COLUMN episodios.titulo          IS 'Título del episodio.';
COMMENT ON COLUMN episodios.duracion        IS 'Duración del episodio en minutos. Debe ser > 0.';
COMMENT ON COLUMN episodios.numero_episodio IS 'Número del episodio dentro de la temporada. Debe ser > 0.';

-- =============================================================================
-- 10. PLANES
-- =============================================================================
-- Define los planes de suscripción.
-- max_perfiles limita cuántos perfiles puede crear un usuario con este plan.
CREATE TABLE planes (
    id_plan             NUMBER GENERATED ALWAYS AS IDENTITY,
    nombre              VARCHAR2(50)    NOT NULL,
    precio              NUMBER(10,2)    NOT NULL,
    cantidad_pantallas  NUMBER(2)       NOT NULL,
    max_perfiles        NUMBER(2)       NOT NULL,
    CONSTRAINT pk_planes            PRIMARY KEY (id_plan),
    CONSTRAINT uq_planes_nombre     UNIQUE (nombre),
    CONSTRAINT ck_planes_nombre     CHECK (
        nombre IN ('Basico', 'Estandar', 'Premium')
    ),
    CONSTRAINT ck_planes_precio             CHECK (precio > 0),
    CONSTRAINT ck_planes_pantallas          CHECK (cantidad_pantallas > 0),
    CONSTRAINT ck_planes_max_perfiles       CHECK (max_perfiles > 0)
);

COMMENT ON TABLE  planes                        IS 'Planes de suscripción: Básico, Estándar, Premium. Define precio, pantallas y perfiles máximos.';
COMMENT ON COLUMN planes.id_plan                IS 'PK autoincremental del plan.';
COMMENT ON COLUMN planes.nombre                 IS 'Nombre del plan. Restringido a Basico, Estandar, Premium.';
COMMENT ON COLUMN planes.precio                 IS 'Precio mensual del plan. Debe ser > 0.';
COMMENT ON COLUMN planes.cantidad_pantallas     IS 'Número máximo de pantallas simultáneas permitidas.';
COMMENT ON COLUMN planes.max_perfiles           IS 'Número máximo de perfiles que puede crear un usuario con este plan.';

-- =============================================================================
-- 11. ROLES [C2] — NUEVA TABLA
-- =============================================================================
-- Catálogo de roles de usuario.
-- Permite diferenciar usuarios normales de moderadores sin acoplar a empleados.
-- Los moderadores son USUARIOS con rol especial, NO empleados internos.
CREATE TABLE roles (
    id_rol      NUMBER GENERATED ALWAYS AS IDENTITY,
    nombre      VARCHAR2(50)    NOT NULL,
    descripcion VARCHAR2(200),
    CONSTRAINT pk_roles         PRIMARY KEY (id_rol),
    CONSTRAINT uq_roles_nombre  UNIQUE (nombre),
    CONSTRAINT ck_roles_nombre  CHECK (
        nombre IN ('usuario', 'moderador')
    )
);

COMMENT ON TABLE  roles             IS '[C2] Catálogo de roles: usuario (estándar) y moderador. Los moderadores son usuarios con rol, NO empleados.';
COMMENT ON COLUMN roles.id_rol      IS 'PK autoincremental del rol.';
COMMENT ON COLUMN roles.nombre      IS 'Nombre del rol. Restringido a usuario y moderador.';
COMMENT ON COLUMN roles.descripcion IS 'Descripción opcional del rol.';

-- =============================================================================
-- 12. USUARIOS [C2] — FK a roles agregada
-- =============================================================================
-- Relación reflexiva: usuario_referente → usuarios (sistema de referidos).
-- email es UNIQUE para login y comunicaciones.
-- FK a plan define el nivel de suscripción activa.
-- [C2] FK a roles: permite asignar rol (usuario normal o moderador).
CREATE TABLE usuarios (
    id_usuario          NUMBER GENERATED ALWAYS AS IDENTITY,
    id_plan             NUMBER          NOT NULL,
    id_rol              NUMBER          NOT NULL,  -- [C2] FK a roles
    nombre              VARCHAR2(150)   NOT NULL,
    email               VARCHAR2(200)   NOT NULL,
    telefono            VARCHAR2(20),
    fecha_nacimiento    DATE            NOT NULL,
    ciudad              VARCHAR2(100),
    fecha_registro      DATE            DEFAULT SYSDATE NOT NULL,
    usuario_referente   NUMBER,  -- NULL si no fue referido por nadie
    CONSTRAINT pk_usuarios              PRIMARY KEY (id_usuario),
    CONSTRAINT uq_usuarios_email        UNIQUE (email),
    CONSTRAINT fk_usuarios_plan         FOREIGN KEY (id_plan)
        REFERENCES planes (id_plan),
    CONSTRAINT fk_usuarios_rol          FOREIGN KEY (id_rol)
        REFERENCES roles (id_rol),
    CONSTRAINT fk_usuarios_referente    FOREIGN KEY (usuario_referente)
        REFERENCES usuarios (id_usuario),
    -- Un usuario no puede referirse a sí mismo
    CONSTRAINT ck_usuarios_no_auto_ref  CHECK (usuario_referente <> id_usuario)
);

COMMENT ON TABLE  usuarios                      IS 'Usuarios de la plataforma. FK a plan y a rol. Relación reflexiva para referidos.';
COMMENT ON COLUMN usuarios.id_usuario           IS 'PK autoincremental del usuario.';
COMMENT ON COLUMN usuarios.id_plan              IS 'FK al plan de suscripción activo del usuario.';
COMMENT ON COLUMN usuarios.id_rol               IS '[C2] FK al rol del usuario (usuario normal o moderador).';
COMMENT ON COLUMN usuarios.nombre               IS 'Nombre completo del usuario.';
COMMENT ON COLUMN usuarios.email                IS 'Email del usuario. UNIQUE para autenticación y comunicaciones.';
COMMENT ON COLUMN usuarios.telefono             IS 'Teléfono de contacto. Opcional.';
COMMENT ON COLUMN usuarios.fecha_nacimiento     IS 'Fecha de nacimiento del usuario.';
COMMENT ON COLUMN usuarios.ciudad               IS 'Ciudad de residencia del usuario. Opcional.';
COMMENT ON COLUMN usuarios.fecha_registro       IS 'Fecha de registro del usuario. Default SYSDATE.';
COMMENT ON COLUMN usuarios.usuario_referente    IS 'FK reflexiva: usuario que refirió a este usuario. NULL si no fue referido.';

-- =============================================================================
-- 13. BENEFICIOS_REFERIDOS
-- =============================================================================
-- Registra cada beneficio otorgado por el programa de referidos.
-- Separa la lógica de beneficios del registro de usuario para mantener 3FN.
-- Un usuario que refiere puede acumular múltiples beneficios (uno por cada referido).
CREATE TABLE beneficios_referidos (
    id_beneficio        NUMBER GENERATED ALWAYS AS IDENTITY,
    id_usuario_refiere  NUMBER          NOT NULL,  -- El que refiere (recibe el beneficio)
    id_usuario_referido NUMBER          NOT NULL,  -- El nuevo usuario registrado
    tipo_beneficio      VARCHAR2(100)   NOT NULL,
    descripcion         VARCHAR2(500),
    fecha_otorgado      DATE            DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_beneficios_referidos  PRIMARY KEY (id_beneficio),
    CONSTRAINT fk_br_usuario_refiere    FOREIGN KEY (id_usuario_refiere)
        REFERENCES usuarios (id_usuario),
    CONSTRAINT fk_br_usuario_referido   FOREIGN KEY (id_usuario_referido)
        REFERENCES usuarios (id_usuario),
    -- El que refiere y el referido no pueden ser la misma persona
    CONSTRAINT ck_br_distintos          CHECK (id_usuario_refiere <> id_usuario_referido),
    -- Un referido solo genera un beneficio para el mismo referente
    CONSTRAINT uq_br_par_unico         UNIQUE (id_usuario_refiere, id_usuario_referido)
);

COMMENT ON TABLE  beneficios_referidos                      IS 'Beneficios otorgados por el programa de referidos. FK al usuario que refiere y al referido.';
COMMENT ON COLUMN beneficios_referidos.id_beneficio         IS 'PK autoincremental del beneficio.';
COMMENT ON COLUMN beneficios_referidos.id_usuario_refiere   IS 'FK al usuario que realizó la referencia (quien recibe el beneficio).';
COMMENT ON COLUMN beneficios_referidos.id_usuario_referido  IS 'FK al usuario que fue referido (nuevo registro).';
COMMENT ON COLUMN beneficios_referidos.tipo_beneficio       IS 'Tipo o categoría del beneficio (ej. descuento, mes gratis, etc.).';
COMMENT ON COLUMN beneficios_referidos.descripcion          IS 'Descripción detallada del beneficio otorgado. Opcional.';
COMMENT ON COLUMN beneficios_referidos.fecha_otorgado       IS 'Fecha en que se otorgó el beneficio. Default SYSDATE.';

-- =============================================================================
-- 14. PERFILES
-- =============================================================================
-- Cada usuario puede tener múltiples perfiles (limitado por max_perfiles del plan).
-- tipo (adulto/infantil) filtra el contenido disponible según clasificación.
--
-- *** REGLA DE NEGOCIO NO IMPLEMENTABLE CON CHECK [C4] ***
-- 1) Límite de perfiles por usuario según planes.max_perfiles:
--    NO se puede implementar con CHECK (requiere consultar otra tabla).
--    >>> DEBE IMPLEMENTARSE CON UN TRIGGER BEFORE INSERT que cuente:
--        SELECT COUNT(*) FROM perfiles WHERE id_usuario = :NEW.id_usuario
--        y lo compare con el max_perfiles del plan del usuario.
--        Si COUNT >= max_perfiles → RAISE_APPLICATION_ERROR.
--
-- 2) Perfiles infantiles solo deben consumir contenido TP, +7, +13:
--    Esta restricción aplica en reproducciones, favoritos y calificaciones.
--    NO se puede implementar con CHECK (requiere consultar contenido.clasificacion_edad).
--    >>> DEBE IMPLEMENTARSE CON TRIGGERS BEFORE INSERT en reproducciones,
--        favoritos y calificaciones que validen:
--        Si el perfil es 'infantil', el contenido asociado debe tener
--        clasificacion_edad IN ('TP', '+7', '+13'). Rechazar +16 y +18.
-- *******************************************************************
CREATE TABLE perfiles (
    id_perfil   NUMBER GENERATED ALWAYS AS IDENTITY,
    id_usuario  NUMBER          NOT NULL,
    nombre      VARCHAR2(100)   NOT NULL,
    avatar      VARCHAR2(300),  -- Ruta o URL del avatar del perfil
    tipo        VARCHAR2(10)    NOT NULL,
    CONSTRAINT pk_perfiles          PRIMARY KEY (id_perfil),
    CONSTRAINT fk_perfiles_usuario  FOREIGN KEY (id_usuario)
        REFERENCES usuarios (id_usuario) ON DELETE CASCADE,
    CONSTRAINT ck_perfiles_tipo     CHECK (tipo IN ('adulto', 'infantil'))
);

COMMENT ON TABLE  perfiles              IS 'Perfiles de usuario. TRIGGER requerido: límite según plan.max_perfiles. Perfiles infantiles restringidos a contenido TP/+7/+13 (TRIGGER).';
COMMENT ON COLUMN perfiles.id_perfil    IS 'PK autoincremental del perfil.';
COMMENT ON COLUMN perfiles.id_usuario   IS 'FK al usuario propietario del perfil.';
COMMENT ON COLUMN perfiles.nombre       IS 'Nombre visible del perfil.';
COMMENT ON COLUMN perfiles.avatar       IS 'Ruta o URL de la imagen de avatar. Opcional.';
COMMENT ON COLUMN perfiles.tipo         IS 'Tipo de perfil: adulto o infantil. Determina filtro de contenido (TRIGGER).';

-- =============================================================================
-- 15. DISPOSITIVOS
-- =============================================================================
-- Catálogo cerrado de tipos de dispositivo desde los cuales se puede reproducir.
CREATE TABLE dispositivos (
    id_dispositivo  NUMBER GENERATED ALWAYS AS IDENTITY,
    nombre          VARCHAR2(30)    NOT NULL,
    CONSTRAINT pk_dispositivos          PRIMARY KEY (id_dispositivo),
    CONSTRAINT uq_dispositivos_nombre   UNIQUE (nombre),
    CONSTRAINT ck_dispositivos_nombre   CHECK (
        nombre IN ('celular', 'tablet', 'TV', 'computador')
    )
);

COMMENT ON TABLE  dispositivos                  IS 'Catálogo de tipos de dispositivo: celular, tablet, TV, computador.';
COMMENT ON COLUMN dispositivos.id_dispositivo   IS 'PK autoincremental del dispositivo.';
COMMENT ON COLUMN dispositivos.nombre           IS 'Nombre del tipo de dispositivo. Restringido por CHECK.';

-- =============================================================================
-- 16. REPRODUCCIONES
-- =============================================================================
-- Registro de cada sesión de reproducción.
-- RESTRICCIÓN CRÍTICA: Exactamente uno entre id_contenido e id_episodio debe ser NOT NULL.
--   - Si se reproduce una película/documental/música → id_contenido NOT NULL, id_episodio NULL.
--   - Si se reproduce un episodio de serie/podcast → id_episodio NOT NULL, id_contenido NULL.
-- Esto se implementa con CHECK (XOR lógico).
--
-- *** REGLA DE NEGOCIO ADICIONAL [C4] ***
-- Si el perfil es 'infantil', el contenido/episodio reproducido debe tener
-- clasificacion_edad IN ('TP', '+7', '+13'). IMPLEMENTAR CON TRIGGER.
-- *******************************************************************
CREATE TABLE reproducciones (
    id_reproduccion     NUMBER GENERATED ALWAYS AS IDENTITY,
    id_perfil           NUMBER          NOT NULL,
    id_contenido        NUMBER,         -- NULL si se reproduce un episodio
    id_episodio         NUMBER,         -- NULL si se reproduce contenido directo
    id_dispositivo      NUMBER          NOT NULL,
    fecha_inicio        TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
    fecha_fin           TIMESTAMP,      -- NULL si la reproducción está en curso
    porcentaje_avance   NUMBER(5,2)     DEFAULT 0 NOT NULL,
    CONSTRAINT pk_reproducciones            PRIMARY KEY (id_reproduccion),
    CONSTRAINT fk_repro_perfil              FOREIGN KEY (id_perfil)
        REFERENCES perfiles (id_perfil) ON DELETE CASCADE,
    CONSTRAINT fk_repro_contenido           FOREIGN KEY (id_contenido)
        REFERENCES contenido (id_contenido),
    CONSTRAINT fk_repro_episodio            FOREIGN KEY (id_episodio)
        REFERENCES episodios (id_episodio),
    CONSTRAINT fk_repro_dispositivo         FOREIGN KEY (id_dispositivo)
        REFERENCES dispositivos (id_dispositivo),
    -- XOR: exactamente uno de los dos debe ser NOT NULL
    CONSTRAINT ck_repro_contenido_xor_ep    CHECK (
        (id_contenido IS NOT NULL AND id_episodio IS NULL)
        OR
        (id_contenido IS NULL AND id_episodio IS NOT NULL)
    ),
    CONSTRAINT ck_repro_porcentaje          CHECK (porcentaje_avance BETWEEN 0 AND 100),
    -- fecha_fin debe ser posterior a fecha_inicio (si existe)
    CONSTRAINT ck_repro_fechas              CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);

COMMENT ON TABLE  reproducciones                    IS 'Registro de sesiones de reproducción. XOR entre contenido directo y episodio. TRIGGER requerido para restricción infantil.';
COMMENT ON COLUMN reproducciones.id_reproduccion    IS 'PK autoincremental de la reproducción.';
COMMENT ON COLUMN reproducciones.id_perfil          IS 'FK al perfil que realiza la reproducción.';
COMMENT ON COLUMN reproducciones.id_contenido       IS 'FK al contenido reproducido (películas, docs, música). NULL si es episodio.';
COMMENT ON COLUMN reproducciones.id_episodio        IS 'FK al episodio reproducido (series, podcasts). NULL si es contenido directo.';
COMMENT ON COLUMN reproducciones.id_dispositivo     IS 'FK al dispositivo desde el cual se reproduce.';
COMMENT ON COLUMN reproducciones.fecha_inicio       IS 'Timestamp del inicio de la reproducción.';
COMMENT ON COLUMN reproducciones.fecha_fin          IS 'Timestamp del fin de la reproducción. NULL si está en curso.';
COMMENT ON COLUMN reproducciones.porcentaje_avance  IS 'Porcentaje de avance de la reproducción (0.00 a 100.00).';

-- =============================================================================
-- 17. FAVORITOS (N:M)
-- =============================================================================
-- Relación N:M entre perfiles y contenidos marcados como favoritos.
-- PK compuesta evita duplicados (un perfil marca un contenido como favorito una sola vez).
CREATE TABLE favoritos (
    id_perfil       NUMBER  NOT NULL,
    id_contenido    NUMBER  NOT NULL,
    fecha_agregado  DATE    DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_favoritos         PRIMARY KEY (id_perfil, id_contenido),
    CONSTRAINT fk_fav_perfil        FOREIGN KEY (id_perfil)
        REFERENCES perfiles (id_perfil) ON DELETE CASCADE,
    CONSTRAINT fk_fav_contenido     FOREIGN KEY (id_contenido)
        REFERENCES contenido (id_contenido) ON DELETE CASCADE
);

COMMENT ON TABLE  favoritos                 IS 'Relación N:M entre perfiles y contenidos favoritos.';
COMMENT ON COLUMN favoritos.id_perfil       IS 'FK al perfil que marca el contenido como favorito.';
COMMENT ON COLUMN favoritos.id_contenido    IS 'FK al contenido marcado como favorito.';
COMMENT ON COLUMN favoritos.fecha_agregado  IS 'Fecha en que se agregó a favoritos.';

-- =============================================================================
-- 18. CALIFICACIONES
-- =============================================================================
-- Un perfil puede calificar un contenido una sola vez (PK compuesta).
-- Estrellas restringidas de 1 a 5 con CHECK.
-- reseña es opcional (CLOB para textos extensos).
CREATE TABLE calificaciones (
    id_perfil       NUMBER      NOT NULL,
    id_contenido    NUMBER      NOT NULL,
    estrellas       NUMBER(1)   NOT NULL,
    resenia         CLOB,       -- Reseña textual opcional
    fecha           DATE        DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_calificaciones        PRIMARY KEY (id_perfil, id_contenido),
    CONSTRAINT fk_cal_perfil            FOREIGN KEY (id_perfil)
        REFERENCES perfiles (id_perfil) ON DELETE CASCADE,
    CONSTRAINT fk_cal_contenido         FOREIGN KEY (id_contenido)
        REFERENCES contenido (id_contenido) ON DELETE CASCADE,
    CONSTRAINT ck_cal_estrellas         CHECK (estrellas BETWEEN 1 AND 5)
);

COMMENT ON TABLE  calificaciones                IS 'Calificaciones de contenido por perfil. Estrellas (1-5) y reseña opcional.';
COMMENT ON COLUMN calificaciones.id_perfil      IS 'FK al perfil que califica.';
COMMENT ON COLUMN calificaciones.id_contenido   IS 'FK al contenido calificado.';
COMMENT ON COLUMN calificaciones.estrellas      IS 'Puntuación de 1 a 5 estrellas.';
COMMENT ON COLUMN calificaciones.resenia        IS 'Reseña textual opcional (CLOB).';
COMMENT ON COLUMN calificaciones.fecha          IS 'Fecha de la calificación.';

-- =============================================================================
-- 19. REPORTES [C1][C5] — CORREGIDO
-- =============================================================================
-- Un usuario reporta un contenido por algún motivo.
-- [C1] CORRECCIÓN: El moderador es un USUARIO con rol 'moderador', NO un empleado.
--      FK id_moderador ahora apunta a usuarios (antes apuntaba a empleados).
--      La validación de que el moderador tenga rol 'moderador' requiere TRIGGER.
-- [C5] CORRECCIÓN: Si el estado es 'resuelto' o 'rechazado', el moderador y la
--      fecha de resolución deben estar informados (CHECK implementado).
--
-- *** REGLA DE NEGOCIO ADICIONAL ***
-- Validar que id_moderador apunte a un usuario con id_rol correspondiente
-- al rol 'moderador'. NO se puede implementar con CHECK.
-- >>> DEBE IMPLEMENTARSE CON UN TRIGGER BEFORE INSERT/UPDATE.
-- *******************************************************************
CREATE TABLE reportes (
    id_reporte          NUMBER GENERATED ALWAYS AS IDENTITY,
    id_usuario          NUMBER          NOT NULL,  -- Usuario que reporta
    id_contenido        NUMBER          NOT NULL,  -- Contenido reportado
    motivo              VARCHAR2(500)   NOT NULL,
    estado              VARCHAR2(20)    DEFAULT 'pendiente' NOT NULL,
    fecha_creacion      DATE            DEFAULT SYSDATE NOT NULL,
    id_moderador        NUMBER,         -- [C1] FK a usuarios (moderador = usuario con rol)
    fecha_resolucion    DATE,
    CONSTRAINT pk_reportes              PRIMARY KEY (id_reporte),
    CONSTRAINT fk_rpt_usuario           FOREIGN KEY (id_usuario)
        REFERENCES usuarios (id_usuario),
    CONSTRAINT fk_rpt_contenido         FOREIGN KEY (id_contenido)
        REFERENCES contenido (id_contenido),
    -- [C1] FK ahora apunta a usuarios, NO a empleados
    CONSTRAINT fk_rpt_moderador         FOREIGN KEY (id_moderador)
        REFERENCES usuarios (id_usuario),
    CONSTRAINT ck_rpt_estado            CHECK (
        estado IN ('pendiente', 'en_revision', 'resuelto', 'rechazado')
    ),
    -- La fecha de resolución debe ser >= fecha de creación (si existe)
    CONSTRAINT ck_rpt_fecha_resolucion  CHECK (
        fecha_resolucion IS NULL OR fecha_resolucion >= fecha_creacion
    ),
    -- [C5] Si estado es resuelto o rechazado, moderador y fecha_resolucion son obligatorios
    CONSTRAINT ck_rpt_estado_resuelto   CHECK (
        (estado NOT IN ('resuelto', 'rechazado'))
        OR
        (id_moderador IS NOT NULL AND fecha_resolucion IS NOT NULL)
    ),
    -- Un usuario no puede moderar su propio reporte
    CONSTRAINT ck_rpt_no_auto_moderar   CHECK (id_usuario <> id_moderador)
);

COMMENT ON TABLE  reportes                      IS '[C1] Reportes de contenido. Moderador = usuario con rol moderador (NO empleado). TRIGGER requerido para validar rol.';
COMMENT ON COLUMN reportes.id_reporte           IS 'PK autoincremental del reporte.';
COMMENT ON COLUMN reportes.id_usuario           IS 'FK al usuario que realiza el reporte.';
COMMENT ON COLUMN reportes.id_contenido         IS 'FK al contenido reportado.';
COMMENT ON COLUMN reportes.motivo               IS 'Motivo o descripción del reporte.';
COMMENT ON COLUMN reportes.estado               IS 'Estado del reporte: pendiente, en_revision, resuelto, rechazado.';
COMMENT ON COLUMN reportes.fecha_creacion       IS 'Fecha de creación del reporte.';
COMMENT ON COLUMN reportes.id_moderador         IS '[C1] FK al usuario moderador que gestiona el reporte. NULL si aún no asignado. TRIGGER valida rol.';
COMMENT ON COLUMN reportes.fecha_resolucion     IS 'Fecha de resolución del reporte. NULL si no resuelto. Obligatorio si estado = resuelto/rechazado.';

-- =============================================================================
-- 20. PAGOS [C3] — NUEVA TABLA
-- =============================================================================
-- Registra los pagos de suscripción de los usuarios.
-- Cada pago está vinculado a un usuario (FK).
-- CHECKs obligan: monto > 0, métodos de pago y estados válidos.
CREATE TABLE pagos (
    id_pago         NUMBER GENERATED ALWAYS AS IDENTITY,
    id_usuario      NUMBER          NOT NULL,
    fecha_pago      DATE            DEFAULT SYSDATE NOT NULL,
    monto           NUMBER(10,2)    NOT NULL,
    metodo_pago     VARCHAR2(30)    NOT NULL,
    estado          VARCHAR2(20)    DEFAULT 'pendiente' NOT NULL,
    referencia      VARCHAR2(100),  -- Referencia externa de la transacción (pasarela de pago)
    CONSTRAINT pk_pagos                 PRIMARY KEY (id_pago),
    CONSTRAINT fk_pagos_usuario         FOREIGN KEY (id_usuario)
        REFERENCES usuarios (id_usuario),
    CONSTRAINT ck_pagos_monto           CHECK (monto > 0),
    CONSTRAINT ck_pagos_metodo          CHECK (
        metodo_pago IN ('tarjeta_credito', 'tarjeta_debito', 'PSE', 'efectivo', 'paypal')
    ),
    CONSTRAINT ck_pagos_estado          CHECK (
        estado IN ('pendiente', 'aprobado', 'rechazado', 'reembolsado')
    )
);

COMMENT ON TABLE  pagos                 IS '[C3] Pagos de suscripción. Registra monto, método de pago y estado de cada transacción.';
COMMENT ON COLUMN pagos.id_pago         IS 'PK autoincremental del pago.';
COMMENT ON COLUMN pagos.id_usuario      IS 'FK al usuario que realiza el pago.';
COMMENT ON COLUMN pagos.fecha_pago      IS 'Fecha del pago. Default SYSDATE.';
COMMENT ON COLUMN pagos.monto           IS 'Monto pagado. Debe ser > 0.';
COMMENT ON COLUMN pagos.metodo_pago     IS 'Método de pago: tarjeta_credito, tarjeta_debito, PSE, efectivo, paypal.';
COMMENT ON COLUMN pagos.estado          IS 'Estado del pago: pendiente, aprobado, rechazado, reembolsado.';
COMMENT ON COLUMN pagos.referencia      IS 'Referencia externa de la transacción (código de pasarela de pago). Opcional.';

-- =============================================================================
-- FIN DEL DDL CORREGIDO — QUINDIOFLIX v2.0
-- =============================================================================
-- Resumen del modelo:
--   20 tablas (18 originales + roles + pagos)
--   3FN estricta (sin redundancias, sin dependencias transitivas)
--
--   Relaciones N:M:
--     - contenido_genero (contenido ↔ género)
--     - favoritos (perfil ↔ contenido)
--
--   Relaciones reflexivas:
--     - usuarios.usuario_referente → usuarios (referidos)
--     - empleados.id_supervisor → empleados (jerarquía de supervisión)
--     - relacion_contenido (contenido ↔ contenido con tipo)
--
--   Restricciones CHECK implementadas:
--     - Categorías, departamentos, dispositivos, roles, planes (catálogos cerrados)
--     - clasificacion_edad, es_original, tipo perfil, estrellas 1-5
--     - Métodos de pago, estados de pago, estados de reporte
--     - XOR contenido/episodio en reproducciones
--     - Porcentaje entre 0 y 100
--     - Coherencia de fechas (fecha_fin >= fecha_inicio, fecha_resolucion >= fecha_creacion)
--     - Estado resuelto/rechazado requiere moderador + fecha_resolucion
--     - Anti-autorrelación en usuarios, reportes, relacion_contenido
--     - Duración NULL o > 0
--
--   REGLAS QUE REQUIEREN TRIGGER (no implementables con CHECK):
--     [T1] Solo contenidos de categoría 'Series' o 'Podcasts' pueden tener temporadas
--     [T2] Límite de perfiles por usuario según planes.max_perfiles
--     [T3] Perfiles infantiles solo pueden consumir contenido con clasificacion_edad
--          IN ('TP', '+7', '+13') — aplica en reproducciones, favoritos, calificaciones
--     [T4] Validar que reportes.id_moderador apunte a usuario con rol 'moderador'
--   (Ya implementados en quindioflix_triggers.sql)
-- =============================================================================
