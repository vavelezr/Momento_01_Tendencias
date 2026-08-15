-- Punto 1 — Arquitectura Snowflake como código (Momento 2).
-- Ejecutar UNA SOLA VEZ, como ACCOUNTADMIN (o SECURITYADMIN, dueño de la jerarquía de roles).
--
-- Rol de servicio para el pipeline ELT: NO es ACCOUNTADMIN ni SYSADMIN. Solo puede usar
-- el warehouse del proyecto y leer/escribir en los esquemas de YELP_GOODYEAR_DW — nada
-- de administrar la cuenta, crear otros warehouses, ni tocar otras bases de datos.
--
-- Se conceden permisos también sobre objetos FUTUROS (FUTURE TABLES) en RAW y STAGING:
-- el Punto 2 va a crear tablas nuevas en cada corrida (auto_create_table / CREATE TABLE
-- AS), y sin este grant "a futuro" cada tabla nueva quedaría fuera del alcance del rol
-- hasta que alguien la conceda a mano — justo el tipo de fricción manual que ELT-como-código
-- busca eliminar.

CREATE ROLE IF NOT EXISTS YELP_LOADER_ROLE
    COMMENT = 'Rol de servicio para el pipeline ELT Neon -> Snowflake (Momento 2). Sin privilegios de administración de cuenta.';

-- Warehouse: solo USAGE (correr queries) + OPERATE (poder reanudarlo/suspenderlo él
-- mismo). No ADMIN ni MODIFY: el rol no necesita poder redimensionar o borrar el warehouse.
GRANT USAGE ON WAREHOUSE WH_YELP_XS TO ROLE YELP_LOADER_ROLE;
GRANT OPERATE ON WAREHOUSE WH_YELP_XS TO ROLE YELP_LOADER_ROLE;

-- Database + esquemas: USAGE para navegar, CREATE TABLE para que el Punto 2 pueda crear
-- las tablas de carga (write_pandas con auto_create_table, o un CREATE TABLE explícito).
GRANT USAGE ON DATABASE YELP_GOODYEAR_DW TO ROLE YELP_LOADER_ROLE;

GRANT USAGE, CREATE TABLE ON SCHEMA YELP_GOODYEAR_DW.RAW TO ROLE YELP_LOADER_ROLE;
GRANT USAGE, CREATE TABLE ON SCHEMA YELP_GOODYEAR_DW.STAGING TO ROLE YELP_LOADER_ROLE;

-- Tablas ya existentes en RAW (las que crea 06_raw_tables.sql) + las que se creen después.
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA YELP_GOODYEAR_DW.RAW
    TO ROLE YELP_LOADER_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON FUTURE TABLES IN SCHEMA YELP_GOODYEAR_DW.RAW
    TO ROLE YELP_LOADER_ROLE;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA YELP_GOODYEAR_DW.STAGING
    TO ROLE YELP_LOADER_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON FUTURE TABLES IN SCHEMA YELP_GOODYEAR_DW.STAGING
    TO ROLE YELP_LOADER_ROLE;
