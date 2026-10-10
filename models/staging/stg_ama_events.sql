WITH source AS (

    SELECT DISTINCT *
    FROM {{ source('raw', 'raw_events_ama') }}

)

SELECT
      event_id
    , user_id
    , workspace_id
    , CASE
          WHEN LOWER(TRIM(module_tag)) = 'civil' THEN 'civile'
          ELSE LOWER(TRIM(module_tag))
      END                                                   AS module
    , CASE
          WHEN response_latency_ms < 0 THEN NULL
          ELSE response_latency_ms
      END                                                   AS response_latency_ms
    , response_latency_ms < 0                               AS has_invalid_latency
    , response_latency_ms >= {{ var('timeout_latency_ms') }} AS is_timeout
    , response_tokens
    , retrieved_chunks
    , retrieved_chunks = 0                                  AS has_no_sources
    , is_cached
    , created_at AT TIME ZONE 'UTC'                         AS created_at_utc
    , CAST(created_at AT TIME ZONE 'UTC' AS DATE)           AS event_date
    , CAST(DATE_TRUNC('week', created_at AT TIME ZONE 'UTC') AS DATE) AS event_week
FROM source
