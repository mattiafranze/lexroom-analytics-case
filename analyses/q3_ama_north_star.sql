-- Q3: AMA North Star, last 8 complete weeks.

SELECT
      event_week
    , answers
    , rated_answers
    , ROUND(good_answer_rate, 3)        AS good_answer_rate
    , ROUND(technical_success_rate, 3)  AS technical_success_rate
    , ROUND(thumbs_down_rate, 3)        AS thumbs_down_rate
    , is_low_sample
FROM {{ ref('mart_ama_quality_weekly') }}
WHERE event_week > (SELECT MAX(event_week) FROM {{ ref('mart_ama_quality_weekly') }}) - INTERVAL 8 WEEK
ORDER BY event_week
