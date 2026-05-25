# Guía de Ejecución del Proyecto QuindioFlix

Esta guía detalla los pasos exactos y el orden riguroso en el que deben compilarse los scripts SQL para levantar la base de datos completa de QuindioFlix sin disparar errores por dependencias.

## ⚠️ Pre-requisitos Críticos
1. Tener instalado un motor **Oracle Database** (Express Edition o Enterprise).
2. Utilizar un cliente compatible con scripts como **SQL Developer** o **SQL*Plus**.
3. **Privilegios de Administrador (SYSDBA):** Los primeros y últimos pasos requieren permisos elevados para poder interactuar con el disco duro (Crear Tablespaces físicos) y alterar el catálogo de seguridad (Crear usuarios reales).

---

## 🏃 Secuencia de Ejecución

### PASO 1: Creación del Entorno Físico (Carpeta `02_Modelo_Datos`)
Debes conectarte a Oracle usando una cuenta con rol `SYSDBA` (por ejemplo, el usuario `SYSTEM` o `SYS`).
1. Ejecuta el script **`02_Modelo_Datos/quindioflix_tablespaces.sql`**.
   *Nota: Este script creará los archivos físicos (`.dbf`) a nivel de sistema operativo para soportar la partición futura de la tabla. Si falla por rutas de disco, asegúrate de correr tu Oracle localmente.*

### PASO 2: Creación del Modelo Relacional (Carpeta `02_Modelo_Datos`)
1. Ejecuta el script **`02_Modelo_Datos/quindioflix_ddl.sql`**.
   *Nota: Esto generará las tablas en 3FN, establecerá las Claves Foráneas (FK), activará los Constraints de integridad y enlazará la tabla `reproducciones` a los tablespaces físicos creados en el Paso 1.*

### PASO 3: Disparadores de Reglas (Carpeta `03_Logica_Negocio`)
1. Ejecuta el script **`03_Logica_Negocio/quindioflix_triggers.sql`**.
   *Nota: Es mandatorio ejecutar los triggers **antes** de insertar cualquier dato de prueba. Los triggers serán los vigilantes que garantizarán que las inserciones masivas posteriores no violen las reglas de negocio (como calificaciones prematuras o límites de perfiles).*

### PASO 4: Inserción de Volumen y Asimetría (Carpeta `06_Datos_Prueba`)
1. Ejecuta el script **`06_Datos_Prueba/quindioflix_dml.sql`**.
   *Nota: Este script compila bloques PL/SQL que aprovechan `DBMS_RANDOM` para generar miles de registros asimétricos (200 reproducciones, 30 usuarios en múltiples ciudades, etc.). Esto tarda un par de segundos. Es posible que Oracle levante algunas "Warnings" sobre variables aleatorias omitidas, son normales y parte de la lógica de forzado de fallos.*

### PASO 5: Programación Avanzada PL/SQL (Carpeta `03_Logica_Negocio`)
1. Ejecuta el script **`03_Logica_Negocio/quindioflix_plsql.sql`**.
   *Nota: Esto compilará las Funciones, Procedimientos, Excepciones y Cursores solicitados en el Núcleo 2 dejándolos listos en el motor.*
2. Opcional: Abre y analiza el contenido de **`03_Logica_Negocio/quindioflix_transacciones.sql`** para ver o ejecutar ejemplos manuales de rutinas atómicas (Registro completo, Renovación masiva).

### PASO 6: Reportes Analíticos (Carpeta `04_Consultas_y_Reportes`)
1. Ejecuta primero **`04_Consultas_y_Reportes/quindioflix_consultas.sql`**.
   *Nota: Aquí Oracle detendrá la ejecución y te pedirá por pantalla el valor para las variables de sustitución `&` (e.g., ingresa 'Bogota', 'Accion'). Acto seguido procesará los pesados PIVOT, ROLLUP y finalmente construirá las Vistas Materializadas.*
2. Ejecuta **`04_Consultas_y_Reportes/quindioflix_indices.sql`** para presenciar cómo los B-Trees optimizan los tiempos de respuesta leyendo el `EXPLAIN PLAN`.

### PASO 7: Despliegue de Seguridad (Carpeta `05_Seguridad`)
Debe ejecutarse volviendo a tu cuenta administrativa inicial (`SYSDBA`).
1. Ejecuta el script **`05_Seguridad/quindioflix_seguridad.sql`**.
   *Nota: Compilará el Profile de blindaje, creará los 4 roles restrictivos de la compañía y desplegará los 4 usuarios de prueba, asignándoles permisos mediante instrucciones `GRANT`.*

---

## ✅ Lista de Verificación Rápida
Si seguiste estrictamente este orden, tu entorno transaccional está en un estado óptimo (100%). Para auditarlo rápidamente, abre una ventana y lanza esta sentencia:
```sql
SELECT COUNT(*) FROM reproducciones;
```
Deberías recibir un retorno cercano o igual a **200**, el cual además sabrás (por el Paso 1) que está fragmentado entre el año 2024, 2025 y 2026.
