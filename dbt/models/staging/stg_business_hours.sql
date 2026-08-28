select
    business_id,
    day_of_week,
    open_time,
    close_time
from {{ source('raw_json', 'stg_business_hours_flattened') }}
