-- Punto 1 — Arquitectura Snowflake como código (Momento 2).
-- Ejecutar UNA SOLA VEZ, como ACCOUNTADMIN (o SECURITYADMIN).
--
-- Usuario de servicio para el pipeline ELT del Punto 2. Dos decisiones deliberadas aquí,
-- ambas apuntando al mismo problema — MFA obligatorio en cuentas nuevas de Snowflake:
--
-- 1. TYPE = SERVICE. Desde 2024 Snowflake distingue usuarios PERSON (personas, login
--    interactivo, sujetos a la política de MFA obligatorio de la cuenta) de usuarios
--    SERVICE (procesos automatizados, sin login interactivo, autenticados solo por
--    key-pair u OAuth). Un usuario SERVICE queda fuera del alcance de "MFA obligatorio"
--    porque nunca pasa por el flujo de login humano al que esa política aplica.
-- 2. Sin PASSWORD. No se define contraseña en el CREATE USER: este usuario solo puede
--    autenticarse por key-pair (RSA), configurado en 05_set_service_user_key.sql tras
--    generar el par de llaves con generate_keypair.sh. Sin password no hay superficie de
--    ataque por credencial débil, y no hay MFA que pedir porque no hay login por password
--    que proteger.
--
-- Nota: si tu cuenta de Snowflake es más antigua y no reconoce TYPE = SERVICE (feature
-- introducida en 2024), quita esa línea — el resto (sin password, solo key-pair) sigue
-- siendo válido y sigue evitando el prompt de MFA, porque key-pair es autenticación no
-- interactiva sin importar el tipo de usuario.

CREATE USER IF NOT EXISTS SVC_YELP_LOADER
    TYPE = SERVICE
    DEFAULT_ROLE = YELP_LOADER_ROLE
    DEFAULT_WAREHOUSE = WH_YELP_XS
    DEFAULT_NAMESPACE = YELP_GOODYEAR_DW.RAW
    COMMENT = 'Usuario de servicio del pipeline ELT Neon -> Snowflake (Momento 2, Punto 2). Autenticación exclusivamente por key-pair (RSA) — ver 05_set_service_user_key.sql.';

GRANT ROLE YELP_LOADER_ROLE TO USER SVC_YELP_LOADER;

-- Por si el usuario ya existía de un intento previo sin TYPE = SERVICE: confirma el rol
-- por defecto sin fallar si CREATE USER hizo IF NOT EXISTS y no aplicó los ajustes.
ALTER USER IF EXISTS SVC_YELP_LOADER SET
    DEFAULT_ROLE = YELP_LOADER_ROLE,
    DEFAULT_WAREHOUSE = WH_YELP_XS,
    DEFAULT_NAMESPACE = YELP_GOODYEAR_DW.RAW;
