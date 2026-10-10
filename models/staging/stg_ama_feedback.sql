-- One feedback per answer: if a user rates the same answer again, the latest rating wins.
WITH source AS (

    SELECT *
    FROM {{ source('raw', 'raw_feedback_ama') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY created_at DESC, feedback_id) = 1

)

SELECT
      feedback_id
    , event_id
    , user_id
    , CASE
          WHEN thumbs IN (1, -1) THEN thumbs
      END                                     AS thumbs
    , thumbs NOT IN (1, -1)                   AS has_invalid_thumbs
    , thumbs = -1                             AS is_thumbs_down
    , reason_tag
    , free_text
    , created_at AT TIME ZONE 'UTC'           AS created_at_utc
FROM source
