-- Every thumbs down is in exactly one reason column (including "other" and "missing"),
-- so a PM summing the reasons always gets back to the total.

SELECT
      module
    , event_week
    , thumbs_down
    , reason_wrong_answer + reason_hallucination + reason_incomplete
      + reason_slow + reason_other + reason_missing AS reasons_total
FROM {{ ref('mart_ama_module_weekly') }}
WHERE thumbs_down <> reason_wrong_answer + reason_hallucination + reason_incomplete
                     + reason_slow + reason_other + reason_missing
