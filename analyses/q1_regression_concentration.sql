-- Q1 (where the regression comes from): thumbs-down rate, last 4 weeks vs the 4 before, by segment.
-- Answers the question "is this platform-wide, or a few accounts?"

WITH reporting AS (

    SELECT *
    FROM {{ ref('int_ama_events_enriched') }}
    WHERE NOT is_after_as_of_date

)

, windowed AS (

    SELECT
          *
        , CASE
              WHEN event_week > (SELECT MAX(event_week) FROM reporting) - INTERVAL 4 WEEK THEN 'last_4w'
              ELSE 'previous_4w'
          END AS period
    FROM reporting
    WHERE event_week > (SELECT MAX(event_week) FROM reporting) - INTERVAL 8 WEEK

)

, segments AS (

    SELECT 'all workspaces' AS segment, * FROM windowed
    UNION ALL
    SELECT 'ws_0041 only', * FROM windowed WHERE workspace_id = 'ws_0041'
    UNION ALL
    SELECT 'all except ws_0041', * FROM windowed WHERE workspace_id <> 'ws_0041'
    UNION ALL
    SELECT 'enterprise except ws_0041', * FROM windowed WHERE plan = 'enterprise' AND workspace_id <> 'ws_0041'
    UNION ALL
    SELECT 'pro and free', * FROM windowed WHERE plan IN ('pro', 'free')

)

SELECT
      segment
    , COUNT(*) FILTER (WHERE period = 'previous_4w' AND is_rated)                   AS rated_previous_4w
    , COUNT(*) FILTER (WHERE period = 'last_4w' AND is_rated)                       AS rated_last_4w
    , ROUND(COUNT(*) FILTER (WHERE period = 'previous_4w' AND is_thumbs_down)
        / COUNT(*) FILTER (WHERE period = 'previous_4w' AND is_rated), 3)           AS thumbs_down_rate_previous_4w
    , ROUND(COUNT(*) FILTER (WHERE period = 'last_4w' AND is_thumbs_down)
        / COUNT(*) FILTER (WHERE period = 'last_4w' AND is_rated), 3)               AS thumbs_down_rate_last_4w
FROM segments
GROUP BY segment
ORDER BY rated_previous_4w DESC
