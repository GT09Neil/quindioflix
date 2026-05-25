-- =============================================================================
-- QUINDIOFLIX - SEGURIDAD Y ROLES DE BASE DE DATOS (Oracle SQL)
-- Núcleo 5: Administración de acceso a BD
-- =============================================================================

-- =============================================================================
-- 1. CREACIÓN DE PERFIL (PROFILE) PARA LÍMITES DE RECURSOS
-- Limita max 5 sesiones concurrentes por usuario, inactividad de 30 min, 
-- y bloquea cuenta tras 3 intentos fallidos de login a la BD.
-- =============================================================================
CREATE PROFILE prof_quindioflix LIMIT
    SESSIONS_PER_USER       5
    IDLE_TIME               30
    FAILED_LOGIN_ATTEMPTS   3
    PASSWORD_LOCK_TIME      1;

-- =============================================================================
-- 2. CREACIÓN DE ROLES
-- =============================================================================
CREATE ROLE ROL_ADMIN;
CREATE ROLE ROL_ANALISTA;
CREATE ROLE ROL_SOPORTE;
CREATE ROLE ROL_CONTENIDO;

-- =============================================================================
-- 3. ASIGNACIÓN DE PRIVILEGIOS A ROLES
-- =============================================================================

-- A) ROL_ADMIN: CRUD en todo, ejecutar SPs.
GRANT ALL PRIVILEGES ON usuarios TO ROL_ADMIN;
GRANT ALL PRIVILEGES ON perfiles TO ROL_ADMIN;
GRANT ALL PRIVILEGES ON contenido TO ROL_ADMIN;
GRANT ALL PRIVILEGES ON pagos TO ROL_ADMIN;
GRANT EXECUTE ON sp_registro_completo TO ROL_ADMIN;
GRANT EXECUTE ON sp_renovacion_mensual TO ROL_ADMIN;
GRANT EXECUTE ON sp_eliminar_cuenta TO ROL_ADMIN;

-- B) ROL_ANALISTA: SELECT en todas las tablas para reportes.
GRANT SELECT ON usuarios TO ROL_ANALISTA;
GRANT SELECT ON perfiles TO ROL_ANALISTA;
GRANT SELECT ON pagos TO ROL_ANALISTA;
GRANT SELECT ON reproducciones TO ROL_ANALISTA;
GRANT SELECT ON contenido TO ROL_ANALISTA;

-- C) ROL_SOPORTE: Ver usuarios, perfiles, pagos. Modificar pagos.
GRANT SELECT ON usuarios TO ROL_SOPORTE;
GRANT SELECT ON perfiles TO ROL_SOPORTE;
GRANT SELECT, INSERT, UPDATE ON pagos TO ROL_SOPORTE;
-- (Nota: SP_CAMBIAR_PLAN se asume como procedimiento, si existiera:)
-- GRANT EXECUTE ON sp_cambiar_plan TO ROL_SOPORTE;

-- D) ROL_CONTENIDO: Gestionar catálogo, ver métricas.
GRANT SELECT, INSERT, UPDATE, DELETE ON contenido TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON temporadas TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON episodios TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON generos TO ROL_CONTENIDO;
GRANT SELECT ON reproducciones TO ROL_CONTENIDO;
GRANT SELECT ON calificaciones TO ROL_CONTENIDO;

-- =============================================================================
-- 4. CREACIÓN DE USUARIOS DE BD Y ASIGNACIÓN DE ROLES Y PROFILE
-- =============================================================================

-- Administrador
CREATE USER admin_qf IDENTIFIED BY "Admin123**" PROFILE prof_quindioflix;
GRANT CREATE SESSION TO admin_qf;
GRANT ROL_ADMIN TO admin_qf;

-- Analista de datos
CREATE USER analista_qf IDENTIFIED BY "Data123**" PROFILE prof_quindioflix;
GRANT CREATE SESSION TO analista_qf;
GRANT ROL_ANALISTA TO analista_qf;

-- Soporte
CREATE USER soporte_qf IDENTIFIED BY "Support123**" PROFILE prof_quindioflix;
GRANT CREATE SESSION TO soporte_qf;
GRANT ROL_SOPORTE TO soporte_qf;

-- Gestor de contenido
CREATE USER contenido_qf IDENTIFIED BY "Content123**" PROFILE prof_quindioflix;
GRANT CREATE SESSION TO contenido_qf;
GRANT ROL_CONTENIDO TO contenido_qf;

-- =============================================================================
-- 5. DEMOSTRACIÓN DE PERMISOS (Ejemplo de intento no permitido)
-- =============================================================================
/*
-- Si nos conectamos como soporte_qf e intentamos borrar un contenido:
CONNECT soporte_qf/Support123**;

DELETE FROM contenido WHERE id_contenido = 1;
-- ORA-01031: insufficient privileges (Error: privilegios insuficientes)
-- Esto demuestra que el ROL_SOPORTE no tiene permisos de DELETE en contenido,
-- cumpliendo con la restricción de seguridad asignada.
*/
