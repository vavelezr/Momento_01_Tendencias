-- Bootstrap del esquema de destino de dbt (Momento 3). Ejecutar UNA SOLA VEZ, como
-- ACCOUNTADMIN — mismo patrón que 01-05 (Momento 2, Punto 1): privilegios de cuenta
-- (CREATE SCHEMA) que YELP_LOADER_ROLE no tiene ni necesita tener de forma permanente.
--
-- Por qué un esquema nuevo y no reusar RAW/STAGING: dbt reconstruye todo lo que hay en su
-- esquema de destino con `dbt build` — mezclarlo con RAW (carga cruda) o STAGING (JSON
-- aplanado del Momento 2, Sesión 5) volvería ambiguo qué objeto lo mantiene un script
-- manual y cuál dbt. Ver dbt/README.md para el detalle.
USE ROLE ACCOUNTADMIN;

CREATE SCHEMA IF NOT EXISTS YELP_GOODYEAR_DW.ANALYTICS
    COMMENT = 'Destino de los modelos dbt (staging/intermediate/marts) del Momento 3.';

-- YELP_LOADER_ROLE ya tenía CREATE TABLE sobre RAW/STAGING (03_role_and_grants.sql) pero
-- nunca CREATE VIEW en ningún esquema — dbt materializa staging/intermediate como vistas
-- por defecto (ver dbt/dbt_project.yml).
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA YELP_GOODYEAR_DW.ANALYTICS
    TO ROLE YELP_LOADER_ROLE;

-- Lectura para los roles de negocio ya creados en snowflake/json/04_rbac_and_masking.sql
-- (Sesión 5): quien vaya a consultar los marts desde Streamlit in Snowflake o ad-hoc
-- necesita SELECT aquí, no solo YELP_LOADER_ROLE (que es el rol de build, no de consumo).
-- Incluye objetos futuros porque cada `dbt build` puede crear modelos nuevos.
GRANT USAGE ON SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT USAGE ON SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_BUSINESS_OWNER;

GRANT SELECT ON ALL TABLES IN SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_DATA_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_DATA_ANALYST;

GRANT SELECT ON ALL TABLES IN SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT SELECT ON ALL VIEWS IN SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_BUSINESS_OWNER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA YELP_GOODYEAR_DW.ANALYTICS TO ROLE ROLE_YELP_BUSINESS_OWNER;

-- Verificación rápida (opcional): confirma que YELP_LOADER_ROLE ya puede crear ahí.
-- USE ROLE YELP_LOADER_ROLE;
-- CREATE OR REPLACE VIEW YELP_GOODYEAR_DW.ANALYTICS.ping AS SELECT 1 AS ok;
-- SELECT * FROM YELP_GOODYEAR_DW.ANALYTICS.ping;
-- DROP VIEW YELP_GOODYEAR_DW.ANALYTICS.ping;
