-- One row per AMA answer, with its feedback (if any) and workspace attributes.
-- Feedback is 1:1 with events after deduplication (enforced by a unique test on stg_ama_feedback.event_id).

WITH events AS (

    SELECT *
    FROM {{ ref('stg_ama_events') }}

)

, feedback AS (

    SELECT *
    FROM {{ ref('stg_ama_feedback') }}
    WHERE NOT has_invalid_thumbs

)

, workspaces AS (

    SELECT *
    FROM {{ ref('stg_workspaces') }}

)

SELECT
      e.event_id
    , e.user_id
    , e.workspace_id
    , w.workspace_id IS NULL                                        AS is_orphan_workspace
    , w.plan
    , w.country
    , e.event_date < w.signup_date                                  AS is_before_workspace_signup
    , e.module
    , e.event_date
    , e.event_week
    , e.event_date > DATE '{{ var("as_of_date") }}'                 AS is_after_as_of_date
    , e.is_cached
    , e.response_latency_ms
    , e.is_timeout
    , e.has_no_sources
    , f.feedback_id IS NOT NULL                                     AS is_rated
    , COALESCE(f.is_thumbs_down, FALSE)                             AS is_thumbs_down
    , f.reason_tag
    , NOT e.is_timeout
      AND NOT e.has_no_sources                                      AS is_technical_success
FROM events AS e
LEFT JOIN feedback AS f
    ON f.event_id = e.event_id
LEFT JOIN workspaces AS w
    ON w.workspace_id = e.workspace_id
