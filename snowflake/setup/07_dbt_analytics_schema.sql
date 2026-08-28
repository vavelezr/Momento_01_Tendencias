-- Bootstrap de privilegios para dbt (Momento 3). Ejecutar UNA SOLA VEZ, como
-- ACCOUNTADMIN -- mismo patron que 01-05 (Momento 2, Punto 1): privilegios de cuenta
-- (CREATE SCHEMA) que YELP_LOADER_ROLE no tiene ni necesita tener de forma permanente.
--
-- Sigue el patron exacto de la Sesion 7 del curso (README de la sesion, seccion
-- "Privilegios adicionales sobre el rol de servicio"): en vez de pre-crear un esquema y
-- darle CREATE TABLE/CREATE VIEW ahi, se le da a YELP_LOADER_ROLE el privilegio de
-- CREAR sus propios esquemas -- dbt los crea el mismo la primera vez que corre (uno por
-- capa: ANALYTICS_STAGING para staging/, ANALYTICS_CORE para core/, via +schema en
-- dbt_project.yml) y, al crearlos, queda como dueno con privilegios completos ahi. Nunca
-- toca RAW ni STAGING (Momento 1/2): son esquemas nuevos, separados a proposito.
USE ROLE ACCOUNTADMIN;

GRANT CREATE SCHEMA ON DATABASE YELP_GOODYEAR_DW TO ROLE YELP_LOADER_ROLE;

-- Verificacion (opcional): confirma que YELP_LOADER_ROLE ya puede crear un esquema.
-- USE ROLE YELP_LOADER_ROLE;
-- CREATE SCHEMA IF NOT EXISTS YELP_GOODYEAR_DW.PING_SCHEMA;
-- DROP SCHEMA YELP_GOODYEAR_DW.PING_SCHEMA;
