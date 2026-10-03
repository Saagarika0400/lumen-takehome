-- Assignment counts
SELECT experiment, variant, COUNT(*) AS n_rows, COUNT(DISTINCT user_id) AS n_users
FROM experiment_assignments GROUP BY 1,2 ORDER BY 1,2;

-- Users assigned more than once (expect 0)
SELECT COUNT(*) AS users_with_multiple_rows FROM (
  SELECT user_id FROM experiment_assignments
  WHERE experiment='onboarding_v2' GROUP BY 1 HAVING COUNT(*)>1);

-- Base view: assignment joined to users, with an eligibility flag
CREATE OR REPLACE TEMP VIEW expu AS
SELECT a.user_id, a.variant, a.assigned_ts, u.account_created_ts AS t0,
       u.platform, u.country, (u.anon_id IS NOT NULL) AS had_anon,
       (u.user_id IS NOT NULL) AS in_users,
       (u.platform IN ('ios','android')
        AND u.account_created_ts >= TIMESTAMPTZ '2026-06-15 00:00:00+00'
        AND u.account_created_ts <  TIMESTAMPTZ '2026-07-16 00:00:00+00') AS eligible
FROM experiment_assignments a LEFT JOIN users u USING (user_id)
WHERE a.experiment='onboarding_v2';

-- Eligibility check
SELECT eligible, in_users, variant, COUNT(*) AS n
FROM expu GROUP BY 1,2,3 ORDER BY 1,2,3;

-- Balance by platform and had_anon
SELECT 'platform' AS dim, platform AS val, variant, COUNT(*) AS n FROM expu WHERE eligible GROUP BY 1,2,3
UNION ALL
SELECT 'had_anon', CAST(had_anon AS VARCHAR), variant, COUNT(*) FROM expu WHERE eligible GROUP BY 1,2,3
ORDER BY 1,2,3;

-- Gap between account creation and assignment
SELECT variant,
       ROUND(MEDIAN(EPOCH(assigned_ts - t0)),0) AS median_gap_sec,
       ROUND(MAX(ABS(EPOCH(assigned_ts - t0))),0) AS max_abs_gap_sec
FROM expu WHERE eligible GROUP BY 1;

-- Activity view: day number after signup, clean = success and not demo
CREATE OR REPLACE TEMP VIEW act AS
SELECT x.user_id, x.variant, x.platform, x.had_anon,
  CAST(FLOOR(EPOCH(e.event_ts - x.t0)/86400) AS INT) AS day_n,
  (e.status='success' AND e.feature<>'onboarding_demo') AS clean
FROM expu x JOIN usage_events e ON e.user_id = x.user_id
WHERE x.eligible AND e.event_ts >= x.t0;

-- D1 and D7-13 with and without demo events
SELECT x.variant, COUNT(*) AS users,
  ROUND(100.0*AVG(CASE WHEN a.d1_any   THEN 1 ELSE 0 END),1) AS d1_pm_style_any_event,
  ROUND(100.0*AVG(CASE WHEN a.d1_clean THEN 1 ELSE 0 END),1) AS d1_clean,
  ROUND(100.0*AVG(CASE WHEN a.d713_any   THEN 1 ELSE 0 END),1) AS d7_13_any_event,
  ROUND(100.0*AVG(CASE WHEN a.d713_clean THEN 1 ELSE 0 END),1) AS d7_13_clean
FROM expu x LEFT JOIN (
  SELECT user_id,
    BOOL_OR(day_n=1) AS d1_any,
    BOOL_OR(day_n=1 AND clean) AS d1_clean,
    BOOL_OR(day_n BETWEEN 7 AND 13) AS d713_any,
    BOOL_OR(day_n BETWEEN 7 AND 13 AND clean) AS d713_clean
  FROM act GROUP BY 1) a USING (user_id)
WHERE x.eligible GROUP BY 1 ORDER BY 1;

-- Eligible users never assigned, by platform and app version
SELECT u.platform, u.app_version,
       COUNT(*) AS users_in_window,
       COUNT(a.user_id) AS assigned,
       COUNT(*) - COUNT(a.user_id) AS never_assigned
FROM users u LEFT JOIN experiment_assignments a
  ON a.user_id=u.user_id AND a.experiment='onboarding_v2'
WHERE u.platform IN ('ios','android')
  AND u.account_created_ts >= TIMESTAMPTZ '2026-06-15 00:00:00+00'
  AND u.account_created_ts <  TIMESTAMPTZ '2026-07-16 00:00:00+00'
GROUP BY 1,2 ORDER BY 1,2;

-- Demo cost per user (guardrail)
SELECT x.variant, COUNT(DISTINCT x.user_id) AS users,
       ROUND(SUM(c.usd),2) AS demo_usd,
       ROUND(SUM(c.usd)/COUNT(DISTINCT x.user_id),4) AS demo_usd_per_user
FROM expu x LEFT JOIN cost c
  ON c.user_id=x.user_id AND c.feature='onboarding_demo'
WHERE x.eligible GROUP BY 1;
