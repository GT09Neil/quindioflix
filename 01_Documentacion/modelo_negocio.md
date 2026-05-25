# Documento 1: Estructura del Proyecto y Modelo de Negocio - QuindioFlix

Este documento cumple con el **Entregable 1** del proyecto y detalla tanto el entorno conceptual sobre el cual se construyó la base de datos relacional, como la guía de navegación de los archivos entregados.

## 📂 Organización y Guía de Revisión
El proyecto ha sido rigurosamente estructurado en carpetas para facilitar su calificación por parte del cuerpo docente. Para ejecutar el proyecto sin errores, se sugiere correr los scripts en el orden de las carpetas:

1. **`01_Documentacion/`**: Contiene los reportes obligatorios (Modelo de Negocio y Sustentación Técnica).
2. **`02_Modelo_Datos/`**: Aloja la base arquitectónica. 
   - `quindioflix_tablespaces.sql`: Definición física en disco (Datafiles).
   - `quindioflix_ddl.sql`: Modelo Físico materializado con constraints estrictos.
3. **`03_Logica_Negocio/`**: Encapsula las reglas exigidas en el *Núcleo 2 y 3*.
   - `quindioflix_triggers.sql`: 4 Disparadores obligatorios de validación de estado y consumo.
   - `quindioflix_plsql.sql`: Cursores, Funciones, Excepciones y Procedimientos.
   - `quindioflix_transacciones.sql`: Lógicas atómicas (COMMIT/ROLLBACK) y escenario de concurrencia.
4. **`04_Consultas_y_Reportes/`**: Alberga la inteligencia de datos (*Núcleo 1 y 4*).
   - `quindioflix_consultas.sql`: Cubre PIVOT, UNPIVOT, ROLLUP, CUBE y Vistas Materializadas.
   - `quindioflix_indices.sql`: Creación de índices y análisis de rendimiento EXPLAIN PLAN.
5. **`05_Seguridad/`**: Administra los accesos (*Núcleo 5*).
   - `quindioflix_seguridad.sql`: Configuración de Roles, Privilegios GRANT, y límite de recursos por PROFILE.
6. **`06_Datos_Prueba/`**: Satisface el requerimiento de carga masiva.
   - `quindioflix_dml.sql`: Bloques PL/SQL aleatorios para asegurar la "Asimetría" de la información (30 usuarios, 50 perfiles, 200 reproducciones).

---

## 1. Identificación de los Actores del Sistema
El sistema cuenta con múltiples actores que interactúan con la plataforma, divididos en clientes y personal interno:
- **Usuario Registrado (Cliente Principal):** Adquiere una suscripción, paga mensualidades y gestiona su plan.
- **Perfil (Espectador):** Sub-actor que hereda del usuario. Puede ser 'Adulto' o 'Infantil'. Es quien consume el catálogo.
- **Moderador:** Usuario normal de la plataforma con un `ROL` en base de datos otorgado para resolver reportes.
- **Empleado de Contenido:** Sube nuevos títulos y etiqueta películas/series en el catálogo.
- **Agente de Soporte:** Empleado que maneja cambios manuales de planes y facturación.

## 2. Procesos de Negocio Principales
1. **Suscripción y Registro:** Un usuario se registra proporcionando sus datos, elige un plan (Básico, Estándar, Premium) y el sistema consolida el pago, abriendo su perfil predeterminado.
2. **Visualización de Contenido:** Un perfil selecciona un dispositivo e inicia la reproducción. El sistema almacena la sesión calculando el porcentaje de avance respecto a la duración total.
3. **Facturación Mensual:** El sistema realiza un barrido por usuarios activos, calcula montos (aplicando descuentos correspondientes) e inserta el estado del cobro.
4. **Moderación de Contenido:** Usuarios denuncian contenido, encolando reportes. Los moderadores intervienen para pasar su estado a resuelto/rechazado.
5. **Gestión Jerárquica del Catálogo:** El contenido se bifurca lógicamente; las películas se almacenan estáticas, mientras las series despliegan dependencias a temporadas y estas a episodios.

## 3. Reglas de Negocio (Abstracción Analítica)
1. **Límite Estricto de Perfiles:** Un usuario no puede crear más perfiles de los definidos por la capacidad máxima de su plan. *(Manejado por Trigger)*.
2. **Restricción de Downgrade:** Un usuario no puede bajar la categoría de su plan si posee en el momento más perfiles activos de los que permite el plan destino. *(Manejado por PL/SQL)*.
3. **Control Parental Riguroso:** Los perfiles 'infantiles' tienen bloqueado el consumo, favoriteo y calificación de cualquier contenido que no sea clasificado como 'TP', '+7' o '+13'. *(Manejado por Triggers)*.
4. **Barrera de Calidad (50%):** Un espectador no puede emitir un voto de calificación si no ha visualizado al menos la mitad (50%) de la película o episodio. *(Manejado por Trigger)*.
5. **Estructura Exclusiva de Series:** Solo los formatos de tipo 'Series' o 'Podcasts' están habilitados para crear sub-entidades de Temporadas. *(Manejado por Trigger)*.
6. **XOR Lógico de Reproducción:** Un hit de consumo debe enlazar obligatoriamente o bien a una película directa, o bien a un episodio. Apuntar a ambos es una violación de integridad. *(Manejado por Constraint CHECK)*.
7. **Beneficio Cruzado de Referidos:** Los usuarios con cuentas activas que logren referir a nuevos suscriptores, ganan un descuento monetario en su propia próxima factura. *(Manejado por Funciones PL/SQL)*.
8. **Segregación de Funciones de Moderación:** Nadie puede moderar el mismo reporte que ha originado. Además, el moderador no es un empleado de nómina, sino un usuario de la plataforma con privilegios elevados. *(Manejado por Triggers y Constraint de auto-relación)*.
9. **Fidelización por Antigüedad:** El sistema premia con 10% de reducción en la factura a usuarios con más de un año inscritos, y un 15% superando los dos años. *(Manejado por Funciones PL/SQL)*.
10. **Aislamiento por Mora:** 30 días posteriores al vencimiento de un pago infructuoso, la cuenta queda 'INACTIVA' y se abortan todos los intentos de reproducción por parte de sus perfiles. *(Manejado por Cursor y Transacciones)*.

## 4. Restricciones del Dominio para Atributos Clave
- **Planes de Suscripción:** Solo pueden tomar los valores nominales `('Basico', 'Estandar', 'Premium')`.
- **Precios e Ingresos:** Todo campo de moneda y duración es numérico estricto mayor a cero `(> 0)`.
- **Clasificación Etaria:** Restringido estáticamente a `('TP', '+7', '+13', '+16', '+18')`.
- **Rango de Puntuación:** Las estrellas en reseñas oscilan en un Integer de `1` a `5`.
- **Avance Porcentual:** El porcentaje de visualización se restringe a decimales exactos entre `0.00` y `100.00`.
- **Estados Operativos:** Pagos confinados a `('pendiente', 'aprobado', 'rechazado', 'reembolsado')`. Cuentas confinadas a `('ACTIVO', 'INACTIVO', 'SUSPENDIDO')`. Reportes limitados a `('pendiente', 'en_revision', 'resuelto', 'rechazado')`.
