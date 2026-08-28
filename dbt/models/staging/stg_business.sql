select
    business_id,
    name              as business_name,
    full_address,
    city,
    state,
    latitude,
    longitude,
    stars,
    review_count,
    is_open,
    primary_category
from {{ source('raw', 'business') }}
