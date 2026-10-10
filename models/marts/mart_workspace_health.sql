-- One row per workspace, as of the as_of_date var.
-- Compares the last 28 days with the 28 days before. Every signal is also computed one week
-- earlier (as_of_date - 7): a quality drop counts in full only if it shows in both, so a single
-- bad week does not move an account to the top of the CS list.

WITH events AS (

    SELECT *
    FROM {{ ref('int_ama_events_enriched') }}
    WHERE NOT is_orphan_workspace

)

, anchors AS (

    SELECT 'this_week' AS anchor, DATE '{{ var("as_of_date") }}'     AS as_of_date
    UNION ALL
    SELECT 'last_week' AS anchor, DATE '{{ var("as_of_date") }}' - 7 AS as_of_date

)

, windows AS (

    SELECT
          a.anchor
        , e.*
        , CASE
              WHEN e.event_date > a.as_of_date      THEN NULL
              WHEN e.event_date > a.as_of_date - 28 THEN 'current'
              WHEN e.event_date > a.as_of_date - 56 THEN 'previous'
          END AS period
    FROM events AS e
    CROSS JOIN anchors AS a

)

, periods AS (

    SELECT
          anchor
        , workspace_id
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
    GROUP BY
          anchor
        , workspace_id

)

, platform AS (

    SELECT
          anchor
        , SUM(answers_current) / SUM(answers_previous)                    AS answers_ratio
        , SUM(active_users_current) / SUM(active_users_previous)          AS active_users_ratio
    FROM periods
    GROUP BY anchor

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
    INNER JOIN platform AS pl
        ON pl.anchor = p.anchor

)

, this_week AS (

    SELECT *
    FROM signals
    WHERE anchor = 'this_week'

)

, last_week AS (

    SELECT *
    FROM signals
    WHERE anchor = 'last_week'

)

, scored AS (

    SELECT
          w.workspace_id
        , w.country
        , w.plan
        , w.firm_size_bucket
        , w.signup_date
        , DATE '{{ var("as_of_date") }}'                                AS as_of_date
        , COALESCE(t.answers_current, 0)                                AS answers_current
        , COALESCE(t.answers_previous, 0)                               AS answers_previous
        , COALESCE(t.active_users_current, 0)                           AS active_users_current
        , COALESCE(t.active_users_previous, 0)                          AS active_users_previous
        , COALESCE(t.rated_previous, 0)                                 AS rated_previous
        , COALESCE(t.rated_current, 0)                                  AS rated_current
        , t.thumbs_down_rate_previous
        , t.thumbs_down_rate_current
        , t.failed_answer_rate_current
        , COALESCE(t.rated_previous >= 15 AND t.rated_current >= 15, FALSE) AS has_enough_data
        , COALESCE(t.signal_quality_drop, FALSE)                        AS signal_quality_drop
        , COALESCE(t.signal_quality_drop AND l.signal_quality_drop, FALSE) AS is_quality_drop_confirmed
        , COALESCE(t.signal_usage_drop, FALSE)                          AS signal_usage_drop
        , COALESCE(t.signal_users_drop, FALSE)                          AS signal_users_drop
        , COALESCE(t.signal_failed_answers, FALSE)                      AS signal_failed_answers
    FROM {{ ref('stg_workspaces') }} AS w
    LEFT JOIN this_week AS t
        ON t.workspace_id = w.workspace_id
    LEFT JOIN last_week AS l
        ON l.workspace_id = w.workspace_id

)

SELECT
      *
    , CASE
          WHEN is_quality_drop_confirmed THEN 40
          WHEN signal_quality_drop       THEN 20
          ELSE 0
      END
      + 30 * signal_usage_drop::INT
      + 20 * signal_users_drop::INT
      + 10 * signal_failed_answers::INT                                 AS risk_score
    , CASE
          WHEN risk_score >= 40   THEN 'high'
          WHEN risk_score >= 20   THEN 'medium'
          WHEN has_enough_data    THEN 'low'
          ELSE 'not enough data'
      END                                                               AS risk_level
FROM scored
