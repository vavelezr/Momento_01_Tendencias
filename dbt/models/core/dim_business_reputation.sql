-- Gold: un negocio por fila, con su reputación clasificada y cuántas categorías cubre.
-- Cruza stg_business (atributos + calificación denormalizada) con un conteo agregado
-- desde stg_business_category (relación N:N) -- no se limita a repetir stg_business tal
-- cual, que sería un modelo Gold "de relleno" sin agregar valor sobre Silver.
--
-- Pregunta de negocio: ¿qué negocios son de fiar, y cuántas categorías distintas cubren?
-- Un negocio "Destacado" que además opera en 3 categorías es un caso de negocio distinto
-- a uno "Destacado" enfocado en una sola.

with categorias_por_negocio as (
    select
        business_id,
        count(distinct category_id) as num_categorias
    from {{ ref('stg_business_category') }}
    group by business_id
)

select
    b.business_id,
    b.business_name,
    b.city,
    b.primary_category,
    b.stars,
    b.review_count,
    coalesce(c.num_categorias, 0)                    as num_categorias,
    coalesce(c.num_categorias, 0) > 1                as tiene_multiples_categorias,
    {{ nivel_negocio('b.stars', 'b.review_count') }}  as reputation_tier
from {{ ref('stg_business') }} b
left join categorias_por_negocio c
    on b.business_id = c.business_id
