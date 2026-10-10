-- The grain of mart_ama_module_weekly is one row per module per week.

SELECT
      module
    , event_week
    , COUNT(*) AS rows_per_grain
FROM {{ ref('mart_ama_module_weekly') }}
GROUP BY
      module
    , event_week
HAVING COUNT(*) > 1
