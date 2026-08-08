# Dominio de negocio — Reseñas de negocios locales (Goodyear, AZ)

## 1. Descripción del dominio

El modelo representa una **plataforma de reseñas de negocios locales**, inspirada en el
caso real de Yelp: negocios que pueden pertenecer a varias categorías (restaurante,
tienda, servicio de salud...), publican su horario de atención, y reciben **reseñas**
(calificación + texto) y **tips** (recomendaciones cortas, sin calificación) de parte
de **usuarios** registrados. Además, cada negocio acumula un historial agregado de
**check-ins**: cuántas visitas se registraron en cada franja de hora/día de la semana,
útil para entender patrones de afluencia.

A diferencia de Parch & Posey (una empresa que vende *a* cuentas corporativas a través
de representantes de ventas), este dominio es de **consumo masivo**: miles de usuarios
individuales interactúan libremente con cientos de negocios, sin jerarquía de ventas ni
territorios. La pregunta de negocio típica no es "¿qué representante vendió más?", sino
cosas como "¿qué categoría de negocio tiene mejor calificación promedio?", "¿en qué
franja horaria hay más afluencia?" o "¿qué negocios tienen reseñas pero ningún tip, o
viceversa?".

Los datos son una **muestra real acotada** del [Yelp Academic Dataset]: todos los
negocios de **Goodyear, AZ** (un suburbio de Phoenix, ~308 negocios) y únicamente las
reseñas, tips, check-ins y usuarios asociados a esos negocios — no el dataset completo
(que pesa ~1.3 GB y excede el tier gratuito de Neon). El proceso de extracción vive en
[`scripts/extraer_muestra.py`](../scripts/extraer_muestra.py) y se documenta en el
[`README`](../README.md).

## 2. Diagrama entidad-relación

El diagrama refleja el esquema **final**, después de aplicar el baseline y todas las
migraciones evolutivas de `sql_migrations/`. Las tablas marcadas como *(migración)*
no existen en el baseline: las crea una migración `V__` posterior — ver el detalle en
la sección 3.

```mermaid
erDiagram
    CATEGORY ||--o{ BUSINESS_CATEGORY : clasifica
    BUSINESS ||--o{ BUSINESS_CATEGORY : pertenece_a
    BUSINESS ||--o{ BUSINESS_HOURS : abre_en
    BUSINESS ||--o{ REVIEW : recibe
    BUSINESS ||--o{ TIP : recibe
    BUSINESS ||--o{ CHECKIN : registra
    USERS ||--o{ REVIEW : escribe
    USERS ||--o{ TIP : escribe

    CATEGORY {
        int id PK
        text name
    }
    BUSINESS {
        text business_id PK
        text name
        text full_address
        text city
        text state
        numeric latitude
        numeric longitude
        numeric stars
        int review_count
        boolean is_open
        varchar primary_category "migración: columna nueva"
    }
    BUSINESS_CATEGORY {
        text business_id PK_FK
        int category_id PK_FK
    }
    BUSINESS_HOURS {
        int id PK
        text business_id FK
        text day_of_week
        time open_time
        time close_time
    }
    USERS {
        text user_id PK
        text name
        int review_count
        date yelping_since
        numeric average_stars
        int fans
    }
    REVIEW {
        text review_id PK
        text business_id FK
        text user_id FK
        smallint stars
        date review_date
        text text
        int votes_useful
        int votes_funny
        int votes_cool
    }
    TIP {
        int tip_id PK
        text business_id FK
        text user_id FK
        text tip_text
        date tip_date
        int likes
    }
    CHECKIN {
        int id PK
        text business_id FK
        smallint day_index
        smallint hour_of_day
        int checkin_count
    }
```

## 3. Qué existe desde el baseline y qué llega por migración

| Tabla | Origen | Detalle |
|---|---|---|
| `category` | Baseline | Catálogo de categorías (192 en la muestra) |
| `business` | Baseline | Negocios de Goodyear, AZ (308) |
| `business_category` | Baseline | Relación N:N negocio↔categoría (870 filas) |
| `users` | Baseline | Usuarios autores de al menos una reseña o tip (2 757) |
| `review` | Baseline | Reseñas de esos negocios (4 978) |
| `business_hours` | Migración `V__` (tabla nueva) | Horario semanal por negocio (1 026 filas) |
| `business.primary_category` | Migración `V__` (columna nueva) | Categoría principal denormalizada — nace con un error de diseño (`VARCHAR(15)`), corregido por roll forward. Ver `docs/evidencias/`. |
| `tip` | Migración `V__` (tabla nueva) | Recomendaciones cortas (2 239 filas) |
| `checkin` | Migración `V__` (tabla nueva) | Check-ins agregados por hora/día (8 635 filas) |
| Índice + restricción sobre `review`/`business` | Migración `V__` | Ver `sql_migrations/` |

Volumen total de la muestra: **21 005 filas en 8 tablas**, muy por debajo del límite de
0.5 GB del tier gratuito de Neon.

[Yelp Academic Dataset]: https://www.yelp.com/dataset
