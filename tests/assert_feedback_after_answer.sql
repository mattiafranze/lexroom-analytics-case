-- Feedback cannot be given before the answer exists. If this fails, timestamps from the
-- two Pub/Sub topics are out of sync and every weekly attribution of feedback is suspect.

SELECT
      f.feedback_id
    , f.created_at_utc  AS feedback_at
    , e.created_at_utc  AS answer_at
FROM {{ ref('stg_ama_feedback') }} AS f
INNER JOIN {{ ref('stg_ama_events') }} AS e
    ON e.event_id = f.event_id
WHERE f.created_at_utc < e.created_at_utc
