# dbt — transformación (Momento 3)

Proyecto dbt sobre `YELP_GOODYEAR_DW`, capas `staging/` → `intermediate/` → `marts/`.
Consume las tablas de `RAW` (Momento 1/2, vía [`ingesta/`](../ingesta/)) y de `STAGING`
(JSON aplanado, Momento 2 Sesión 5, vía [`snowflake/json/`](../snowflake/json/)) como
`source()`, nunca directamente por nombre de tabla — así el lineage queda completo en
`dbt docs generate`.

Entorno Python **separado** del resto del repo (`dbt/pyproject.toml`, `dbt/.venv/`):
`dbt-snowflake` fija sus propias versiones de dependencias y no conviene mezclarlo con el
`uv sync` de la raíz.

## Setup

```bash
cd dbt
uv sync                          # crea dbt/.venv con dbt-snowflake
cp profiles.yml.example profiles.yml
```

Edita `profiles.yml` con los mismos valores `SNOWFLAKE_*` de tu `.env` de la raíz (mismo
usuario de servicio `SVC_YELP_LOADER`, misma llave RSA — ver
[`../snowflake/setup/README.md`](../snowflake/setup/README.md)). `profiles.yml` nunca se
versiona.

**Antes de correr `dbt run` por primera vez**, alguien con `ACCOUNTADMIN` debe correr una
vez [`../snowflake/setup/07_dbt_analytics_schema.sql`](../snowflake/setup/07_dbt_analytics_schema.sql):
crea el esquema `ANALYTICS` (destino de todo lo que construye dbt) y le da a
`YELP_LOADER_ROLE` los privilegios `CREATE TABLE` / `CREATE VIEW` ahí — hoy ese rol solo
tiene `CREATE TABLE` sobre `RAW`/`STAGING` (Momento 2), no sobre `ANALYTICS` ni
`CREATE VIEW` en ningún esquema.

```bash
uv run dbt debug     # valida conexión — no necesita que ANALYTICS ya exista
uv run dbt run       # sí necesita el script anterior ya corrido
uv run dbt test
uv run dbt docs generate && uv run dbt docs serve
```

## Por qué `ANALYTICS` y no reusar `STAGING`

`STAGING` (el esquema de Snowflake) ya existe desde el Momento 2 y guarda
`STG_BUSINESS_HOURS_FLATTENED` — un JSON aplanado, no un modelo dbt. Meter ahí también
`stg_category`, `mart_business_performance`, etc. mezclaría dos cosas con el mismo nombre
pero distinto origen (carga manual vs. `dbt build`). Un esquema propio (`ANALYTICS`)
mantiene esa frontera clara: todo lo que hay ahí lo construyó dbt y se puede reconstruir
desde cero con `dbt build`.

## Estructura

```
dbt/
├── dbt_project.yml
├── profiles.yml.example      ← plantilla, sin credenciales
├── models/
│   ├── staging/               ← una vista por tabla fuente, sin lógica de negocio
│   │   ├── _sources.yml
│   │   └── _staging__models.yml
│   ├── intermediate/          ← agregados reutilizables entre marts
│   └── marts/                 ← tablas listas para consumo (Streamlit, ad-hoc)
├── tests/                     ← tests singulares (reglas de negocio, no estructurales)
├── macros/
└── seeds/ · snapshots/ · analyses/
```
