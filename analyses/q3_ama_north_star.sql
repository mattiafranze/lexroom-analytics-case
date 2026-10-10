-- Q3: AMA North Star, last 8 complete weeks up to as_of_date.

WITH reporting AS (

    SELECT *
    FROM {{ ref('mart_ama_quality_weekly') }}
    WHERE NOT is_after_as_of_date

)

SELECT
      event_week
    , answers
    , rated_answers
    , ROUND(good_answer_rate, 3)              AS good_answer_rate
    , ROUND(technical_success_rate, 3)        AS technical_success_rate
    , ROUND(thumbs_down_rate_successful, 3)   AS thumbs_down_rate_successful
    , is_low_sample
FROM reporting
WHERE event_week > (SELECT MAX(event_week) FROM reporting) - INTERVAL 8 WEEK
ORDER BY event_week
