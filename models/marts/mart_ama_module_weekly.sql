-- One row per legal module per ISO week (Monday start, UTC).

WITH weekly AS (

    SELECT
          module
        , event_week
        , BOOL_OR(is_after_as_of_date)                                AS is_after_as_of_date
        , COUNT(*)                                                    AS answers
        , COUNT(*) FILTER (WHERE is_rated)                            AS rated_answers
        , COUNT(*) FILTER (WHERE is_thumbs_down)                      AS thumbs_down
        , COUNT(*) FILTER (WHERE is_technical_success) / COUNT(*)     AS technical_success_rate
        , COUNT(*) FILTER (WHERE is_thumbs_down AND is_technical_success)
            / NULLIF(COUNT(*) FILTER (WHERE is_rated AND is_technical_success), 0)
                                                                      AS thumbs_down_rate_successful
        , COUNT(*) FILTER (WHERE is_timeout) / COUNT(*)               AS timeout_rate
        , COUNT(*) FILTER (WHERE has_no_sources) / COUNT(*)           AS no_sources_rate
        , MEDIAN(response_latency_ms) FILTER (WHERE NOT is_cached
                                                AND NOT is_timeout)   AS median_latency_ms_uncached
        , COUNT(*) FILTER (WHERE reason_tag = 'wrong_answer')         AS reason_wrong_answer
        , COUNT(*) FILTER (WHERE reason_tag = 'hallucination')        AS reason_hallucination
        , COUNT(*) FILTER (WHERE reason_tag = 'incomplete')           AS reason_incomplete
        , COUNT(*) FILTER (WHERE reason_tag = 'slow')                 AS reason_slow
        , COUNT(*) FILTER (WHERE reason_tag = 'other')                AS reason_other
        , COUNT(*) FILTER (WHERE is_thumbs_down AND reason_tag IS NULL) AS reason_missing
    FROM {{ ref('int_ama_events_enriched') }}
    GROUP BY
          module
        , event_week

)

SELECT
      module
    , event_week
    , is_after_as_of_date
    , answers
    , rated_answers
    , thumbs_down
    , thumbs_down / NULLIF(rated_answers, 0)                          AS thumbs_down_rate
    , technical_success_rate * (1 - thumbs_down_rate_successful)      AS good_answer_rate
    , technical_success_rate
    , timeout_rate
    , no_sources_rate
    , median_latency_ms_uncached
    , reason_wrong_answer
    , reason_hallucination
    , reason_incomplete
    , reason_slow
    , reason_other
    , reason_missing
    , rated_answers < {{ var('min_rated_answers') }}                  AS is_low_sample
FROM weekly
