"""
Verificación de conexión a Snowflake por key-pair (RSA) — Punto 1 (Momento 2).

No hace ELT: no lee de Neon, no escribe filas. Su único trabajo es confirmar que
SVC_YELP_LOADER puede autenticarse con la llave privada y que aterriza en el
warehouse/database/schema/rol correctos — el prerequisito que el Punto 2 necesita antes
de escribir la primera línea de código de carga.

Uso:
    uv run snowflake/setup/verificar_conexion.py

Requiere las variables de entorno documentadas en snowflake/setup/README.md y en el
.env.example de la raíz del repo (patrón key-pair, no password).
"""

from __future__ import annotations

import os
import sys

import snowflake.connector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from dotenv import load_dotenv


def cargar_llave_privada() -> bytes:
    ruta = os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH")
    if not ruta:
        print("ERROR: falta SNOWFLAKE_PRIVATE_KEY_PATH en .env", file=sys.stderr)
        sys.exit(1)
    if not os.path.exists(ruta):
        print(f"ERROR: no existe el archivo de llave privada: {ruta}", file=sys.stderr)
        sys.exit(1)

    passphrase = os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
    with open(ruta, "rb") as archivo:
        clave_pem = archivo.read()

    clave = serialization.load_pem_private_key(
        clave_pem,
        password=passphrase.encode() if passphrase else None,
        backend=default_backend(),
    )
    # snowflake-connector-python espera la llave privada en formato DER, no PEM.
    return clave.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def conectar() -> snowflake.connector.SnowflakeConnection:
    faltantes = [
        variable
        for variable in ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER")
        if not os.getenv(variable)
    ]
    if faltantes:
        print(f"ERROR: faltan variables de entorno: {faltantes}", file=sys.stderr)
        sys.exit(1)

    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key=cargar_llave_privada(),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "WH_YELP_XS"),
        database=os.environ.get("SNOWFLAKE_DATABASE", "YELP_GOODYEAR_DW"),
        schema=os.environ.get("SNOWFLAKE_SCHEMA", "RAW"),
        role=os.environ.get("SNOWFLAKE_ROLE", "YELP_LOADER_ROLE"),
    )


def main() -> int:
    load_dotenv()
    conexion = conectar()
    try:
        with conexion.cursor() as cursor:
            cursor.execute(
                "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(), "
                "CURRENT_DATABASE(), CURRENT_SCHEMA()"
            )
            usuario, rol, warehouse, database, schema = cursor.fetchone()

        print("Conexión OK por key-pair:")
        print(f"  usuario    = {usuario}")
        print(f"  rol        = {rol}")
        print(f"  warehouse  = {warehouse}")
        print(f"  database   = {database}")
        print(f"  schema     = {schema}")
        return 0
    finally:
        conexion.close()


if __name__ == "__main__":
    sys.exit(main())
