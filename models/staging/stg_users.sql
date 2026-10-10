SELECT
      user_id
    , workspace_id
    , role
    , created_at AT TIME ZONE 'UTC'    AS created_at_utc
    , is_deleted
FROM {{ source('raw', 'raw_users') }}
