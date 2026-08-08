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

## Pendiente de documentar (se agrega en cada fase siguiente)

- [x] `flyway baseline` sobre `dev` — ver arriba (sección 3)
- [ ] `flyway baseline` sobre `main`
- [ ] Workflow `flyway-validate-pr.yml` corriendo en un PR (éxito) — Fase 5
- [ ] Workflow `flyway-migrate.yml` corriendo tras un merge a `main` (éxito) — Fase 5
- [x] Runs de las migraciones `V__`/`R__` contra `dev` — ver arriba (sección 3)
- [ ] Runs de las migraciones `V__`/`R__` contra `main` (vía pipeline)
- [ ] Falla real por editar una migración ya aplicada (checksum mismatch en CI) — Fase 6
- [ ] Roll forward corregido y desplegado — Fase 6
