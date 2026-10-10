-- Q2: workspaces at risk, for Customer Success.
-- Same score: larger accounts first, because they are the ones CS should call first.

SELECT
      workspace_id
    , plan
    , country
    , risk_level
    , risk_score
    , answers_previous
    , answers_current
    , active_users_previous
    , active_users_current
    , ROUND(thumbs_down_rate_previous, 2) AS thumbs_down_rate_previous
    , ROUND(thumbs_down_rate_current, 2)  AS thumbs_down_rate_current
    , signal_quality_drop
    , signal_usage_drop
    , signal_users_drop
    , signal_failed_answers
FROM {{ ref('mart_workspace_health') }}
WHERE risk_level <> 'low'
ORDER BY
      risk_score DESC
    , answers_previous DESC
