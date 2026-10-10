-- Q1: weekly AMA quality per module, last 8 complete weeks.

SELECT
      module
    , event_week
    , answers
    , rated_answers
    , ROUND(good_answer_rate, 3)  AS good_answer_rate
    , ROUND(thumbs_down_rate, 3)  AS thumbs_down_rate
    , reason_wrong_answer + reason_hallucination AS wrong_or_hallucinated
    , is_low_sample
FROM {{ ref('mart_ama_module_weekly') }}
WHERE event_week > (SELECT MAX(event_week) FROM {{ ref('mart_ama_module_weekly') }}) - INTERVAL 8 WEEK
ORDER BY
      module
    , event_week
