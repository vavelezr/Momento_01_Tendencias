-- Punto 1 — Arquitectura Snowflake como código (Momento 2).
-- Ejecutar UNA SOLA VEZ, como ACCOUNTADMIN (o un rol con CREATE DATABASE en la cuenta).
--
-- Crea la base de datos del proyecto y sus esquemas por capa. Solo se crean dos capas
-- en este Punto 1 porque es lo que el taller pide adelantar ahora:
--   RAW      -- destino de la carga cruda desde Neon (Punto 2), sin transformar.
--   STAGING  -- esquema de trabajo para las transformaciones que vengan después
--              (dbt o SQL directo) sobre el dominio de reseñas de negocios locales.
-- No se crea todavía un esquema tipo MARTS/ANALYTICS: no hay nada que modelar aún y
-- agregarlo ahora sería anticipar trabajo del Punto 3 en adelante.

CREATE DATABASE IF NOT EXISTS YELP_GOODYEAR_DW
    COMMENT = 'Cloud Data Warehouse — reseñas de negocios locales (Goodyear, AZ). Fuente: Neon (Momento 1).';

CREATE SCHEMA IF NOT EXISTS YELP_GOODYEAR_DW.RAW
    COMMENT = 'Capa RAW: espejo 1:1 de las tablas de Neon, sin transformar. Carga la ejecuta el Punto 2.';

CREATE SCHEMA IF NOT EXISTS YELP_GOODYEAR_DW.STAGING
    COMMENT = 'Capa de trabajo para transformaciones sobre RAW. Vacía por ahora — Puntos 3 en adelante.';
