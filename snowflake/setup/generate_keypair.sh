#!/usr/bin/env bash
# Genera el par de llaves RSA para autenticar SVC_YELP_LOADER por key-pair en vez de
# password (ver 04_service_user.sql para el porqué). Requiere `openssl` — ya viene
# instalado en Git Bash / WSL / macOS / Linux.
#
# Uso:
#   bash snowflake/setup/generate_keypair.sh [directorio_destino]
#
# Por defecto guarda las llaves en snowflake/setup/keys/ (ignorado por git — ver
# .gitignore). NUNCA subas rsa_key.p8 (la llave PRIVADA) a git, ni la compartas por Slack
# o correo: es el equivalente a una contraseña. La llave pública (rsa_key.pub) sí es
# segura de compartir — es la que se asocia al usuario en Snowflake.

set -euo pipefail

DESTINO="${1:-$(dirname "$0")/keys}"
mkdir -p "$DESTINO"

LLAVE_PRIVADA="$DESTINO/rsa_key.p8"
LLAVE_PUBLICA="$DESTINO/rsa_key.pub"

if [ -f "$LLAVE_PRIVADA" ]; then
    echo "Ya existe $LLAVE_PRIVADA — bórrala a mano primero si de verdad quieres regenerar" \
         "el par (regenerar invalida la llave pública ya asociada en Snowflake)." >&2
    exit 1
fi

TEMPORAL="$DESTINO/.rsa_key_sin_cifrar.tmp"
limpiar_temporal() { rm -f "$TEMPORAL"; }
trap limpiar_temporal EXIT

# Dos pasos en vez de un pipe (`openssl genrsa | openssl pkcs8 ...`) a propósito: en Git
# Bash / MSYS sobre Windows, un pipe deja la entrada estándar ocupada y el prompt de
# passphrase del segundo comando se queda esperando una entrada que nunca le llega —
# la terminal parece congelada. Separar en dos comandos, sin pipe, deja el teclado libre
# para cuando sí toca escribir la passphrase.
echo "Generando llave privada RSA de 2048 bits (paso 1/2, sin passphrase todavía)..."
openssl genrsa -out "$TEMPORAL" 2048

echo "Cifrando la llave (paso 2/2) — te va a pedir una passphrase: escríbela y presiona" \
     "Enter (no se ve nada en pantalla mientras escribes, es normal). Anótala, el futuro" \
     "conector Python de Punto 2 la necesita en SNOWFLAKE_PRIVATE_KEY_PASSPHRASE."
openssl pkcs8 -topk8 -inform PEM -in "$TEMPORAL" -out "$LLAVE_PRIVADA" -v2 aes256

echo "Derivando la llave pública..."
openssl rsa -in "$LLAVE_PRIVADA" -pubout -out "$LLAVE_PUBLICA"

chmod 600 "$LLAVE_PRIVADA"

echo
echo "Listo. Archivos generados:"
echo "  Privada (secreta):  $LLAVE_PRIVADA"
echo "  Pública (compartir): $LLAVE_PUBLICA"
echo
echo "Copia esto en 05_set_service_user_key.sql (SET RSA_PUBLIC_KEY='...'), sin" \
     "encabezado/pie ni saltos de línea:"
echo
grep -v -- "-----" "$LLAVE_PUBLICA" | tr -d '\n'
echo
echo
echo "Y guarda esta ruta como SNOWFLAKE_PRIVATE_KEY_PATH en el .env de quien vaya a" \
     "correr el Punto 2 (normalmente tu compañero de equipo)."
