# dbt — transformación (Momento 3)

Proyecto dbt sobre `YELP_GOODYEAR_DW`, arquitectura **Medallón** (mismo patrón enseñado en
la Sesión 7 del curso):

- **Bronze** — `RAW`/`STAGING` de Snowflake, ya existentes (Momento 1/2, fuera de este
  proyecto).
- **Silver** — `models/staging/`: un modelo por fuente cruda, cast/rename, `VIEW`.
- **Gold** — `models/core/`: modelos listos para consumo, `ref()` exclusivamente sobre
  Silver, `TABLE`. Hoy son 2: `dim_business_reputation` (reputación por negocio) y
  `fct_business_hours_performance` (cruza horario semi-estructurado de la Sesión 5 con
  reseñas relacionales del Momento 1).

> **Fuera de alcance de este Momento** (según `momento_3.md`, actualizado por el profesor
> el 28/08): modelos incrementales y capa de entrega/dashboard (Streamlit). No se
> enseñaron en la única sesión de contenido (Sesión 7) y no se evalúan.

Entorno Python **separado** del resto del repo (`dbt/pyproject.toml`, `dbt/.venv/`):
`dbt-snowflake` fija sus propias versiones de dependencias.

## Setup

```bash
cd dbt
uv sync                          # crea dbt/.venv con dbt-snowflake
cp profiles.yml.example profiles.yml
```

`profiles.yml` lee todo con `env_var()` de las **mismas variables `SNOWFLAKE_*`** del
`.env` de la raíz (mismo usuario de servicio `SVC_YELP_LOADER`, misma llave RSA — ver
[`../snowflake/setup/README.md`](../snowflake/setup/README.md)). Antes de invocar dbt:

```bash
set -a && source ../.env && set +a
export SNOWFLAKE_PRIVATE_KEY_PATH="../snowflake/setup/keys/rsa_key.p8"  # ver nota abajo
uv run dbt deps --profiles-dir .     # instala dbt_expectations
uv run dbt debug --profiles-dir .    # valida conexión
```

> **Por qué el `export` extra de `SNOWFLAKE_PRIVATE_KEY_PATH`.** El `.env` de la raíz
> define esa ruta relativa a la raíz del repo (la usan `scripts/inyeccion_semilla.py` e
> `ingesta/`, que se anclan ahí). dbt resuelve rutas relativas desde donde se invoca
> (`dbt/`), no desde la raíz — sobreescribirla evita que apunte a
> `dbt/snowflake/setup/keys/...` (no existe).

**Antes de correr `dbt run`/`dbt build` por primera vez**, alguien con `ACCOUNTADMIN` debe
correr una vez [`../snowflake/setup/07_dbt_analytics_schema.sql`](../snowflake/setup/07_dbt_analytics_schema.sql):
le da a `YELP_LOADER_ROLE` el privilegio `CREATE SCHEMA` sobre la base de datos — hoy no
lo tiene (confirmado en vivo: `dbt run` falla con `003001/42501`). Con ese privilegio, dbt
crea y es dueño de `ANALYTICS_STAGING`/`ANALYTICS_CORE` la primera vez que corre (uno por
capa, vía `+schema` en `dbt_project.yml`) — no hace falta pre-crear nada más.

```bash
uv run dbt run --profiles-dir .
uv run dbt test --profiles-dir .
uv run dbt build --profiles-dir .    # run + test respetando el orden del grafo
uv run dbt docs generate --profiles-dir . && uv run dbt docs serve
```

## Estructura

```
dbt/
├── dbt_project.yml
├── packages.yml               ← dbt_expectations (metaplane), para C3 de la rúbrica
├── profiles.yml.example       ← plantilla, sin credenciales
├── models/
│   ├── staging/                ← Silver: un modelo por fuente cruda, sin lógica de negocio
│   │   ├── _sources.yml
│   │   └── _staging__models.yml
│   └── core/                   ← Gold: ≥2 modelos, ≥1 cruzando dos orígenes de datos
│       (relacional de Momento 1 + semi-estructurado de Momento 2 Sesión 5)
├── tests/                      ← tests singulares (reglas de negocio, no estructurales)
├── macros/
└── seeds/ · snapshots/ · analyses/
```
