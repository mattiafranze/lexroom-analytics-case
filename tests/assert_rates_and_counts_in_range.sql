-- Rates must be between 0 and 1 and counts must nest (thumbs down ≤ rated ≤ answers).
-- Catches broken denominators, integer division and filters applied to one side only.

SELECT 'mart_ama_module_weekly' AS mart, module AS key, event_week
FROM {{ ref('mart_ama_module_weekly') }}
WHERE NOT (thumbs_down <= rated_answers AND rated_answers <= answers)
   OR thumbs_down_rate NOT BETWEEN 0 AND 1
   OR good_answer_rate NOT BETWEEN 0 AND 1
   OR technical_success_rate NOT BETWEEN 0 AND 1

UNION ALL

SELECT 'mart_ama_quality_weekly', NULL, event_week
FROM {{ ref('mart_ama_quality_weekly') }}
WHERE rated_answers > answers
   OR thumbs_down_rate NOT BETWEEN 0 AND 1
   OR good_answer_rate NOT BETWEEN 0 AND 1
   OR technical_success_rate NOT BETWEEN 0 AND 1
   OR feedback_rate NOT BETWEEN 0 AND 1
