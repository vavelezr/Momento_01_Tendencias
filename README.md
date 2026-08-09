# Momento 1 — CI/CD en Base de Datos

**Módulo:** Tendencias emergentes en desarrollo de software (SI6010-5979) · Pos ST1707
**Entregable:** Momento evaluativo 1 — CI/CD sobre un dominio de negocio propio

Este repositorio implementa, sobre un dominio propio, el patrón enseñado en el curso: estado
base versionado en **Neon** (PostgreSQL serverless, branches `main`/`dev` aisladas),
migraciones de esquema con **Flyway**, y despliegue automatizado con **GitHub Actions**.

---

## El dominio: reseñas de negocios locales (Goodyear, AZ)

Los datos son una muestra real del [Yelp Academic Dataset]: todos los negocios de
**Goodyear, AZ** (un suburbio de Phoenix, 308 negocios) junto con sus categorías, reseñas,
tips y los usuarios que los escribieron. Descripción completa y diagrama entidad-relación
en [`docs/dominio_de_negocio.md`](docs/dominio_de_negocio.md).

**Por qué este dominio y no otro:**

- **Es un dataset real, no un ejercicio sintético.** Trae los problemas de un dataset real —
  categorías con nombres largos que rompen un `VARCHAR` mal dimensionado, fechas con
  precisión inconsistente (`yelping_since` solo trae año-mes), campos que existen en el JSON
  pero no en el modelo original — y esos problemas son justamente los que generan decisiones
  de ingeniería defendibles, no solo un CRUD de relleno.
- **Es deliberadamente distinto a Parch & Posey**, el ejemplo del curso. Parch & Posey es
  B2B: una empresa le vende a cuentas corporativas a través de representantes de ventas y
  territorios. Este dominio es de consumo masivo: miles de usuarios independientes
  interactuando con negocios, sin ninguna jerarquía de ventas. El modelo, las preguntas de
  negocio y hasta el tipo de migraciones que tiene sentido escribir son distintos por
  diseño — no es el mismo schema con nombres de tabla cambiados.
- **El tamaño es el correcto para el problema.** El Yelp Academic Dataset completo pesa
  ~1.3 GB y excede el tier gratuito de Neon (0.5 GB); acotarlo a una sola ciudad deja
  ~21 000 filas en 8 entidades relacionadas (5-6 tablas + relación N:N + funciones) —
  suficiente complejidad relacional para justificar Flyway, sin necesitar una tarjeta de
  crédito.

**Preguntas de negocio que el modelo responde** (ver más en `docs/dominio_de_negocio.md`):
¿qué categoría de negocio tiene mejor calificación promedio? ¿qué negocios tienen reseñas
pero ningún tip, o viceversa? ¿qué tan bien correlacionan calificación y volumen de reseñas
(la función `fn_nivel_negocio`, sección "Lógica de negocio" más abajo)?

---

## Decisiones técnicas clave

| Decisión | Por qué |
|---|---|
| `main` protegida, cero push directo, todo vía PR | El entorno destino nunca es implícito: un commit local mal apuntado no debe poder tocar producción sin revisión — ver evidencia en [`docs/evidences/`](docs/evidences/) §1. |
| Dos branches de Neon (`dev`/`main`), aisladas | `dev` es el banco de pruebas real de cada migración; `main` solo cambia por pipeline, nunca por una terminal. |
| Migraciones atómicas, un propósito por archivo | Una tabla nueva, una columna nueva, un índice/restricción — nunca mezclados — para que un roll forward corrija exactamente una cosa. |
| Dos workflows separados (`validate` en PR, `deploy` en push) | La misma imagen fija de Flyway corre en ambos: lo que se valida en el PR es *exactamente* lo que se despliega después, no una aproximación. |

---

## Estado del repositorio

| Pieza | Estado |
|---|---|
| Dominio de negocio + ER | ✅ [`docs/dominio_de_negocio.md`](docs/dominio_de_negocio.md) |
| Estado base (schema + carga) | ✅ [`scripts/inyeccion_semilla.py`](scripts/inyeccion_semilla.py) |
| Protección de rama `main` | ✅ ruleset "No push to main" |
| Configuración Flyway + baseline | ✅ [`flyway.conf.example`](flyway.conf.example) |
| Migraciones Flyway (`V__`/`R__`) | ✅ 4 `V__` (tabla, columna, índice/restricción, fix de columna) + 1 `R__` en [`sql_migrations/`](sql_migrations/) |
| Workflows de CI/CD | ✅ [`.github/workflows/`](.github/workflows/) — deploy a `main` + validación en cada PR contra `dev` |
| Falla real + roll forward documentados | ✅ [`docs/evidences/`](docs/evidences/) §5 |

