-- Gold: cruza las DOS fuentes del proyecto en un solo modelo --
--   * Horario semanal por negocio -- semi-estructurado (Momento 2, Sesión 5:
--     External/Internal Stage + VARIANT + LATERAL FLATTEN -- stg_business_hours).
--   * Reseñas -- relacional (Momento 1: Neon -> Flyway -> Snowflake RAW -- stg_review).
--
-- Pregunta de negocio: ¿los negocios con más horas de atención a la semana reciben más
-- reseñas, o mejor calificación promedio? Es la pregunta que motivó traer el horario a
-- Snowflake en primer lugar -- sin este modelo, el JSON aplanado de la Sesión 5 se queda
-- en un dato sin explotar.
--
-- Grano: un negocio por fila -- solo los que reportan horario (154 de 308). El join con
-- horario_semanal es INNER a propósito: el análisis no tiene sentido para un negocio sin
-- horario reportado, así que no se rellena con NULL.

with horario_por_dia as (
    select
        business_id,
        day_of_week,
        -- Formato explícito ('HH24:MI'): open_time/close_time llegan como '06:00', sin
        -- segundos -- no depender de que Snowflake adivine el formato por auto-detección.
        datediff('minute', to_time(open_time, 'HH24:MI'), to_time(close_time, 'HH24:MI')) as minutos_abierto
    from {{ ref('stg_business_hours') }}
),

horario_semanal as (
    select
        business_id,
        count(distinct day_of_week) as dias_abierto_semana,
        -- Un negocio que cierra pasada la medianoche (ej. abre 18:00, cierra 02:00) da un
        -- DATEDIFF negativo porque open_time/close_time se comparan como TIME del mismo
        -- día, sin cruce de fecha. 11 de 154 negocios caían en este caso (detectado por
        -- el test dbt_expectations de rango 0-168h) -- se corrige sumando 24h cuando la
        -- resta da negativo, en vez de descartar esos negocios del análisis.
        sum(
            case
                when minutos_abierto < 0 then minutos_abierto + 1440
                else minutos_abierto
            end
        ) / 60.0 as horas_abiertas_semana
    from horario_por_dia
    group by business_id
),

resenas_por_negocio as (
    select
        business_id,
        count(*)          as total_resenas,
        avg(stars)        as calificacion_promedio,
        max(review_date)  as fecha_ultima_resena
    from {{ ref('stg_review') }}
    group by business_id
)

select
    b.business_id,
    b.business_name,
    b.city,
    h.dias_abierto_semana,
    round(h.horas_abiertas_semana, 1)                    as horas_abiertas_semana,
    case
        when h.horas_abiertas_semana >= 60 then 'Extendido (60+ h/semana)'
        when h.horas_abiertas_semana >= 40 then 'Estándar (40-59 h/semana)'
        else 'Reducido (<40 h/semana)'
    end                                                   as horario_tier,
    coalesce(r.total_resenas, 0)                          as total_resenas,
    round(r.calificacion_promedio, 2)                     as calificacion_promedio,
    r.fecha_ultima_resena
from horario_semanal h
inner join {{ ref('stg_business') }} b
    on h.business_id = b.business_id
left join resenas_por_negocio r
    on h.business_id = r.business_id
