-- Punto 3 — Ingesta semi-estructurada (Momento 2, Sesión 5).
-- Fuente elegida: horario semanal por negocio, agrupado en un array anidado
-- (`weekly_hours`) a partir de data/business_hours.json — ver
-- scripts/generar_export_business_hours.py y docs/dominio_de_negocio.md.
--
-- Grants adicionales: correr UNA SOLA VEZ, como ACCOUNTADMIN. 03_role_and_grants.sql
-- (Punto 1) le dio a YELP_LOADER_ROLE CREATE TABLE sobre RAW/STAGING, pero no
-- CREATE STAGE ni CREATE FILE FORMAT — privilegios que ese punto todavía no necesitaba.
USE ROLE ACCOUNTADMIN;

GRANT CREATE STAGE ON SCHEMA YELP_GOODYEAR_DW.RAW TO ROLE YELP_LOADER_ROLE;
GRANT CREATE FILE FORMAT ON SCHEMA YELP_GOODYEAR_DW.RAW TO ROLE YELP_LOADER_ROLE;

-- A partir de aquí, todo con el rol de servicio — mismo criterio que el resto del
-- proyecto: ACCOUNTADMIN solo concede privilegios de cuenta, nunca opera el pipeline.
USE ROLE YELP_LOADER_ROLE;
USE WAREHOUSE WH_YELP_XS;
USE DATABASE YELP_GOODYEAR_DW;
USE SCHEMA RAW;

-- STRIP_OUTER_ARRAY = TRUE es obligatorio: sin él, todo el archivo (un array de ~77
-- objetos) carga como UNA sola fila VARIANT en vez de una fila por negocio.
CREATE FILE FORMAT IF NOT EXISTS ff_business_hours_json
    TYPE = JSON
    STRIP_OUTER_ARRAY = TRUE
    COMMENT = 'Formato para los exports de horario semanal.';

CREATE STAGE IF NOT EXISTS stg_business_hours_internal
    FILE_FORMAT = ff_business_hours_json
    COMMENT = 'Internal Stage — export de horario semanal por negocio.';

-- Carga de los 2 archivos generados por scripts/generar_export_business_hours.py al
-- stage. Vía Snowsight: botón "Upload Files" sobre el stage. Vía SnowSQL (equivalente):
--
--   PUT file://data/business_hours_exports/business_hours_export_1.json
--       @stg_business_hours_internal AUTO_COMPRESS=TRUE;
--   PUT file://data/business_hours_exports/business_hours_export_2.json
--       @stg_business_hours_internal AUTO_COMPRESS=TRUE;

LIST @stg_business_hours_internal;

-- Vista previa del contenido crudo, antes de cargarlo a una tabla — confirma que
-- weekly_hours llega como array anidado real, no un JSON plano.
SELECT $1
FROM @stg_business_hours_internal (FILE_FORMAT => ff_business_hours_json)
LIMIT 5;

CREATE TABLE IF NOT EXISTS RAW_BUSINESS_HOURS (
    raw_data       VARIANT       COMMENT 'Un objeto por negocio: {business_id, weekly_hours: [...]}.',
    _stg_file_name STRING        COMMENT 'Trazabilidad: de qué archivo salió cada fila.',
    _stg_loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO RAW_BUSINESS_HOURS (raw_data, _stg_file_name, _stg_loaded_at)
FROM (
    SELECT $1, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @stg_business_hours_internal
)
FILE_FORMAT = (FORMAT_NAME = ff_business_hours_json)
ON_ERROR = ABORT_STATEMENT;

SELECT COUNT(*) AS total_negocios FROM RAW_BUSINESS_HOURS;  -- esperado: 154
