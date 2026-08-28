-- sentiment_label llegó por schema drift (Momento 2, Sesión 5) como NUMBER en Snowflake,
-- no VARCHAR como describe la migración original en Neon: se re-infirió al recargar con
-- write_pandas(auto_create_table=True) sobre datos que ya venían numéricos.
select
    review_id,
    business_id,
    user_id,
    stars,
    review_date,
    text            as review_text,
    votes_useful,
    votes_funny,
    votes_cool,
    sentiment_label
from {{ source('raw', 'review') }}
