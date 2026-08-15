-- Punto 1 — Arquitectura Snowflake como código (Momento 2).
-- Ejecutar UNA SOLA VEZ, como ACCOUNTADMIN (o SECURITYADMIN), DESPUÉS de:
--   1. Correr generate_keypair.sh (genera snowflake/setup/keys/rsa_key.p8 + rsa_key.pub).
--   2. Reemplazar el placeholder de abajo por el contenido real de rsa_key.pub, tal como
--      lo imprime el script: sin "-----BEGIN/END PUBLIC KEY-----" y sin saltos de línea.
--
-- Este archivo se versiona con el placeholder — es una plantilla, no un secreto. La
-- llave pública en sí NO es secreta (es la mitad "pública" del par), pero de todas
-- formas no tiene sentido commitear un valor real: cada integrante/entorno puede acabar
-- generando su propio par si regenera las llaves, y el placeholder dejaría de coincidir.
-- Corre esta sentencia manualmente con el valor real cada vez que generes o rotes llaves.

ALTER USER SVC_YELP_LOADER SET RSA_PUBLIC_KEY = '<pega_aqui_el_contenido_de_rsa_key.pub_sin_encabezado_ni_saltos_de_linea>';

-- Verificación: DESCRIBE USER expone rsa_public_key_fp (huella/fingerprint), suficiente
-- para confirmar que la llave quedó asociada sin exponer la llave privada en ningún momento.
DESC USER SVC_YELP_LOADER;

-- Rotación de llaves (cuando toque, ej. cada pocos meses o si la privada se filtró):
-- Snowflake permite dos llaves activas a la vez (RSA_PUBLIC_KEY y RSA_PUBLIC_KEY_2) para
-- rotar sin downtime — genera el nuevo par, asocia RSA_PUBLIC_KEY_2, actualiza el .env
-- del conector, y solo entonces retira la llave vieja de RSA_PUBLIC_KEY.
-- ALTER USER SVC_YELP_LOADER SET RSA_PUBLIC_KEY_2 = '<...>';
-- ALTER USER SVC_YELP_LOADER UNSET RSA_PUBLIC_KEY;
