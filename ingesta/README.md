# Ingesta — Neon → Snowflake (RAW)

Proyecto Python independiente (gestionado con `uv`, adaptado de la Sesión 4 del curso)
que extrae el modelo propio desde Neon `dev` y lo carga sin transformar en la capa
`RAW` de Snowflake.

## Setup

```bash
uv sync
cp ../.env.example .env   # plantilla única del repo (Neon + Snowflake) — .env nunca se versiona
```

`SNOWFLAKE_PRIVATE_KEY_PATH` se resuelve relativo a la **raíz del repo**, no a esta
carpeta — el script busca `.git/` hacia arriba para anclarse, igual que
`scripts/inyeccion_semilla.py`. No hace falta ajustar la ruta del `.env.example` al
copiarlo aquí.

Requiere haber corrido antes `../snowflake/setup/setup_snowflake.sql` (aprovisiona
Snowflake) y `../snowflake/setup/generate_keypair.sh` (genera tu llave de autenticación
— cada integrante genera la suya, no se comparte el `.p8`).

## Uso

```bash
uv run elt_neon_to_snowflake.py --solo-verificar   # detecta schema drift, no escribe
uv run elt_neon_to_snowflake.py                    # carga las 6 tablas
uv run elt_neon_to_snowflake.py --tabla review      # carga solo una tabla
```

## Qué carga

`category`, `business`, `business_category`, `users`, `review`, `tip` — el modelo del
Momento 1 (baseline + migración `tip`). No incluye `business_hours` ni `checkin`: quedaron
fuera del alcance del Momento 1 (ver `../docs/dominio_de_negocio.md`).

## Autenticación a Snowflake

Por par de llaves RSA, no por contraseña. `SVC_YELP_LOADER` es un usuario de servicio
**compartido por el equipo** — Snowflake permite registrar dos llaves públicas por
usuario (`RSA_PUBLIC_KEY` / `RSA_PUBLIC_KEY_2`), así que cada integrante usa un slot
distinto. Ver el comentario en `../snowflake/setup/setup_snowflake.sql`.
