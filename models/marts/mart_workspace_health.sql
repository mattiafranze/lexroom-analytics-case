-- One row per workspace, as of the as_of_date var (last day before the suspected truncated export).
-- Compares the last 28 days with the 28 days before. Workspaces with no activity in either window score 0.

WITH events AS (

    SELECT *
    FROM {{ ref('int_ama_events_enriched') }}
    WHERE NOT is_orphan_workspace

)

, as_of AS (

    SELECT DATE '{{ var("as_of_date") }}' AS as_of_date

)

, windows AS (

    SELECT
          e.*
        , CASE
              WHEN e.event_date > a.as_of_date      THEN NULL
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
        , COUNT(*) FILTER (WHERE period = 'previous' AND is_rated)                            AS rated_previous
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

-- Usage signals are relative to the platform trend: a workspace is flagged only if it fell
-- below half of the level the platform trend would predict. Same factor for answers and users.
-- Each signal needs a minimum volume in both periods to fire.
, signals AS (

    SELECT
          p.*
        , p.answers_previous >= 30
          AND p.answers_current < 0.5 * pl.answers_ratio * p.answers_previous             AS signal_usage_drop
        , p.active_users_previous >= 5
          AND p.active_users_current < 0.5 * pl.active_users_ratio * p.active_users_previous AS signal_users_drop
        , p.rated_previous >= 15
          AND p.rated_current >= 15
          AND p.thumbs_down_rate_current >= p.thumbs_down_rate_previous + 0.10            AS signal_quality_drop
        , p.answers_current >= 20
          AND p.failed_answer_rate_current >= 0.03                                         AS signal_failed_answers
    FROM periods AS p
    CROSS JOIN platform AS pl

)

, scored AS (

    SELECT
          w.workspace_id
        , w.country
        , w.plan
        , w.firm_size_bucket
        , w.signup_date
        , (SELECT as_of_date FROM as_of)                                AS as_of_date
        , COALESCE(s.answers_current, 0)                                AS answers_current
        , COALESCE(s.answers_previous, 0)                               AS answers_previous
        , COALESCE(s.active_users_current, 0)                           AS active_users_current
        , COALESCE(s.active_users_previous, 0)                          AS active_users_previous
        , COALESCE(s.rated_previous, 0)                                 AS rated_previous
        , COALESCE(s.rated_current, 0)                                  AS rated_current
        , s.thumbs_down_rate_previous
        , s.thumbs_down_rate_current
        , s.failed_answer_rate_current
        , COALESCE(s.signal_quality_drop, FALSE)                        AS signal_quality_drop
        , COALESCE(s.signal_usage_drop, FALSE)                          AS signal_usage_drop
        , COALESCE(s.signal_users_drop, FALSE)                          AS signal_users_drop
        , COALESCE(s.signal_failed_answers, FALSE)                      AS signal_failed_answers
    FROM {{ ref('stg_workspaces') }} AS w
    LEFT JOIN signals AS s
        ON s.workspace_id = w.workspace_id

)

SELECT
      *
    , 40 * signal_quality_drop::INT
      + 30 * signal_usage_drop::INT
      + 20 * signal_users_drop::INT
      + 10 * signal_failed_answers::INT                                 AS risk_score
    , CASE
          WHEN risk_score >= 40 THEN 'high'
          WHEN risk_score >= 20 THEN 'medium'
          ELSE 'low'
      END                                                               AS risk_level
FROM scored
