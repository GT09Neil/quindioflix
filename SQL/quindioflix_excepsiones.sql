-- =============================================================================
-- SECCIÓN 1: EXCEPCIONES PERSONALIZADAS (Paquete de excepciones)
-- =============================================================================
-- Se centraliza en un paquete para poder reutilizarlas en todos los objetos.
CREATE OR REPLACE PACKAGE pkg_quindioflix_excepciones AS
 
    -- Usuario no encontrado
    ex_usuario_no_existe        EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_usuario_no_existe, -20001);
    MSG_USUARIO_NO_EXISTE       CONSTANT VARCHAR2(200) := 'El usuario especificado no existe en el sistema.';
 
    -- Plan no encontrado
    ex_plan_no_existe           EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_plan_no_existe, -20002);
    MSG_PLAN_NO_EXISTE          CONSTANT VARCHAR2(200) := 'El plan de suscripción especificado no existe.';
 
    -- Email ya registrado
    ex_email_duplicado          EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_email_duplicado, -20003);
    MSG_EMAIL_DUPLICADO         CONSTANT VARCHAR2(200) := 'El correo electrónico ya está registrado en el sistema.';
 
    -- Plan igual al actual (sin cambio real)
    ex_plan_igual               EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_plan_igual, -20004);
    MSG_PLAN_IGUAL              CONSTANT VARCHAR2(200) := 'El usuario ya se encuentra suscrito a ese plan.';
 
    -- Contenido no encontrado
    ex_contenido_no_existe      EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_contenido_no_existe, -20005);
    MSG_CONTENIDO_NO_EXISTE     CONSTANT VARCHAR2(200) := 'El contenido especificado no existe en el catálogo.';
 
    -- Datos obligatorios ausentes
    ex_datos_incompletos        EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_datos_incompletos, -20006);
    MSG_DATOS_INCOMPLETOS       CONSTANT VARCHAR2(200) := 'Se deben proporcionar todos los datos obligatorios.';
 
    -- Referente inválido (se refiere a sí mismo o no existe)
    ex_referente_invalido       EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_referente_invalido, -20007);
    MSG_REFERENTE_INVALIDO      CONSTANT VARCHAR2(200) := 'El usuario referente es inválido o no existe.';
 
END pkg_quindioflix_excepciones;