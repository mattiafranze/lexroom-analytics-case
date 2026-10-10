-- One row per ISO week (Monday start, UTC): the AMA North Star and its components.

WITH weekly AS (

    SELECT
          event_week
        , BOOL_OR(is_after_as_of_date)                          AS is_after_as_of_date
        , COUNT(*)                                              AS answers
        , COUNT(*) FILTER (WHERE is_rated)                      AS rated_answers
        , COUNT(*) FILTER (WHERE is_technical_success) / COUNT(*) AS technical_success_rate
        , COUNT(*) FILTER (WHERE is_thumbs_down)
            / NULLIF(COUNT(*) FILTER (WHERE is_rated), 0)       AS thumbs_down_rate
        , COUNT(*) FILTER (WHERE is_thumbs_down AND is_technical_success)
            / NULLIF(COUNT(*) FILTER (WHERE is_rated AND is_technical_success), 0)
                                                                AS thumbs_down_rate_successful
        , COUNT(*) FILTER (WHERE is_timeout) / COUNT(*)         AS timeout_rate
        , COUNT(*) FILTER (WHERE has_no_sources) / COUNT(*)     AS no_sources_rate
    FROM {{ ref('int_ama_events_enriched') }}
    GROUP BY event_week

)

SELECT
      event_week
    , is_after_as_of_date
    , answers
    , rated_answers
    -- P(technically sound) × P(not rated down | technically sound)
    , technical_success_rate * (1 - thumbs_down_rate_successful) AS good_answer_rate
    , technical_success_rate
    , thumbs_down_rate
    , thumbs_down_rate_successful
    , timeout_rate
    , no_sources_rate
    , rated_answers / answers                                   AS feedback_rate
    , rated_answers < {{ var('min_rated_answers') }}            AS is_low_sample
FROM weekly
