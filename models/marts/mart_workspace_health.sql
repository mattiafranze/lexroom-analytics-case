-- One row per workspace, as of the last day with data.
-- Compares the last 28 days with the 28 days before. Workspaces with no activity in either window score 0.

WITH events AS (

    SELECT *
    FROM {{ ref('int_ama_events_enriched') }}
    WHERE NOT is_orphan_workspace

)

, as_of AS (

    SELECT MAX(event_date) AS as_of_date
    FROM events

)

, windows AS (

    SELECT
          e.*
        , CASE
              WHEN e.event_date > a.as_of_date - 28 THEN 'current'
              WHEN e.event_date > a.as_of_date - 56 THEN 'previous'
          END AS period
    FROM events AS e
    CROSS JOIN as_of AS a

)

, periods AS (

    SELECT
          workspace_id
        , COUNT(*) FILTER (WHERE period = 'current')                                          AS answers_current
        , COUNT(*) FILTER (WHERE period = 'previous')                                         AS answers_previous
        , COUNT(DISTINCT user_id) FILTER (WHERE period = 'current')                           AS active_users_current
        , COUNT(DISTINCT user_id) FILTER (WHERE period = 'previous')                           AS active_users_previous
        , COUNT(*) FILTER (WHERE period = 'current' AND is_rated)                             AS rated_current
        , COUNT(*) FILTER (WHERE period = 'current' AND is_thumbs_down)
            / NULLIF(COUNT(*) FILTER (WHERE period = 'current' AND is_rated), 0)              AS thumbs_down_rate_current
        , COUNT(*) FILTER (WHERE period = 'previous' AND is_thumbs_down)
            / NULLIF(COUNT(*) FILTER (WHERE period = 'previous' AND is_rated), 0)             AS thumbs_down_rate_previous
        , COUNT(*) FILTER (WHERE period = 'current' AND (is_timeout OR has_no_sources))
            / NULLIF(COUNT(*) FILTER (WHERE period = 'current'), 0)                           AS failed_answer_rate_current
    FROM windows
    WHERE period IS NOT NULL
    GROUP BY workspace_id

)

, platform AS (

    SELECT
          SUM(answers_current) / SUM(answers_previous)                    AS answers_ratio
        , SUM(active_users_current) / SUM(active_users_previous)          AS active_users_ratio
    FROM periods

)

-- Usage signals are relative to the platform trend: a workspace is flagged only if it
-- declines clearly more than everyone else, so a platform-wide drop does not flag every account.
-- Each signal needs a minimum volume to fire.
, signals AS (

    SELECT
          p.*
        , p.answers_previous >= 10
          AND p.answers_current < 0.5 * pl.answers_ratio * p.answers_previous           AS signal_usage_drop
        , p.active_users_previous >= 3
          AND p.active_users_current < 0.7 * pl.active_users_ratio * p.active_users_previous AS signal_users_drop
        , p.rated_current >= 5
          AND p.thumbs_down_rate_current >= COALESCE(p.thumbs_down_rate_previous, 0) + 0.10 AS signal_quality_drop
        , p.answers_current >= 20
          AND p.failed_answer_rate_current >= 0.03                                       AS signal_failed_answers
    FROM periods AS p
    CROSS JOIN platform AS pl

)

SELECT
      w.workspace_id
    , w.country
    , w.plan
    , w.firm_size_bucket
    , (SELECT as_of_date FROM as_of)                                    AS as_of_date
    , COALESCE(s.answers_current, 0)                                    AS answers_current
    , COALESCE(s.answers_previous, 0)                                   AS answers_previous
    , COALESCE(s.active_users_current, 0)                               AS active_users_current
    , COALESCE(s.active_users_previous, 0)                              AS active_users_previous
    , s.thumbs_down_rate_current
    , s.thumbs_down_rate_previous
    , s.failed_answer_rate_current
    , COALESCE(s.signal_usage_drop, FALSE)                              AS signal_usage_drop
    , COALESCE(s.signal_users_drop, FALSE)                              AS signal_users_drop
    , COALESCE(s.signal_quality_drop, FALSE)                            AS signal_quality_drop
    , COALESCE(s.signal_failed_answers, FALSE)                          AS signal_failed_answers
    , 40 * COALESCE(s.signal_quality_drop, FALSE)::INT
      + 30 * COALESCE(s.signal_usage_drop, FALSE)::INT
      + 20 * COALESCE(s.signal_users_drop, FALSE)::INT
      + 10 * COALESCE(s.signal_failed_answers, FALSE)::INT              AS risk_score
    , CASE
          WHEN risk_score >= 40 THEN 'high'
          WHEN risk_score >= 20 THEN 'medium'
          ELSE 'low'
      END                                                               AS risk_level
FROM {{ ref('stg_workspaces') }} AS w
LEFT JOIN signals AS s
    ON s.workspace_id = w.workspace_id
