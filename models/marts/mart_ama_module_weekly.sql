-- One row per legal module per ISO week (Monday start, UTC).

WITH weekly AS (

    SELECT
          module
        , event_week
        , COUNT(*)                                                    AS answers
        , COUNT(*) FILTER (WHERE is_rated)                            AS rated_answers
        , COUNT(*) FILTER (WHERE is_thumbs_down)                      AS thumbs_down
        , COUNT(*) FILTER (WHERE is_technical_success) / COUNT(*)     AS technical_success_rate
        , COUNT(*) FILTER (WHERE is_timeout) / COUNT(*)               AS timeout_rate
        , COUNT(*) FILTER (WHERE has_no_sources) / COUNT(*)           AS no_sources_rate
        , MEDIAN(response_latency_ms) FILTER (WHERE NOT is_cached
                                                AND NOT is_timeout)   AS median_latency_ms_uncached
        , COUNT(*) FILTER (WHERE reason_tag = 'wrong_answer')         AS reason_wrong_answer
        , COUNT(*) FILTER (WHERE reason_tag = 'hallucination')        AS reason_hallucination
        , COUNT(*) FILTER (WHERE reason_tag = 'incomplete')           AS reason_incomplete
        , COUNT(*) FILTER (WHERE reason_tag = 'slow')                 AS reason_slow
    FROM {{ ref('int_ama_events_enriched') }}
    GROUP BY
          module
        , event_week

)

SELECT
      *
    , thumbs_down / NULLIF(rated_answers, 0)                          AS thumbs_down_rate
    , technical_success_rate * (1 - thumbs_down / NULLIF(rated_answers, 0)) AS good_answer_rate
    , rated_answers < {{ var('min_rated_answers') }}                  AS is_low_sample
FROM weekly
