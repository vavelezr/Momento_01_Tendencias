select
    business_id,
    category_id
from {{ source('raw', 'business_category') }}