Detalle completo de cada corrida (capturas de terminal y de GitHub Actions) en
[`docs/evidences/README.md`](docs/evidences/README.md).

---

## Tech stack

| Capa | Tecnología |
|---|---|
| Base de datos OLTP | **Neon.tech** (PostgreSQL serverless) — branches `main`/`dev` |
| Control de versiones | GitHub, con `main` protegida (solo vía Pull Request) |
| Migraciones de esquema | Flyway |
| CI/CD | GitHub Actions |
| Carga inicial / scripts | Python, gestionado con **`uv`** (nunca `pip`/`venv` a mano) |

---

## Prerrequisitos

```bash
git --version
uv --version     # https://docs.astral.sh/uv/  — curl -LsSf https://astral.sh/uv/install.sh | sh
flyway -v        # https://documentation.red-gate.com/fd/command-line-184127404.html
```

Cuenta en [Neon.tech](https://neon.tech) (tier gratuito) con acceso al proyecto del equipo.

---

## Cómo levantar el proyecto localmente

### 1. Clonar y sincronizar el entorno Python

```bash
git clone https://github.com/vavelezr/Momento_01_Tendencias.git
cd Momento_01_Tendencias
uv sync
```

`uv sync` lee `pyproject.toml` y `uv.lock` y crea `.venv` con las dependencias exactas
(`psycopg2-binary`, `python-dotenv`).

### 2. Configurar credenciales

```bash
cp .env.example .env
```

Edita `.env` y pega tus dos connection strings de Neon (Neon Console → tu proyecto →
Dashboard → *Connection string*, seleccionando la branch correspondiente en el desplegable
antes de copiar). `.env` **no se versiona** — está en `.gitignore`.

> ⚠️ Los GitHub Secrets del repositorio (`NEON_DEV_DATABASE_URL`, `NEON_MAIN_DATABASE_URL`)
> **no se pueden releer** una vez guardados — son de solo escritura y solo los usa el
> workflow en ejecución. Para trabajar en local necesitas tus propios connection strings,
> obtenidos directamente del Neon Console.

### 3. Cargar el estado base

```bash
uv run scripts/inyeccion_semilla.py --solo-verificar   # no escribe; reporta el estado actual
uv run scripts/inyeccion_semilla.py                     # crea el schema y carga los datos
```

Esto crea las 5 tablas del baseline (`category`, `business`, `users`, `business_category`,
`review`) y carga los datos de [`data/`](data/) — **9 105 filas** en total. El script tiene
un guardrail: se niega a correr si `NEON_DEV_DATABASE_URL` y `NEON_MAIN_DATABASE_URL`
apuntan a la misma base (hace `DROP TABLE`, y el destino nunca debe ser implícito).

Salida esperada:

```text
Verificación post-commit:
  OK  category            192 filas
  OK  business             308 filas
  OK  users               2757 filas
  OK  business_category    870 filas
  OK  review              4978 filas

Estado base listo. Total: 9105 filas en 5 tablas.
```

La tabla `tip` y la columna `business.primary_category` **no** forman parte del baseline:
llegan después vía migraciones Flyway (`V__`) — ver la sección 3 de
[`docs/dominio_de_negocio.md`](docs/dominio_de_negocio.md).

### Aprovisionar el proyecto en Neon (una sola vez por integrante/entorno)

1. [console.neon.tech](https://console.neon.tech) → **Create project** → Postgres 16.
2. Neon crea la branch `main` por defecto — **queda vacía**, es la referencia intocable.
3. **Branches → Create branch**: nombre `dev`, parent `main`. Ya tienes dos bases
   independientes.
4. Copia ambos connection strings (paso 2 más arriba).
5. Corre la carga (paso 3 de "Cómo levantar el proyecto") apuntando **solo a `dev`**.
6. **Bootstrap único de `main`** (una sola vez en todo el proyecto, de forma deliberada y
   documentada — no es lo mismo que tratar `main` como banco de pruebas):

   ```bash
   NEON_DEV_DATABASE_URL="<connection string de tu branch main>" \
   NEON_MAIN_DATABASE_URL="" \
     uv run scripts/inyeccion_semilla.py
   ```

   De aquí en adelante, `main` **solo** cambia por pipeline (Flyway + GitHub Actions) — nunca
   más se le apunta un script manual.

---

## Flyway — control de versiones del schema

A partir de aquí, ningún cambio de schema se hace corriendo `inyeccion_semilla.py` de
nuevo: se hace con migraciones versionadas en [`sql_migrations/`](sql_migrations/)
(`V__` evolutivas, `R__` repetibles). Flyway necesita saber, antes de aplicar la primera
migración, que el schema del baseline ya existe — eso es lo que hace `baseline`.

### 1. Configurar `flyway.conf`

```bash
cp flyway.conf.example flyway.conf
```

Edita `flyway.conf` y pega tu connection string de Neon **convertido a formato JDBC** (el
archivo trae el detalle de la conversión en un comentario). `flyway.conf` no se versiona —
está en `.gitignore`, igual que `.env`.

### 2. Correr el baseline (una vez por entorno: primero `dev`, luego `main`)

Requiere que `scripts/inyeccion_semilla.py` ya se haya corrido contra ese entorno (el
baseline le dice a Flyway "este schema que ya existe, cuéntalo como la versión 1" — no crea
nada por sí mismo).

```bash
flyway -configFiles=flyway.conf baseline
```

Salida esperada: `Successfully baselined schema with version: 1`.

> Este paso es solo para trabajar **en local**. Los workflows de CI/CD (siguiente sección)
> **no** lo necesitan contra `main` — lo resuelven solos en su primer run
> (`-baselineOnMigrate=true`).

---

## Workflows de CI/CD

Dos workflows en [`.github/workflows/`](.github/workflows/), ambos con la misma imagen
Docker fijada (`flyway/flyway:13.1.0-alpine`) para que local y CI corran exactamente lo
mismo:

| Workflow | Dispara con | Contra | Qué hace |
|---|---|---|---|
| [`flyway-validate-pr.yml`](.github/workflows/flyway-validate-pr.yml) | `pull_request` hacia `main`, tocando `sql_migrations/` | Neon `dev` | `flyway validate` + `flyway migrate`. Es el status check `flyway-validate` que el ruleset de `main` exige en verde antes de mergear. |
| [`flyway-migrate.yml`](.github/workflows/flyway-migrate.yml) | `push` a `main`, tocando `sql_migrations/` | Neon `main` | `flyway validate` + `flyway migrate`. Es lo único que efectivamente escribe en producción — corre después de cada merge. |

Ninguno usa `flyway clean` (`-cleanDisabled=true`). Cuando alguien edita una migración ya
aplicada en vez de escribir una nueva, `flyway validate` falla con *checksum mismatch* y
bloquea el PR antes de tocar la base — evidencia real de esto en
[`docs/evidences/README.md`](docs/evidences/README.md) §5.

---

## Flujo de trabajo del repositorio

`main` está protegida con un *ruleset* de GitHub ("No push to main"): **no se permite push
directo**, ni siquiera a administradores. Todo cambio sigue este flujo:

```bash
git checkout main && git pull
git checkout -b feature/lo-que-sea
# ... cambios, commits con mensajes tipo feat(db): / fix(db): / docs: / ci: ...
git push origin feature/lo-que-sea
# abrir Pull Request hacia main, esperar aprobación + status checks en verde, mergear
```

Ver [`docs/evidences/`](docs/evidences/) §1 para la prueba de que la protección está activa
(incluye el rechazo real de un intento de push directo).

### Secretos y seguridad

- Cero credenciales en el repositorio, verificado también en el historial de commits (solo
  hay placeholders del tipo `usuario:password@ep-xxxx`, nunca un connection string real).
- `.env` y `flyway.conf` están en `.gitignore` — cada integrante mantiene los suyos en
  local, nunca se comparten por git.
- Los dos secretos reales viven únicamente en GitHub → *Settings → Secrets and variables →
  Actions*:

| Secreto | Contenido | Usado por |
|---|---|---|
| `NEON_DEV_DATABASE_URL` | Connection string de la branch `dev` de Neon | [`flyway-validate-pr.yml`](.github/workflows/flyway-validate-pr.yml) |
| `NEON_MAIN_DATABASE_URL` | Connection string de la branch `main` de Neon | [`flyway-migrate.yml`](.github/workflows/flyway-migrate.yml) |

---

## Estructura del repositorio

```
Momento_01_Tendencias/
├── README.md                    ← este archivo
├── pyproject.toml / uv.lock      ← proyecto Python (uv)
├── .env.example                  ← plantilla de credenciales (sin valores reales)
├── flyway.conf.example            ← plantilla de configuración de Flyway
├── data/                         ← datos semilla (JSON), fuente de verdad de la muestra
├── scripts/
│   └── inyeccion_semilla.py      ← carga el estado base en Neon
├── sql_migrations/                ← migraciones Flyway: 4 V__ + 1 R__
├── docs/
│   ├── dominio_de_negocio.md     ← descripción del dominio + diagrama ER
│   └── evidences/                ← capturas y evidencia de cada fase, incluida la Fase 6
└── .github/workflows/
    ├── flyway-validate-pr.yml    ← corre en cada PR, contra dev
    └── flyway-migrate.yml        ← corre en cada push a main, contra main
```

[Yelp Academic Dataset]: https://www.yelp.com/dataset
