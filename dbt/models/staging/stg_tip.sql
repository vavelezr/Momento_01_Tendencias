select
    tip_id,
    business_id,
    user_id,
    tip_text,
    tip_date,
    likes
from {{ source('raw', 'tip') }}
