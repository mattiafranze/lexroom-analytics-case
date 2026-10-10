-- Every deduplicated answer must be counted exactly once in each weekly mart.
-- Protects against fan-out from the feedback join (an answer counted twice) and against
-- rows silently dropped by a filter. Either would move every rate Product and Leadership read.

WITH expected AS (

    SELECT COUNT(*) AS answers
    FROM {{ ref('stg_ama_events') }}

)

, actual AS (

    SELECT 'mart_ama_module_weekly' AS mart, SUM(answers) AS answers
    FROM {{ ref('mart_ama_module_weekly') }}

    UNION ALL

    SELECT 'mart_ama_quality_weekly' AS mart, SUM(answers) AS answers
    FROM {{ ref('mart_ama_quality_weekly') }}

)

SELECT
      a.mart
    , a.answers  AS actual_answers
    , e.answers  AS expected_answers
FROM actual AS a
CROSS JOIN expected AS e
WHERE a.answers <> e.answers
