"""ELT relacional: Neon (PostgreSQL) -> Snowflake, capa RAW.

Extrae las tablas del dominio propio (reseñas de negocios locales) desde la branch `dev`
de Neon y las carga, sin transformar, en el schema RAW de Snowflake. Es "ELT", no "ETL":
la transformación (dbt, Momento 3) ocurre después, dentro de Snowflake.

Uso:
    uv run elt_neon_to_snowflake.py                  # carga las 6 tablas
    uv run elt_neon_to_snowflake.py --tabla review    # solo una tabla
    uv run elt_neon_to_snowflake.py --solo-verificar  # detecta drift, no carga
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
import snowflake.connector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from dotenv import load_dotenv
from snowflake.connector.pandas_tools import write_pandas

# El modelo propio del Momento 1: 5 tablas de baseline + `tip` (migración V__).
# business_hours y checkin quedaron fuera de alcance del Momento 1 — no se extraen.
TABLAS = ["category", "business", "business_category", "users", "review", "tip"]


# ¿Por qué buscamos la raíz del repo en vez de usar la ruta tal cual? El .env.example de
# la raíz define SNOWFLAKE_PRIVATE_KEY_PATH relativo a la raíz del repo (mismo valor que
# usa snowflake/setup/verificar_conexion.py, que sí corre desde ahí). Este script, en
# cambio, se invoca desde ingesta/ (uv run elt_neon_to_snowflake.py) — una ruta relativa
# tal cual se resolvería contra ingesta/, no contra la raíz, y el archivo "no existiría".
# Anclar la búsqueda en la raíz hace que el mismo .env sirva para los dos scripts, sin
# rutas duplicadas ni un "../" frágil que se rompe si alguien mueve la carpeta.
def _raiz_repositorio() -> Path:
    inicio = Path(__file__).resolve().parent
    for candidato in [inicio, *inicio.parents]:
        if (candidato / ".git").exists():
            return candidato
    return inicio

MAPA_TIPOS_SNOWFLAKE = {
    "int64": "NUMBER",
    "float64": "FLOAT",
    "bool": "BOOLEAN",
    "datetime64[ns]": "TIMESTAMP_NTZ",
    "object": "VARCHAR",
}


def conectar_neon() -> psycopg2.extensions.connection:
    url = os.getenv("NEON_DEV_DATABASE_URL")
    if not url:
        print("ERROR: falta NEON_DEV_DATABASE_URL en .env", file=sys.stderr)
        sys.exit(1)
    return psycopg2.connect(url)


def extraer_tabla(conexion_pg, tabla: str) -> pd.DataFrame:
    with conexion_pg.cursor() as cursor:
        cursor.execute(f"SELECT * FROM {tabla}")
        columnas = [c.name.upper() for c in cursor.description]
        filas = cursor.fetchall()
    return pd.DataFrame(filas, columns=columnas)


def calcular_drift(columnas_dataframe: set[str], columnas_snowflake: set[str]) -> set[str]:
    return columnas_dataframe - columnas_snowflake


def construir_ddl_evolucion(tabla: str, columnas_nuevas: set[str], df: pd.DataFrame) -> str:
    lineas = []
    for columna in sorted(columnas_nuevas):
        tipo_pandas = str(df[columna].dtype)
        tipo_snowflake = MAPA_TIPOS_SNOWFLAKE.get(tipo_pandas, "VARCHAR")
        lineas.append(f'ALTER TABLE {tabla.upper()} ADD COLUMN "{columna}" {tipo_snowflake};')
    return "\n".join(lineas)


def _cargar_llave_privada() -> bytes:
    # Autenticación por par de llaves (RSA), no por contraseña: es lo que exige el rol
    # de servicio de la cuenta. El archivo .p8 es PEM, cifrado con una passphrase — se
    # descifra en memoria aquí y se re-serializa a DER, que es el formato que espera
    # snowflake-connector-python en el parámetro `private_key`. La llave nunca se
    # escribe a disco descifrada.
    ruta = Path(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"])
    if not ruta.is_absolute():
        ruta = _raiz_repositorio() / ruta
    passphrase = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None

    with open(ruta, "rb") as archivo:
        llave = serialization.load_pem_private_key(
            archivo.read(),
            password=passphrase.encode() if passphrase else None,
            backend=default_backend(),
        )

    return llave.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def conectar_snowflake() -> snowflake.connector.SnowflakeConnection:
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key=_cargar_llave_privada(),
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
        schema=os.environ.get("SNOWFLAKE_SCHEMA", "RAW"),
        role=os.environ.get("SNOWFLAKE_ROLE"),
    )


def columnas_existentes_en_snowflake(conexion_sf, esquema: str, tabla: str) -> set[str]:
    with conexion_sf.cursor() as cursor:
        cursor.execute(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_schema = %s AND table_name = %s",
            (esquema.upper(), tabla.upper()),
        )
        return {fila[0] for fila in cursor.fetchall()}


def cargar_tabla(conexion_sf, tabla: str, df: pd.DataFrame, esquema: str) -> int:
    existentes = columnas_existentes_en_snowflake(conexion_sf, esquema, tabla)

    if existentes:
        drift = calcular_drift(set(df.columns), existentes)
        if drift:
            ddl = construir_ddl_evolucion(tabla, drift, df)
            raise RuntimeError(
                f"\nSchema drift detectado en {tabla.upper()}: la fuente en Neon trae "
                f"columna(s) nueva(s) que Snowflake no tiene todavía: {sorted(drift)}.\n\n"
                f"Aplica esto en un Worksheet de Snowsight y vuelve a correr el script:\n\n"
                f"{ddl}\n"
            )

    exito, _, num_filas, _ = write_pandas(
        conexion_sf, df, table_name=tabla.upper(), auto_create_table=True, overwrite=True,
    )
    if not exito:
        raise RuntimeError(f"write_pandas reportó fallo al cargar {tabla}")
    return num_filas


def main() -> int:
    parser = argparse.ArgumentParser(description="ELT de Neon hacia la capa RAW de Snowflake.")
    parser.add_argument("--tabla", choices=TABLAS, help="Cargar solo esta tabla.")
    parser.add_argument(
        "--solo-verificar", action="store_true",
        help="Extrae y compara schemas, pero no escribe nada en Snowflake.",
    )
    argumentos = parser.parse_args()

    load_dotenv()
    tablas = [argumentos.tabla] if argumentos.tabla else TABLAS
    esquema = os.environ.get("SNOWFLAKE_SCHEMA", "RAW")

    conexion_pg = conectar_neon()
    conexion_sf = conectar_snowflake()
    try:
        for tabla in tablas:
            print(f"Extrayendo {tabla} desde Neon...")
            df = extraer_tabla(conexion_pg, tabla)
            print(f"  {len(df)} filas · columnas: {list(df.columns)}")

            if argumentos.solo_verificar:
                existentes = columnas_existentes_en_snowflake(conexion_sf, esquema, tabla)
                drift = calcular_drift(set(df.columns), existentes) if existentes else set()
                estado = f"DRIFT: {sorted(drift)}" if drift else "sin drift"
                print(f"  [verificación] {estado}")
                continue

            num_filas = cargar_tabla(conexion_sf, tabla, df, esquema)
            print(f"  OK -> {num_filas} filas en {esquema}.{tabla.upper()}")

        return 0
    except RuntimeError as error:
        print(f"\nERROR: {error}", file=sys.stderr)
        return 1
    finally:
        conexion_pg.close()
        conexion_sf.close()


if __name__ == "__main__":
    sys.exit(main())