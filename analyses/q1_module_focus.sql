-- Q1 (focus): last 4 complete weeks vs the 4 before, per module, compared with the platform.
-- Ranked by thumbs down volume, because that is where a fix helps the most users.

WITH reporting AS (

    SELECT *
    FROM {{ ref('mart_ama_module_weekly') }}
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

, by_module AS (

    SELECT
          module
        , SUM(answers) FILTER (WHERE period = 'last_4w')                      AS answers_last_4w
        , SUM(rated_answers) FILTER (WHERE period = 'last_4w')                AS rated_last_4w
        , SUM(thumbs_down) FILTER (WHERE period = 'last_4w')                  AS thumbs_down_last_4w
        , SUM(thumbs_down) FILTER (WHERE period = 'last_4w')
            / SUM(rated_answers) FILTER (WHERE period = 'last_4w')            AS thumbs_down_rate_last_4w
        , SUM(thumbs_down) FILTER (WHERE period = 'previous_4w')
            / SUM(rated_answers) FILTER (WHERE period = 'previous_4w')        AS thumbs_down_rate_previous_4w
        , SUM(reason_wrong_answer + reason_hallucination) FILTER (WHERE period = 'last_4w')
            / SUM(thumbs_down) FILTER (WHERE period = 'last_4w')              AS share_wrong_or_hallucinated_last_4w
    FROM windowed
    GROUP BY module

    UNION ALL

    SELECT
          'ALL MODULES'
        , SUM(answers) FILTER (WHERE period = 'last_4w')
        , SUM(rated_answers) FILTER (WHERE period = 'last_4w')
        , SUM(thumbs_down) FILTER (WHERE period = 'last_4w')
        , SUM(thumbs_down) FILTER (WHERE period = 'last_4w')
            / SUM(rated_answers) FILTER (WHERE period = 'last_4w')
        , SUM(thumbs_down) FILTER (WHERE period = 'previous_4w')
            / SUM(rated_answers) FILTER (WHERE period = 'previous_4w')
        , SUM(reason_wrong_answer + reason_hallucination) FILTER (WHERE period = 'last_4w')
            / SUM(thumbs_down) FILTER (WHERE period = 'last_4w')
    FROM windowed

)

SELECT
      module
    , answers_last_4w
    , rated_last_4w
    , thumbs_down_last_4w
    , ROUND(thumbs_down_rate_previous_4w, 3)                          AS thumbs_down_rate_previous_4w
    , ROUND(thumbs_down_rate_last_4w, 3)                              AS thumbs_down_rate_last_4w
    , ROUND(thumbs_down_rate_last_4w - thumbs_down_rate_previous_4w, 3) AS change
    , ROUND(share_wrong_or_hallucinated_last_4w, 2)                   AS share_wrong_or_hallucinated_last_4w
FROM by_module
ORDER BY module = 'ALL MODULES' DESC, thumbs_down_last_4w DESC
