# Evidencias — Momento 1

Este documento reúne, en orden cronológico, la evidencia de que el pipeline de CI/CD sobre
la base de datos funciona como se decidió: **`main` protegida, cero push directo, todo
cambio vía Pull Request con un status check obligatorio**, y de que el estado base quedó
correctamente cargado en Neon. Se va llenando a medida que avanza cada fase del desarrollo —
cada sección nueva se agrega con sus capturas en [`images/`](images/).

---

## 1. Protección de la rama `main`

Regla creada en GitHub → *Settings → Rules → Rulesets*: **"No push to main"**, con 4 branch
rules aplicadas sobre la rama `main`.

![Ruleset "No push to main" activo sobre la rama main](images/no_push_to_main_rule.png)

**Qué prueba:** que la protección de rama no quedó solo documentada en el plan, sino
configurada y activa en el repositorio real.

### Verificación: intento de push directo, rechazado

Se intentó (a propósito, como prueba) un `git push origin main` directo, sin pasar por PR:

![Terminal mostrando el push directo a main rechazado por GitHub](images/push_error.png)

```text
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
remote: - Required status check "flyway-validate" is expected.
error: failed to push some refs to 'https://github.com/vavelezr/Momento_01_Tendencias.git'
```

**Qué prueba:**
- GitHub rechaza el push directo con el código `GH013`, exigiendo explícitamente un Pull
  Request — confirma la decisión técnica de `main` protegida, sin excepciones ni siquiera
  para administradores.
- El mensaje ya exige el status check `flyway-validate` como obligatorio, aunque el workflow
  que lo genera todavía no existe en el repo en este punto — la regla se configuró *antes*
  que el pipeline, a propósito.

---

## 2. Estado base cargado en Neon

Ejecución de [`scripts/inyeccion_semilla.py`](../../scripts/inyeccion_semilla.py) — crea el
schema baseline (`category`, `business`, `users`, `business_category`, `review`) y carga los
datos de [`data/`](../../data/): **9 105 filas en 5 tablas**.

### Carga en la branch `dev`

Primero `--solo-verificar` (las 5 tablas reportan "no existe"), luego la carga real:

![Terminal: verificación previa y carga del estado base en dev](images/verification-add-tables.png)

```text
Estado base listo. Total: 9105 filas en 5 tablas.
```

Conteos por tabla, coincidentes con lo documentado en
[`docs/dominio_de_negocio.md`](../dominio_de_negocio.md): `category` 192, `business` 308,
`users` 2 757, `business_category` 870, `review` 4 978.

### Bootstrap único de la branch `main`

La misma carga, corrida **una sola vez** contra `main` — para que exista un schema que
Flyway pueda adoptar con `baseline` en la fase siguiente. A partir de aquí, `main` no vuelve
a recibir un script manual: solo cambia por pipeline.

![Terminal: bootstrap del estado base en main](images/add-table-main-one-time.png)

**Qué prueba:** que ambas branches de Neon (`dev` y `main`) arrancan desde el mismo estado
base, con integridad verificada (conteos esperados = reales en las 5 tablas), antes de que
Flyway entre a gestionar el esquema.

---

## 3. Migraciones Flyway aplicadas: baseline + `V__` + `R__`

`flyway info` antes de aplicar la migración repetible, seguido de `flyway migrate`:

![Terminal: flyway info mostrando baseline + 3 V__ Success + R__ Pending, luego flyway migrate aplicándola](images/R_applied.png)

```text
Schema version: 20260808190400

 Category    | Version      | Description         | Type | State    |
 ------------|--------------|----------------------|------|----------|
             | 1            | Yelp database base   | BASELINE | Baseline |
 Versioned   | 20260808190100 | add primary category | SQL  | Success  |
 Versioned   | 20260808190200 | add tip              | SQL  | Success  |
 Versioned   | 20260808190400 | add index review     | SQL  | Success  |
 Repeatable  |              | fn nivel negocio     | SQL  | Pending  |

Successfully validated 5 migrations (execution time 00:00.402s)
Migrating schema "public" with repeatable migration "fn nivel negocio"
Successfully applied 1 migration to schema "public" (execution time 00:00.825s)
```

**Qué prueba:**
- El `baseline` (versión 1) y las 3 migraciones `V__` (`add_primary_category`, `add_tip`,
  `add_index_review`) están realmente aplicadas — no son solo archivos `.sql` en el repo sin
  ejecutar.
- `R__fn_nivel_negocio` pasa de `Pending` a aplicada tras el `migrate`, confirmando que
  Flyway detecta el archivo nuevo por checksum y lo corre sin necesitar una migración
  versionada aparte.
