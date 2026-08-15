-- Punto 1 — Arquitectura Snowflake como código (Momento 2).
-- Ejecutar UNA SOLA VEZ, como ACCOUNTADMIN (o un rol con CREATE WAREHOUSE en la cuenta).
--
-- Warehouse X-SMALL dedicado a este proyecto. AUTO_SUSPEND corto + AUTO_RESUME=TRUE es
-- lo que evita pagar crédito de cómputo mientras nadie está corriendo el ELT: se suspende
-- solo a los 60s de inactividad y se reactiva solo en la siguiente query, sin que nadie
-- tenga que acordarse de apagarlo a mano.

CREATE WAREHOUSE IF NOT EXISTS WH_YELP_XS
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse del proyecto reseñas de negocios locales (Goodyear, AZ). Uso: cargas ELT + consultas de dbt/SQL sobre YELP_GOODYEAR_DW.';
