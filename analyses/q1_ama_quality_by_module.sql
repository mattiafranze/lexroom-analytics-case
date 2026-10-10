-- Q1: weekly AMA quality per module, last 8 complete weeks up to as_of_date.
-- Most module-weeks have fewer than 30 ratings (is_low_sample): read the trend, not single weeks.

WITH reporting AS (

    SELECT *
    FROM {{ ref('mart_ama_module_weekly') }}
    WHERE NOT is_after_as_of_date

)

SELECT
      module
    , event_week
    , answers
    , rated_answers
    , ROUND(good_answer_rate, 3)  AS good_answer_rate
    , ROUND(thumbs_down_rate, 3)  AS thumbs_down_rate
    , is_low_sample
FROM reporting
WHERE event_week > (SELECT MAX(event_week) FROM reporting) - INTERVAL 8 WEEK
ORDER BY
      module
    , event_week