- `flyway validate` (parte de `migrate`) pasó sin errores sobre las 5 migraciones antes de
  aplicar nada — la misma puerta de calidad que se automatiza en el workflow de la Fase 5.

> Corrido localmente contra la branch `dev` de Neon, siguiendo la regla del proyecto: la
> terminal de un integrante nunca toca `main` directamente salvo el bootstrap único ya
> documentado en la sección 2. `main` recibirá estas mismas migraciones cuando exista el
> workflow de despliegue (Fase 5).

---

## 4. Primer run del workflow de despliegue: falla real de pipeline, diagnosticada y corregida

Al mergear el PR de la Fase 5, `Flyway Deploy` corrió por primera vez contra `main` — y
falló, como era esperable dado que `main` todavía no tenía el `baseline` corrido:

![Historial de Actions: flyway-validate en el PR (éxito) y Flyway Deploy tras el merge (fallo)](images/first-execution-jobs-ci.png)

```text
Schema history table "public"."flyway_schema_history" does not exist yet
ERROR: Validate failed: Migrations have failed validation
Detected resolved migration not applied to database: 20260808190100.
To fix this error, either run migrate, or set -ignoreMigrationPatterns='*:pending'.
Detected resolved migration not applied to database: 20260808190200.
Detected resolved migration not applied to database: 20260808190400.
Detected resolved repeatable migration not applied to database: fn nivel negocio.
Error: Process completed with exit code 1.
```

![Log del paso Flyway validate mostrando el error de migraciones pendientes](images/first-execution-error-ci.png)

**Diagnóstico:** el paso `Flyway validate` de ambos workflows (`flyway-migrate.yml` y
`flyway-validate-pr.yml`) no tenía el flag `-ignoreMigrationPatterns='*:pending'` — que sí
está presente en la plantilla original del curso
(`data_ops_course_101/.github/workflows/flyway-migrate.yml`). Sin ese flag, `validate`
trata cualquier migración todavía no aplicada como un error, lo cual bloquea *cualquier*
deploy real (toda migración nueva es "pendiente" hasta que `migrate` la aplica un paso
después). Es un bug de configuración del pipeline, no del schema ni de los datos.

**Corrección (roll forward, no se edita el run que ya falló):** se agregó el flag faltante
a ambos workflows en una rama nueva (`fix/ci-validate-ignore-pending`). De paso, el equipo
revisó la decisión original de `flyway.conf.example` (baseline manual, sin
`baselineOnMigrate`) y decidió cambiarla **solo para los workflows de CI/CD**: ahora usan
`-baselineOnMigrate=true`, así que el siguiente deploy contra `main` se auto-baselinea sin
necesitar el paso manual que se había documentado antes. El uso local sigue siendo manual
(`flyway.conf` no fija ese flag) — la decisión y su alternativa descartada quedan
documentadas en el comentario de [`flyway-migrate.yml`](../../.github/workflows/flyway-migrate.yml).

**Qué prueba:** que el pipeline realmente se ejecuta contra Neon (no es un mock), que
`flyway validate` sí actúa como puerta de calidad real (bloqueó el deploy en vez de dejarlo
pasar a medias), y que el equipo puede diagnosticar y corregir un fallo de CI real con
evidencia trazable en GitHub Actions — el mismo patrón que se usará en la Fase 6 para el
error de diseño intencional en `primary_category`.

---

## Pendiente de documentar (se agrega en cada fase siguiente)

- [x] `flyway baseline` sobre `dev` — ver sección 3
- [x] `flyway baseline` sobre `main` — automático vía `-baselineOnMigrate=true` en el primer deploy exitoso (ya no requiere paso manual, ver sección 4)
- [x] Workflow `flyway-validate-pr.yml` corriendo en un PR (éxito) — ver sección 4
- [x] Workflow `flyway-migrate.yml` corriendo tras un merge a `main` (fallo real, diagnosticado) — ver sección 4
- [ ] Workflow `flyway-migrate.yml` corriendo con éxito tras el fix (`-ignoreMigrationPatterns` + `-baselineOnMigrate=true`)
- [x] Runs de las migraciones `V__`/`R__` contra `dev` — ver sección 3
- [ ] Runs de las migraciones `V__`/`R__` contra `main` (vía pipeline)
- [ ] Falla real por un error de diseño (no de pipeline) + roll forward — Fase 6, pendiente
- [ ] Roll forward de `primary_category` corregido y desplegado — Fase 6
