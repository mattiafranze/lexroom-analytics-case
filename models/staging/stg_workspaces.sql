SELECT
      workspace_id
    , COALESCE(country, 'unknown')    AS country
    , plan
    , firm_size_bucket
    , signup_date
FROM {{ source('raw', 'raw_workspaces') }}
