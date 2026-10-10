-- One row per ISO week (Monday start, UTC): the AMA North Star and its components.

WITH weekly AS (

    SELECT
          event_week
        , COUNT(*)                                              AS answers
        , COUNT(*) FILTER (WHERE is_rated)                      AS rated_answers
        , COUNT(*) FILTER (WHERE is_technical_success) / COUNT(*) AS technical_success_rate
        , COUNT(*) FILTER (WHERE is_thumbs_down)
            / NULLIF(COUNT(*) FILTER (WHERE is_rated), 0)       AS thumbs_down_rate
        , COUNT(*) FILTER (WHERE is_timeout) / COUNT(*)         AS timeout_rate
        , COUNT(*) FILTER (WHERE has_no_sources) / COUNT(*)     AS no_sources_rate
    FROM {{ ref('int_ama_events_enriched') }}
    GROUP BY event_week

)

SELECT
      event_week
    , answers
    , rated_answers
    , technical_success_rate * (1 - thumbs_down_rate)           AS good_answer_rate
    , technical_success_rate
    , thumbs_down_rate
    , timeout_rate
    , no_sources_rate
    , rated_answers / answers                                   AS feedback_rate
    , rated_answers < {{ var('min_rated_answers') }}            AS is_low_sample
FROM weekly
