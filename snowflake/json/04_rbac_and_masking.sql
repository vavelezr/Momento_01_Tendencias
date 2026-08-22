-- Punto 5 — RBAC + Masking Policy (Momento 2, Sesión 5).
-- Dos roles de negocio, además de YELP_LOADER_ROLE (que es de servicio, no de negocio).
-- Campo protegido: USERS.NAME — único dato de PII del dominio (nombre de una persona
-- real; no hay teléfono ni email en el modelo).

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS ROLE_YELP_DATA_ANALYST
    COMMENT = 'Rol de negocio — acceso completo de solo lectura, incluida PII sin enmascarar.';

CREATE ROLE IF NOT EXISTS ROLE_YELP_BUSINESS_OWNER
    COMMENT = 'Rol de negocio — acceso de solo lectura con PII enmascarada.';

GRANT USAGE ON WAREHOUSE WH_YELP_XS TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT USAGE ON WAREHOUSE WH_YELP_XS TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT USAGE ON DATABASE YELP_GOODYEAR_DW TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT USAGE ON DATABASE YELP_GOODYEAR_DW TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT USAGE ON SCHEMA YELP_GOODYEAR_DW.RAW TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT USAGE ON SCHEMA YELP_GOODYEAR_DW.RAW TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT USAGE ON SCHEMA YELP_GOODYEAR_DW.STAGING TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT USAGE ON SCHEMA YELP_GOODYEAR_DW.STAGING TO ROLE ROLE_YELP_BUSINESS_OWNER;

-- ROLE_YELP_DATA_ANALYST: todo el dato, incluidas tablas futuras (análogo a
-- ROLE_DATA_ENGINEER en el ejemplo de clase).
GRANT SELECT ON ALL TABLES IN SCHEMA YELP_GOODYEAR_DW.RAW TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA YELP_GOODYEAR_DW.RAW TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA YELP_GOODYEAR_DW.STAGING TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA YELP_GOODYEAR_DW.STAGING TO ROLE ROLE_YELP_DATA_ANALYST;

-- ROLE_YELP_BUSINESS_OWNER: solo el dato operativo/agregado que necesita el dueño del
-- negocio (análogo a ROLE_BUSINESS_MANAGER en el ejemplo de clase).
GRANT SELECT ON TABLE YELP_GOODYEAR_DW.RAW.BUSINESS TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT SELECT ON TABLE YELP_GOODYEAR_DW.RAW.REVIEW TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT SELECT ON TABLE YELP_GOODYEAR_DW.RAW.TIP TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT SELECT ON TABLE YELP_GOODYEAR_DW.RAW.USERS TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT SELECT ON TABLE YELP_GOODYEAR_DW.STAGING.STG_BUSINESS_HOURS_FLATTENED TO ROLE ROLE_YELP_BUSINESS_OWNER;

-- Un solo usuario de Snowflake por integrante en la cuenta trial del equipo: para
-- demostrar los 3 roles en la sustentación, el mismo usuario los tiene todos concedidos
-- y alterna con USE ROLE — no hace falta un usuario por rol.
GRANT ROLE ROLE_YELP_DATA_ANALYST TO USER VAVELEZR;
GRANT ROLE ROLE_YELP_BUSINESS_OWNER TO USER VAVELEZR;

-- ---------------------------------------------------------------------------
-- "Antes": confirmar que ambos roles ven el nombre completo, sin política todavía.
-- CAPTURA (falta tomarla): las dos consultas de abajo, antes de crear la masking policy.
-- ---------------------------------------------------------------------------
USE ROLE ROLE_YELP_DATA_ANALYST;
SELECT user_id, name FROM YELP_GOODYEAR_DW.RAW.USERS LIMIT 5;

USE ROLE ROLE_YELP_BUSINESS_OWNER;
SELECT user_id, name FROM YELP_GOODYEAR_DW.RAW.USERS LIMIT 5;

-- ---------------------------------------------------------------------------
-- Masking policy sobre USERS.NAME.
-- ---------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE MASKING POLICY IF NOT EXISTS mask_user_name
    AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() = 'ROLE_YELP_DATA_ANALYST' THEN val
        WHEN CURRENT_ROLE() = 'ROLE_YELP_BUSINESS_OWNER' THEN LEFT(val, 1) || '.***'
        ELSE '***'
    END
    COMMENT = 'Protege RAW.USERS.NAME — único campo de PII del dominio (Punto 5, Sesión 5).';

ALTER TABLE YELP_GOODYEAR_DW.RAW.USERS
    MODIFY COLUMN name
    SET MASKING POLICY mask_user_name;

-- ---------------------------------------------------------------------------
-- "Después": mismo query, tres roles, tres resultados distintos.
-- Capturas: docs/evidences/images/momento_02_tarea{1,2,3}.png
-- ---------------------------------------------------------------------------
USE ROLE ROLE_YELP_DATA_ANALYST;
SELECT user_id, name FROM YELP_GOODYEAR_DW.RAW.USERS LIMIT 5;  -- nombre completo

USE ROLE ROLE_YELP_BUSINESS_OWNER;
SELECT user_id, name FROM YELP_GOODYEAR_DW.RAW.USERS LIMIT 5;  -- ej. "P.***"

USE ROLE ACCOUNTADMIN;
SELECT user_id, name FROM YELP_GOODYEAR_DW.RAW.USERS LIMIT 5;  -- "***" (no cae en ninguna rama WHEN)
