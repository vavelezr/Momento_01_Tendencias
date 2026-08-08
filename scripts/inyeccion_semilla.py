"""
Inyección del estado base — Reseñas de negocios locales (Goodyear, AZ).

Sesión 1 del módulo "Tendencias emergentes en desarrollo de software" (SI6010-5979).

Este script construye el ESTADO BASE transaccional del curso: crea el schema baseline
(`category`, `business`, `business_category`, `users`, `review`) en una base de datos
PostgreSQL (Neon) y carga los datos semilla desde los archivos JSON de `data/`. Las tablas
`business_hours`, `tip` y `checkin` NO forman parte del baseline: llegan más adelante vía
migraciones Flyway (`sql_migrations/V__...`) — ver `docs/dominio_de_negocio.md` §3.

Es el punto de partida de todo el pipeline. A partir de la Sesión 2, ningún cambio de
schema se hará con un script como este: se hará con migraciones Flyway versionadas.

Uso:
    uv run inyeccion_semilla.py                   # carga contra la branch dev
    uv run inyeccion_semilla.py --solo-verificar   # no escribe; solo reporta el estado
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from decimal import Decimal
from pathlib import Path

import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import execute_values

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------

# ¿Por qué buscamos la carpeta `data/` subiendo por el árbol en vez de escribir
# "../../../data"? Porque una ruta relativa depende de DÓNDE se invoca el script, no de
# dónde vive. Si un estudiante corre `uv run scripts/inyeccion_semilla.py` desde la carpeta
# de la sesión, la ruta fija se rompe. Anclar la búsqueda en la raíz del repositorio hace
# que el script funcione igual desde cualquier directorio — y eso es exactamente lo que
# necesitaremos cuando sea GitHub Actions quien lo ejecute.
def encontrar_raiz_repositorio(inicio: Path) -> Path:
    for candidato in [inicio, *inicio.parents]:
        if (candidato / ".git").exists() and (candidato / "data").is_dir():
            return candidato
    raise RuntimeError(
        "No se encontró la raíz del repositorio (se esperaba un directorio con .git/ y data/). "
        f"Búsqueda iniciada en: {inicio}"
    )


RAIZ = encontrar_raiz_repositorio(Path(__file__).resolve().parent)
DIRECTORIO_DATOS = RAIZ / "data"

# El orden importa: las foreign keys obligan a insertar los padres antes que los hijos.
# `category` y `business` no dependen de nadie; `users` tampoco. `business_category`
# depende de `business` y `category`; `review` depende de `business` y `users`.
#
# El nombre de tabla no siempre coincide con el nombre del archivo JSON (el dataset trae
# `reviews.json` en plural, pero la tabla es `review` en singular, igual que el resto del
# schema) — de ahí el mapeo explícito en vez de asumir `f"{tabla}.json"`.
ORDEN_DE_CARGA = ["category", "business", "users", "business_category", "review"]

ARCHIVOS_JSON: dict[str, str] = {
    "category": "category.json",
    "business": "business.json",
    "users": "users.json",
    "business_category": "business_category.json",
    "review": "reviews.json",
}


# ---------------------------------------------------------------------------
# DDL — el schema del estado base
# ---------------------------------------------------------------------------

DDL = """
DROP TABLE IF EXISTS review CASCADE;
DROP TABLE IF EXISTS business_category CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS business CASCADE;
DROP TABLE IF EXISTS category CASCADE;

