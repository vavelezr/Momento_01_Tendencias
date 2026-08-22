# Snowflake — ingesta JSON, DAG de Tasks y RBAC/Masking (Momento 2, Puntos 3-5)

Segunda fuente del Momento 2: horario semanal por negocio, agrupado en un array anidado
(`weekly_hours`) — ver [`docs/dominio_de_negocio.md`](../../docs/dominio_de_negocio.md) y
[`scripts/generar_export_business_hours.py`](../../scripts/generar_export_business_hours.py)
(genera `data/business_hours_exports/business_hours_export_{1,2}.json`, subidos al
Internal Stage).

Asume que [`snowflake/setup/`](../setup/) ya corrió (database, warehouse, rol de
servicio, esquemas `RAW`/`STAGING`).

## Orden de ejecución

| # | Script | Quién lo corre | Qué deja listo |
|---|---|---|---|
| 1 | [`01_setup_stage_and_raw.sql`](01_setup_stage_and_raw.sql) | `ACCOUNTADMIN` (grants) → `YELP_LOADER_ROLE` | File format, Internal Stage, tabla `RAW.RAW_BUSINESS_HOURS`, `COPY INTO` |
| 2 | [`02_flatten_query_exploration.sql`](02_flatten_query_exploration.sql) | `YELP_LOADER_ROLE` | `LATERAL FLATTEN` explorado, tabla `STAGING.STG_BUSINESS_HOURS_FLATTENED` poblada |
| 3 | [`03_tasks_and_dag_management.sql`](03_tasks_and_dag_management.sql) | `ACCOUNTADMIN` (grants) → `YELP_LOADER_ROLE` | DAG de 2 tasks (`TASK_INGEST_BUSINESS_HOURS` → `TASK_FLATTEN_BUSINESS_HOURS`), activado, disparado y suspendido |
| 4 | [`04_rbac_and_masking.sql`](04_rbac_and_masking.sql) | `ACCOUNTADMIN` | Roles `ROLE_YELP_DATA_ANALYST` / `ROLE_YELP_BUSINESS_OWNER`, Masking Policy sobre `USERS.NAME` |

Todos son idempotentes (`IF NOT EXISTS` / `CREATE OR REPLACE`), salvo el `INSERT` simple
del script 2 (usa `INSERT OVERWRITE` en la versión dentro de la Task del script 3, pero no
en la exploración manual) — correr el script 2 dos veces duplica filas en
`STG_BUSINESS_HOURS_FLATTENED`; si eso pasa, `TRUNCATE TABLE` antes de repetir.

## Notas de administración de Tasks (script 3)

- `EXECUTE TASK ON ACCOUNT` es un privilegio de **cuenta**, no de objeto — se olvida fácil.
- Una task con `AFTER` nace `SUSPENDED` igual que la raíz. Nada corre hasta
  `SYSTEM$TASK_DEPENDENTS_ENABLE('TASK_INGEST_BUSINESS_HOURS')`, que activa la raíz y todo
  su árbol de dependientes de una vez.
- **Al apagar: la raíz primero, siempre.** Tocar la hija (`RESUME` o `SUSPEND`) con la
  raíz todavía activa falla en los dos sentidos — verificado contra la cuenta real, el
  mensaje es *"Unable to update graph with root task ... since that root task is not
  suspended"* (no el 091421 citado en clase, pero la misma regla). El script deja ambos
  intentos fallidos documentados antes del apagado correcto, a propósito, como evidencia
  de haber entendido la regla.

## Campo de PII y la Masking Policy (script 4)

`USERS.NAME` es el único candidato de PII en este dominio (no hay teléfono ni email en el
modelo). La política:

| Rol activo | Ve |
|---|---|
| `ROLE_YELP_DATA_ANALYST` | Nombre completo |
| `ROLE_YELP_BUSINESS_OWNER` | Inicial + `.***` (ej. `P.***`) |
| Cualquier otro rol (incluido `ACCOUNTADMIN`) | `***` |

Si la cuenta es **Standard** (no Enterprise), `CREATE MASKING POLICY` falla con
*"Unsupported feature"* — es evidencia igualmente válida según la rúbrica, siempre que la
política esté bien escrita y el intento quede documentado.
