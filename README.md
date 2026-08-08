# Momento 1 — CI/CD en Base de Datos

**Módulo:** Tendencias emergentes en desarrollo de software (SI6010-5979) · Pos ST1707
**Entregable:** Momento evaluativo 1 — CI/CD sobre un dominio de negocio propio
**Dominio elegido:** reseñas de negocios locales (Goodyear, AZ) — ver
[`docs/dominio_de_negocio.md`](docs/dominio_de_negocio.md) para la descripción completa y
el diagrama entidad-relación.

Este repositorio replica, sobre un dominio propio, el patrón enseñado en las Sesiones 1 y 2
del curso: estado base versionado en **Neon** (PostgreSQL serverless, branches `main`/`dev`
aisladas), migraciones de esquema con **Flyway**, y despliegue automatizado con
**GitHub Actions**.

---

## Estado actual del repositorio

| Pieza | Estado |
|---|---|
| Dominio de negocio + ER | ✅ [`docs/dominio_de_negocio.md`](docs/dominio_de_negocio.md) |
| Estado base (schema + carga) | ✅ [`scripts/inyeccion_semilla.py`](scripts/inyeccion_semilla.py) |
| Protección de rama `main` | ✅ ruleset "No push to main" — ver [`docs/evidences/`](docs/evidences/) |
| Migraciones Flyway (`V__`/`R__`) | 🚧 pendiente |
| Workflows de CI/CD | 🚧 pendiente |
| Evidencia de falla + roll forward | 🚧 pendiente |

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

Las tablas `business_hours`, `tip`, `checkin` y la columna `business.primary_category`
**no** forman parte del baseline: llegan más adelante vía migraciones Flyway (`V__`) — ver
la sección 3 de [`docs/dominio_de_negocio.md`](docs/dominio_de_negocio.md).

### Aprovisionar el proyecto en Neon (una sola vez por integrante/entorno)

1. [console.neon.tech](https://console.neon.tech) → **Create project** → Postgres 16.
2. Neon crea la branch `main` por defecto — **queda vacía**, es la referencia intocable.
3. **Branches → Create branch**: nombre `dev`, parent `main`. Ya tienes dos bases
   independientes.
4. Copia ambos connection strings (paso 3 más arriba).
5. Corre la carga (paso 3 de "Cómo levantar el proyecto") apuntando **solo a `dev`**.
6. **Bootstrap único de `main`** (se hace una sola vez en todo el proyecto, de forma
   deliberada y documentada — no es lo mismo que tratar `main` como banco de pruebas):

   ```bash
   NEON_DEV_DATABASE_URL="<connection string de tu branch main>" \
   NEON_MAIN_DATABASE_URL="" \
     uv run scripts/inyeccion_semilla.py
   ```

   De aquí en adelante, `main` **solo** cambia por pipeline (Flyway + GitHub Actions) — nunca
   más se le apunta un script manual.

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

Ver [`docs/evidences/`](docs/evidences/) para la prueba de que la protección está activa
(incluye el rechazo real de un intento de push directo).

### Secretos requeridos (GitHub → Settings → Secrets and variables → Actions)

| Secreto | Contenido | Usado por |
|---|---|---|
| `NEON_DEV_DATABASE_URL` | Connection string de la branch `dev` de Neon | Workflow de validación en cada PR *(pendiente)* |
| `NEON_MAIN_DATABASE_URL` | Connection string de la branch `main` de Neon | Workflow de despliegue en cada push a `main` *(pendiente)* |

---

## Estructura del repositorio

```
Momento_01_Tendencias/
├── README.md                    ← este archivo
├── pyproject.toml / uv.lock      ← proyecto Python (uv)
├── .env.example                  ← plantilla de credenciales (sin valores reales)
├── data/                         ← datos semilla (JSON), fuente de verdad de la muestra
├── scripts/
│   └── inyeccion_semilla.py      ← carga el estado base en Neon
├── sql_migrations/                🚧 migraciones Flyway (pendiente)
├── docs/
│   ├── dominio_de_negocio.md     ← descripción del dominio + diagrama ER
│   └── evidences/                ← capturas y evidencia de cada fase
└── .github/workflows/             🚧 pendiente
```
