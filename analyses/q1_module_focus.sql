-- Q1 (focus): last 4 weeks vs the 4 before, per module.
-- Ranked by thumbs down volume, because that is where a fix helps the most users.

WITH windowed AS (

    SELECT
          *
        , CASE
              WHEN event_week > (SELECT MAX(event_week) FROM {{ ref('mart_ama_module_weekly') }}) - INTERVAL 4 WEEK
                  THEN 'last_4w'
              ELSE 'previous_4w'
          END AS period
    FROM {{ ref('mart_ama_module_weekly') }}
    WHERE event_week > (SELECT MAX(event_week) FROM {{ ref('mart_ama_module_weekly') }}) - INTERVAL 8 WEEK

)

SELECT
      module
    , SUM(answers) FILTER (WHERE period = 'last_4w')                        AS answers_last_4w
    , SUM(thumbs_down) FILTER (WHERE period = 'last_4w')                    AS thumbs_down_last_4w
    , ROUND(SUM(thumbs_down) FILTER (WHERE period = 'last_4w')
        / SUM(rated_answers) FILTER (WHERE period = 'last_4w'), 3)          AS thumbs_down_rate_last_4w
    , ROUND(SUM(thumbs_down) FILTER (WHERE period = 'previous_4w')
        / SUM(rated_answers) FILTER (WHERE period = 'previous_4w'), 3)      AS thumbs_down_rate_previous_4w
    , SUM(reason_wrong_answer + reason_hallucination)
        FILTER (WHERE period = 'last_4w')                                   AS wrong_or_hallucinated_last_4w
    , SUM(reason_incomplete) FILTER (WHERE period = 'last_4w')              AS incomplete_last_4w
FROM windowed
GROUP BY module
ORDER BY thumbs_down_last_4w DESC