CREATE TABLE category (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE business (
    business_id  TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    full_address TEXT,
    city         TEXT NOT NULL,
    state        TEXT NOT NULL,
    latitude     NUMERIC(9, 7),
    longitude    NUMERIC(10, 7),
    stars        NUMERIC(2, 1),
    review_count INTEGER,
    is_open      BOOLEAN NOT NULL
);

CREATE TABLE users (
    user_id       TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    review_count  INTEGER,
    yelping_since DATE,
    average_stars NUMERIC(3, 2),
    fans          INTEGER,
    votes_useful  INTEGER,
    votes_funny   INTEGER,
    votes_cool    INTEGER
);

CREATE TABLE business_category (
    business_id TEXT NOT NULL REFERENCES business (business_id),
    category_id INTEGER NOT NULL REFERENCES category (id),
    PRIMARY KEY (business_id, category_id)
);

CREATE TABLE review (
    review_id    TEXT PRIMARY KEY,
    business_id  TEXT NOT NULL REFERENCES business (business_id),
    user_id      TEXT NOT NULL REFERENCES users (user_id),
    stars        SMALLINT NOT NULL CHECK (stars BETWEEN 1 AND 5),
    review_date  DATE NOT NULL,
    text         TEXT,
    votes_useful INTEGER,
    votes_funny  INTEGER,
    votes_cool   INTEGER
);

CREATE INDEX idx_business_category_category_id ON business_category (category_id);
CREATE INDEX idx_review_business_id ON review (business_id);
CREATE INDEX idx_review_user_id   ON review (user_id);
"""


# ---------------------------------------------------------------------------
# Conversión de tipos
# ---------------------------------------------------------------------------

# ¿Por qué esta sección es tan corta comparada con la de Parch & Posey? Porque ese dataset
# venía exportado de SQL Server con TODO como string ("123", "613.77"...). Este dataset se
# extrajo directo del Yelp Academic Dataset con `json.load`, así que enteros, decimales y
# booleanos ya llegan como `int`, `float`/`Decimal` y `bool` de Python — no hay nada que
# castear. Lo único que de verdad necesita conversión son las dos columnas de fecha, que
# llegan como texto.
def _fecha_iso(valor: str) -> date:
    # review_date llega como "AAAA-MM-DD" — formato ISO completo.
    return date.fromisoformat(valor)


def _mes_a_fecha(valor: str) -> date:
    # yelping_since llega como "AAAA-MM" (Yelp solo registra el mes de alta, no el día).
    # Normalizamos al día 1 del mes: es una aproximación del dataset origen, no un dato que
    # perdamos por una conversión descuidada nuestra.
    anio, mes = valor.split("-")
    return date(int(anio), int(mes), 1)


# Cada entrada define: columnas de la tabla y cómo construir la tupla de valores a partir
# del registro JSON, en el mismo orden que las columnas.
ESPECIFICACIONES: dict[str, tuple[tuple[str, ...], object]] = {
    "category": (
        ("id", "name"),
        lambda r: (r["id"], r["name"]),
    ),
    "business": (
        (
            "business_id", "name", "full_address", "city", "state", "latitude",
            "longitude", "stars", "review_count", "is_open",
        ),
        lambda r: (
            r["business_id"],
            r["name"],
            r["full_address"],
            r["city"],
            r["state"],
            r["latitude"],
            r["longitude"],
            r["stars"],
            r["review_count"],
            r["is_open"],
        ),
    ),
    "users": (
        (
            "user_id", "name", "review_count", "yelping_since", "average_stars", "fans",
            "votes_useful", "votes_funny", "votes_cool",
        ),
        lambda r: (
            r["user_id"],
            r["name"],
            r["review_count"],
            _mes_a_fecha(r["yelping_since"]),
            r["average_stars"],
            r["fans"],
            r["votes_useful"],
            r["votes_funny"],
            r["votes_cool"],
        ),
    ),
    "business_category": (
        ("business_id", "category_id"),
        lambda r: (r["business_id"], r["category_id"]),
    ),
    "review": (
        (
            "review_id", "business_id", "user_id", "stars", "review_date", "text",
            "votes_useful", "votes_funny", "votes_cool",
        ),
        lambda r: (
            r["review_id"],
            r["business_id"],
            r["user_id"],
            r["stars"],
            _fecha_iso(r["review_date"]),
            r["text"],
            r["votes_useful"],
            r["votes_funny"],
            r["votes_cool"],
        ),
    ),
}


# ---------------------------------------------------------------------------
# Lógica principal
# ---------------------------------------------------------------------------

def obtener_url_conexion() -> str:
    # `load_dotenv()` no hace nada si no encuentra un `.env` (p. ej. en GitHub Actions, donde
    # los secretos ya llegan como variables de entorno reales vía `env:` en el workflow). En
    # local, sí carga el `.env` que cada estudiante mantiene fuera de git.
    load_dotenv()
    url_dev = os.getenv("NEON_DEV_DATABASE_URL")
    url_main = os.getenv("NEON_MAIN_DATABASE_URL")

    if not url_dev:
        print(
            "ERROR: falta la variable NEON_DEV_DATABASE_URL.\n"
            "       Local: copia .env.example a .env y pega ahí el connection string de tu "
            "branch dev.\n"
            "       CI: revisa que el secreto NEON_DEV_DATABASE_URL esté configurado en "
            "GitHub Actions.",
            file=sys.stderr,
        )
        sys.exit(1)

    # ¿Por qué el script se niega a correr si dev y main apuntan al mismo sitio? Porque en
    # DataOps la branch `main` es sagrada: representa el estado que el negocio consume.
    # Este script hace DROP TABLE. Ejecutarlo contra main destruiría producción sin dejar
    # rastro ni forma de revertir. Un guardrail que aborta es más barato que un incidente,
    # y el patrón se repetirá todo el curso: el entorno destino nunca es implícito.
    if url_main and url_dev.strip() == url_main.strip():
        print(
            "ERROR: NEON_DEV_DATABASE_URL y NEON_MAIN_DATABASE_URL apuntan a la misma base.\n"
            "       Este script hace DROP TABLE — nunca debe correr contra main.\n"
            "       Revisa que hayas copiado el connection string de la branch dev.",
            file=sys.stderr,
        )
        sys.exit(1)

    return url_dev


def cargar_json(tabla: str) -> list[dict]:
    ruta = DIRECTORIO_DATOS / ARCHIVOS_JSON[tabla]
    if not ruta.exists():
        print(f"ERROR: no se encontró {ruta}", file=sys.stderr)
        sys.exit(1)
    # `parse_float=Decimal` evita que latitud/longitud/estrellas pasen por `float` de Python
    # antes de llegar a `Decimal` — un float intermedio puede introducir ruido de precisión
    # binaria (33.4627978 -> 33.46279779999999...) que después se cuela en el INSERT.
    with ruta.open(encoding="utf-8") as archivo:
        return json.load(archivo, parse_float=Decimal)


def inyectar(conexion) -> dict[str, int]:
    cargadas: dict[str, int] = {}
    with conexion.cursor() as cursor:
        print("Creando schema...")
        cursor.execute(DDL)

        for tabla in ORDEN_DE_CARGA:
            columnas, convertir = ESPECIFICACIONES[tabla]
            registros = cargar_json(tabla)
            filas = [convertir(registro) for registro in registros]

            # ¿Por qué execute_values y no un INSERT por fila dentro de un bucle? Neon es
            # serverless: cada sentencia es un round-trip de red, y miles de round-trips
            # tardan minutos. execute_values agrupa las filas en pocas sentencias
            # multi-valor. La lección no es "usa esta función": es que en pipelines de
            # datos el costo dominante casi nunca es el CPU, es la latencia de red.
            execute_values(
                cursor,
                f"INSERT INTO {tabla} ({', '.join(columnas)}) VALUES %s",
                filas,
                page_size=1000,
            )
            cargadas[tabla] = len(filas)
            print(f"  {tabla:<18} {len(filas):>6} filas")

    return cargadas


def verificar(conexion) -> dict[str, int]:
    conteos: dict[str, int] = {}
    with conexion.cursor() as cursor:
        for tabla in ORDEN_DE_CARGA:
            cursor.execute(
                "SELECT to_regclass(%s) IS NOT NULL", (f"public.{tabla}",)
            )
            existe = cursor.fetchone()[0]
            if not existe:
                conteos[tabla] = -1
                continue
            cursor.execute(f"SELECT count(*) FROM {tabla}")
            conteos[tabla] = cursor.fetchone()[0]
    return conteos


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Inyecta el estado base de reseñas de negocios locales (Goodyear, AZ)."
    )
    parser.add_argument(
        "--solo-verificar",
        action="store_true",
        help="No escribe nada; solo reporta qué tablas existen y cuántas filas tienen.",
    )
    argumentos = parser.parse_args()

    url = obtener_url_conexion()
    print(f"Datos semilla: {DIRECTORIO_DATOS}")

    # ¿Por qué abrimos la conexión sin autocommit y hacemos un único commit al final? Para
    # que la carga sea atómica: o queda el estado base completo, o no queda nada. Un
    # `DROP TABLE` exitoso seguido de un `INSERT` fallido dejaría la base vacía y al
    # estudiante sin punto de partida. En una transacción, ese escenario simplemente no
    # existe: el rollback devuelve todo al estado anterior.
    conexion = psycopg2.connect(url)
    conexion.autocommit = False
    try:
        if argumentos.solo_verificar:
            conteos = verificar(conexion)
            print("\nEstado actual de la base:")
            for tabla, n in conteos.items():
                print(f"  {tabla:<18} {'(no existe)' if n < 0 else f'{n:>6} filas'}")
            return 0

        cargadas = inyectar(conexion)
        conexion.commit()

        conteos = verificar(conexion)
        print("\nVerificación post-commit:")
        todo_ok = True
        for tabla in ORDEN_DE_CARGA:
            esperado, real = cargadas[tabla], conteos[tabla]
            ok = esperado == real
            todo_ok &= ok
            print(f"  {'OK ' if ok else 'FAIL'} {tabla:<18} esperado={esperado:>6} real={real:>6}")

        if not todo_ok:
            print("\nLa verificación falló: los conteos no coinciden.", file=sys.stderr)
            return 1

        total = sum(conteos.values())
        print(f"\nEstado base listo. Total: {total} filas en {len(conteos)} tablas.")
        return 0

    except Exception as error:
        conexion.rollback()
        print(f"\nERROR — se revirtió la transacción completa: {error}", file=sys.stderr)
        return 1
    finally:
        conexion.close()


if __name__ == "__main__":
    sys.exit(main())
