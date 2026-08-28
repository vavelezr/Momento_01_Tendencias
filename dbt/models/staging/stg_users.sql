select
    user_id,
    name           as user_name,
    review_count,
    yelping_since,
    average_stars,
    fans,
    votes_useful,
    votes_funny,
    votes_cool
from {{ source('raw', 'users') }}
