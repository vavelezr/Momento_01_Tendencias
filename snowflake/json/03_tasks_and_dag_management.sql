-- Punto 4 — Orquestación con Tasks (Momento 2, Sesión 5).
-- DAG de 2 tareas: la raíz recarga RAW_BUSINESS_HOURS desde el stage; la hija (AFTER)
-- reaplana hacia STAGING. Requiere 01_setup_stage_and_raw.sql y
-- 02_flatten_query_exploration.sql ya corridos (las tablas y el stage deben existir).

-- EXECUTE TASK ON ACCOUNT es privilegio de cuenta, no de objeto — se olvida fácil y no
-- lo cubre ningún grant anterior. Correr una sola vez, como ACCOUNTADMIN.
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE YELP_LOADER_ROLE;
GRANT CREATE TASK ON SCHEMA YELP_GOODYEAR_DW.RAW TO ROLE YELP_LOADER_ROLE;
GRANT CREATE TASK ON SCHEMA YELP_GOODYEAR_DW.STAGING TO ROLE YELP_LOADER_ROLE;

USE ROLE YELP_LOADER_ROLE;
USE WAREHOUSE WH_YELP_XS;
USE DATABASE YELP_GOODYEAR_DW;

CREATE OR REPLACE TASK RAW.TASK_INGEST_BUSINESS_HOURS
    WAREHOUSE = WH_YELP_XS
    COMMENT = 'Raíz del DAG — Punto 4, Sesión 5. Recarga RAW_BUSINESS_HOURS desde el stage interno.'
    SCHEDULE = 'USING CRON 0 * * * * America/Bogota'
AS
    COPY INTO RAW.RAW_BUSINESS_HOURS (raw_data, _stg_file_name, _stg_loaded_at)
    FROM (
        SELECT $1, METADATA$FILENAME, CURRENT_TIMESTAMP()
        FROM @RAW.stg_business_hours_internal
    )
    FILE_FORMAT = (FORMAT_NAME = RAW.ff_business_hours_json)
    ON_ERROR = ABORT_STATEMENT;

-- AFTER, no un segundo SCHEDULE: la hija depende del éxito de la raíz, no de un horario
-- propio. Una task creada con AFTER nace SUSPENDED igual que la raíz — ninguna de las dos
-- corre sola hasta activarlas explícitamente más abajo.
CREATE OR REPLACE TASK RAW.TASK_FLATTEN_BUSINESS_HOURS
    WAREHOUSE = WH_YELP_XS
    COMMENT = 'Hija del DAG — Punto 4, Sesión 5. Reaplana RAW_BUSINESS_HOURS hacia STG_BUSINESS_HOURS_FLATTENED.'
    AFTER RAW.TASK_INGEST_BUSINESS_HOURS
AS
    INSERT OVERWRITE INTO STAGING.STG_BUSINESS_HOURS_FLATTENED (business_id, day_of_week, open_time, close_time)
    SELECT
        raw_data:business_id::STRING,
        h.value:day_of_week::STRING,
        h.value:open_time::STRING,
        h.value:close_time::STRING
    FROM RAW.RAW_BUSINESS_HOURS,
         LATERAL FLATTEN(input => raw_data:weekly_hours) h;

SHOW TASKS IN DATABASE YELP_GOODYEAR_DW;  -- ambas en state = suspended (recién creadas)

-- Sin esto, la hija nunca se activa aunque la raíz sí: SYSTEM$TASK_DEPENDENTS_ENABLE
-- activa la raíz Y todo su árbol de dependientes de una vez.
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('RAW.TASK_INGEST_BUSINESS_HOURS');

SHOW TASKS IN DATABASE YELP_GOODYEAR_DW;  -- CAPTURA: ambas en state = started

-- Disparo manual de la raíz (no hay que esperar al cron para demostrar el DAG).
EXECUTE TASK RAW.TASK_INGEST_BUSINESS_HOURS;

-- TASK_HISTORY() sin filtro devuelve tasks de TODA la cuenta, incluidas las internas de
-- Snowflake (CORTEX_BASE_MODELS_REFRESH_TASK, APPLY_OVERRIDES_TASK, etc.) — no son del
-- proyecto. Filtrar por nombre deja la evidencia limpia sin tener que recortar la captura.
SELECT name, state, error_message, scheduled_time, completed_time
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_INGEST_BUSINESS_HOURS', 'TASK_FLATTEN_BUSINESS_HOURS')
ORDER BY scheduled_time DESC
LIMIT 10;  -- CAPTURA: ambas SUCCEEDED, completed_time de la hija justo después de la raíz

-- ---------------------------------------------------------------------------
-- Evidencia de administración: tocar la hija con la raíz activa falla, en las dos
-- direcciones. Verificado contra la cuenta real: el mensaje no es el código 091421
-- citado en clase, sino "Unable to update graph with root task ... since that root
-- task is not suspended." — misma regla, error distinto. Ver docs/evidences/README.md.
-- ---------------------------------------------------------------------------
ALTER TASK RAW.TASK_INGEST_BUSINESS_HOURS RESUME;
ALTER TASK RAW.TASK_FLATTEN_BUSINESS_HOURS RESUME;   -- CAPTURADO: falla, root no suspendido
ALTER TASK RAW.TASK_FLATTEN_BUSINESS_HOURS SUSPEND;  -- CAPTURADO: también falla

-- Orden correcto: la raíz primero, siempre.
ALTER TASK RAW.TASK_INGEST_BUSINESS_HOURS SUSPEND;
ALTER TASK RAW.TASK_FLATTEN_BUSINESS_HOURS SUSPEND;

SHOW TASKS IN DATABASE YELP_GOODYEAR_DW;  -- CAPTURA: ambas en state = suspended
