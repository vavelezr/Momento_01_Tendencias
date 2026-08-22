-- Punto 3 — Ingesta semi-estructurada (Momento 2, Sesión 5).
-- Exploración de LATERAL FLATTEN sobre RAW_BUSINESS_HOURS y materialización en STAGING.
-- Correr con YELP_LOADER_ROLE, después de 01_setup_stage_and_raw.sql.

USE ROLE YELP_LOADER_ROLE;
USE WAREHOUSE WH_YELP_XS;
USE DATABASE YELP_GOODYEAR_DW;

-- Notación de punto (raw_data:business_id) para el campo escalar, LATERAL FLATTEN para
-- desenrollar el array anidado — una fila de salida por día de la semana que el negocio
-- reportó. Un negocio con menos de 7 días en weekly_hours simplemente aporta menos filas,
-- no filas con NULL (el dato de origen no trae huecos dentro de un día ya reportado).
SELECT
    raw_data:business_id::STRING   AS business_id,
    h.value:day_of_week::STRING    AS day_of_week,
    h.value:open_time::STRING      AS open_time,
    h.value:close_time::STRING     AS close_time
FROM RAW.RAW_BUSINESS_HOURS,
     LATERAL FLATTEN(input => raw_data:weekly_hours) h
LIMIT 10;

USE SCHEMA STAGING;

CREATE TABLE IF NOT EXISTS STG_BUSINESS_HOURS_FLATTENED (
    business_id  VARCHAR(50)  COMMENT 'FK -> RAW.BUSINESS.BUSINESS_ID (capa relacional, Sesión 4).',
    day_of_week  VARCHAR(20),
    open_time    VARCHAR(10),
    close_time   VARCHAR(10)
);

INSERT INTO STG_BUSINESS_HOURS_FLATTENED (business_id, day_of_week, open_time, close_time)
SELECT
    raw_data:business_id::STRING,
    h.value:day_of_week::STRING,
    h.value:open_time::STRING,
    h.value:close_time::STRING
FROM RAW.RAW_BUSINESS_HOURS,
     LATERAL FLATTEN(input => raw_data:weekly_hours) h;

SELECT COUNT(*) AS total_filas_horario FROM STG_BUSINESS_HOURS_FLATTENED;

-- Negocios con menos días reportados que el resto — prueba de que el FLATTEN desenrolló
-- el array completo (cantidades variables por negocio), no solo la primera posición.
SELECT business_id, COUNT(*) AS dias_con_horario
FROM STG_BUSINESS_HOURS_FLATTENED
GROUP BY business_id
ORDER BY dias_con_horario ASC
LIMIT 5;
