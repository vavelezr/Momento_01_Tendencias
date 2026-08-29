{% macro nivel_negocio(stars_column, review_count_column) %}
{#
    Porta a dbt la misma regla de negocio de R__fn_nivel_negocio.sql (Momento 1,
    función repetible sobre Neon) -- se reimplementa aquí como macro, no se reutiliza el
    SQL de Postgres, porque Snowflake es el motor de esta capa y una función de Postgres
    no es invocable desde un modelo dbt/Snowflake.
#}
    case
        when {{ review_count_column }} < 5 then 'Nuevo'
        when {{ stars_column }} >= 4.5 and {{ review_count_column }} >= 50 then 'Destacado'
        when {{ stars_column }} >= 4.0 and {{ review_count_column }} >= 10 then 'Recomendado'
        else 'Regular'
    end
{% endmacro %}
