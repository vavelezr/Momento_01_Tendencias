# Documento de decisiones — Momento 2 (E8)

Cubre las decisiones de diseño de la Sesión 5 (Puntos 3-5 del Momento 2: ingesta
semi-estructurada, orquestación con Tasks, RBAC + Masking) sobre el dominio de reseñas de
negocios locales de Goodyear, AZ — ver [`docs/dominio_de_negocio.md`](dominio_de_negocio.md).

---

## 1. Fuente semi-estructurada: horario semanal, no check-ins

**Decisión:** se eligió `data/business_hours.json` (horario de atención semanal por
negocio), agrupado por `business_id` en un array anidado `weekly_hours`, en vez de
`data/checkins.json`.

**Por qué:**
- Ninguna de las dos fuentes trae anidamiento tal como está en el dataset — ambas son un
  registro plano por fila (un negocio + un día, o un negocio + una franja horaria). La
  rúbrica exige un array anidado real, así que cualquiera de las dos requería el mismo
  trabajo de transformación (agrupar por negocio y generar un export simulado, como el
  `marketing_leads_*.json` visto en clase).
- `business_hours` quedó explícitamente fuera del alcance relacional del Momento 1 (ver
  `docs/dominio_de_negocio.md`, nota "Alcance de este Momento 1") — es exactamente el
  caso que describe el enunciado: una segunda fuente, más desordenada, que también
  importa para el negocio pero que el modelo transaccional no cubre.
- `checkins.json` es ~52 000 registros de origen frente a ~1 026 de `business_hours` —
  semánticamente es un dato más rico (patrones de afluencia por franja horaria), pero
  requiere más contexto de negocio para justificar en los 10 minutos de la sustentación
  que el horario, que se explica solo.
- **Alternativa descartada:** check-ins agrupados por negocio (array `checkin_slots` con
  `day_index`, `hour_of_day`, `checkin_count`). Se descartó por la razón de tiempo de
  exposición explicada arriba, no porque fuera técnicamente inferior.

**Cómo se generó el export:** [`scripts/generar_export_business_hours.py`](../scripts/generar_export_business_hours.py)
agrupa el horario real por `business_id` (100% dato real, ninguna hora inventada) y
mockea con Faker únicamente el metadata de trazabilidad que un sistema real de
exportación agregaría solo (`export_batch_id`, `generated_at`) — dos archivos
(`business_hours_export_1.json`, `_2.json`, 77 negocios cada uno), simulando dos
corridas semanales sucesivas del export.

---

## 2. Dónde se alojó: Internal Stage, no bucket S3 propio

**Decisión:** Internal Stage de Snowflake (`stg_business_hours_internal`), subiendo los
archivos vía Snowsight *Upload Files* (equivalente a `PUT` desde SnowSQL).

**Por qué:**
- El bucket S3 público de solo lectura era la opción recomendada por el docente (mismo
  patrón que usó para `marketing_leads`), pero requiere una cuenta AWS con permisos para
  crear buckets y editar bucket policies — nadie del equipo tenía eso disponible a
  tiempo antes del deadline de código.
- El Internal Stage es explícitamente válido para el alcance de este momento: la
  rúbrica solo excluye `STORAGE INTEGRATION` con IAM (fuera de alcance), no el uso de
  stages externos en general — y el propio docente usó el Internal Stage como
  *fallback* mientras preparaba el bucket público, según el README de la Sesión 5.
- **Alternativa descartada:** bucket S3 propio con bucket policy de lectura pública. Se
  descartó únicamente por disponibilidad de cuenta AWS del equipo, no por una limitación
  técnica del patrón — de hecho es la opción que más se acerca a un escenario real de
  producción (external stage sobre un bucket controlado por el equipo de datos).

---

## 3. Roles de negocio: por qué esos dos y qué ve cada uno

**Decisión:** dos roles de negocio, además de `YELP_LOADER_ROLE` (que es de servicio, no
de negocio):

| Rol | Ve | Análogo en clase |
|---|---|---|
| `ROLE_YELP_DATA_ANALYST` | Todo el dato de `RAW` y `STAGING`, incluida PII sin enmascarar | `ROLE_DATA_ENGINEER` |
| `ROLE_YELP_BUSINESS_OWNER` | Dato operativo (`BUSINESS`, `REVIEW`, `TIP`, `USERS`, horario aplanado), PII enmascarada | `ROLE_BUSINESS_MANAGER` |

**Por qué esos dos y no otros:**
- Reflejan las dos personas reales que consumirían este dato en un negocio de reseñas:
  alguien de datos/analítica que necesita ver todo para hacer su trabajo (detectar
  fraude, calidad de reseñas, auditoría), y el dueño de un negocio que solo necesita ver
  su propia operación (reseñas, tips, horario) sin exponer datos personales de usuarios
  que no le corresponden.
- Es el mismo patrón de separación que usó la clase (`ROLE_DATA_ENGINEER` /
  `ROLE_BUSINESS_MANAGER`), adaptado al dominio: no hay representantes de ventas ni
  territorios en este negocio de consumo masivo, así que no aplican roles análogos a
  los de Parch & Posey.
- `ROLE_YELP_DATA_ANALYST` tiene `SELECT` sobre `ALL TABLES` + `FUTURE TABLES` en `RAW`
  y `STAGING` (no necesita que alguien le conceda acceso a mano cada vez que se cree una
  tabla nueva). `ROLE_YELP_BUSINESS_OWNER` tiene grants explícitos tabla por tabla —
  intencionalmente más restrictivo, porque su acceso debe quedar acotado a lo operativo,
  no crecer solo por default.

---

## 4. Campo enmascarado y criterio

**Decisión:** `USERS.NAME` — único campo de PII del dominio (no hay teléfono ni email en
el modelo, a diferencia del ejemplo de clase que enmascaraba `phone`).

**Criterio de la Masking Policy** (`mask_user_name`, ver
[`snowflake/json/04_rbac_and_masking.sql`](../snowflake/json/04_rbac_and_masking.sql)):

| Rol activo | Qué ve |
|---|---|
| `ROLE_YELP_DATA_ANALYST` | Nombre completo |
| `ROLE_YELP_BUSINESS_OWNER` | Inicial + `.***` (ej. `P.***`) |
| Cualquier otro rol (incluido `ACCOUNTADMIN`) | `***` |

**Por qué ese criterio:** el analista de datos necesita el nombre completo para su
trabajo (p. ej. detectar cuentas duplicadas o patrones de abuso). El dueño de negocio no
necesita saber quién escribió una reseña específica, solo que es una persona real — la
inicial es suficiente contexto sin exponer la identidad completa. Cualquier rol sin una
excepción explícita en la política (incluido `ACCOUNTADMIN`) ve el dato completamente
enmascarado — es una decisión deliberada: la política protege el dato incluso del rol
administrativo si nadie le dio acceso a propósito, en vez de asumir que un privilegio de
cuenta implica acceso a datos sensibles.

**Nota de alcance:** si la cuenta del equipo hubiera sido Standard (no Enterprise),
`CREATE MASKING POLICY` habría fallado con *"Unsupported feature"* — evidencia
igualmente válida según la rúbrica, siempre que la política estuviera bien escrita y el
intento quedara documentado. No fue nuestro caso: la cuenta del equipo sí soporta
Masking Policies.
