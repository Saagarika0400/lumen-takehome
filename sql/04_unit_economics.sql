-- Cost basis view: invoice rules (dedupe, success and timeout, Vox rounded to 15s, Jul 15 output price, UTC)
CREATE OR REPLACE TEMP VIEW cost AS
SELECT request_id, user_id, feature, status, event_ts, input_tokens,
       CAST(event_ts AS DATE) AS d,
       COALESCE(CASE WHEN provider='vox' THEN CEIL(audio_seconds/15.0)*15/60.0*0.006 END,0)
     + COALESCE(CASE WHEN model LIKE 'nimbus-large%' THEN 3.0 WHEN model='nimbus-mini' THEN 0.15
                     WHEN model='nimbus-embed' THEN 0.02 END/1e6*input_tokens,0)
     + COALESCE(CASE WHEN model LIKE 'nimbus-large%' THEN 15.0 WHEN model='nimbus-mini' THEN 0.6 ELSE 0 END/1e6*output_tokens,0)
     + CASE WHEN model LIKE 'nimbus-large%' AND event_ts >= TIMESTAMPTZ '2026-07-15 00:00:00+00'
            THEN 3.0/1e6*COALESCE(output_tokens,0) ELSE 0 END AS usd
FROM usage_events
QUALIFY ROW_NUMBER() OVER (PARTITION BY request_id ORDER BY ingested_ts) = 1
   AND status IN ('success','timeout');

-- Check
SELECT ROUND(SUM(usd),2) AS july_cost FROM cost
WHERE event_ts >= TIMESTAMPTZ '2026-07-01 00:00:00+00' AND event_ts < TIMESTAMPTZ '2026-08-01 00:00:00+00';

-- July cost by category
SELECT feature, ROUND(SUM(usd),2) AS usd, ROUND(100*SUM(usd)/SUM(SUM(usd)) OVER (),1) AS pct
FROM cost WHERE d BETWEEN DATE '2026-07-01' AND DATE '2026-07-31'
GROUP BY 1 ORDER BY 2 DESC;

-- Daily active users and cost per active user
WITH dau AS (
  SELECT d, COUNT(DISTINCT user_id) AS dau FROM cost
  WHERE status='success' AND feature<>'onboarding_demo'
    AND d BETWEEN DATE '2026-07-01' AND DATE '2026-07-31'
  GROUP BY 1),
dc AS (
  SELECT d, SUM(usd) AS usd FROM cost
  WHERE d BETWEEN DATE '2026-07-01' AND DATE '2026-07-31' GROUP BY 1)
SELECT ROUND(AVG(dau),0) AS avg_dau,
       ROUND(SUM(usd)/SUM(dau),4) AS cost_per_dau_day,
       ROUND(AVG(usd/dau),4) AS avg_of_daily_ratios
FROM dau JOIN dc USING (d);

-- Cost per user, skew, top 1% share
WITH u AS (
  SELECT user_id, SUM(usd) AS usd FROM cost
  WHERE d BETWEEN DATE '2026-07-01' AND DATE '2026-07-31' AND user_id IS NOT NULL
  GROUP BY 1)
SELECT COUNT(*) AS users,
       ROUND(AVG(usd),3) AS mean_usd, ROUND(MEDIAN(usd),3) AS median_usd,
       ROUND(QUANTILE_CONT(usd,0.99),2) AS p99_usd,
       ROUND(100*SUM(usd) FILTER (WHERE usd >= (SELECT QUANTILE_CONT(usd,0.99) FROM u))/SUM(usd),1) AS top1pct_share
FROM u;

-- First-week cost per new user, June vs July cohorts
WITH n AS (
  SELECT user_id, account_created_ts AS t0,
    CASE WHEN account_created_ts >= TIMESTAMPTZ '2026-06-01 00:00:00+00' AND account_created_ts < TIMESTAMPTZ '2026-07-01 00:00:00+00' THEN 'June'
         WHEN account_created_ts >= TIMESTAMPTZ '2026-07-01 00:00:00+00' AND account_created_ts < TIMESTAMPTZ '2026-07-25 00:00:00+00' THEN 'July' END AS cohort
  FROM users),
w AS (
  SELECT n.cohort, n.user_id, COALESCE(SUM(c.usd),0) AS wk1
  FROM n LEFT JOIN cost c ON c.user_id=n.user_id AND c.event_ts >= n.t0 AND c.event_ts < n.t0 + INTERVAL 7 DAY
  WHERE n.cohort IS NOT NULL GROUP BY 1,2)
SELECT cohort, COUNT(*) AS new_users, ROUND(AVG(wk1),3) AS mean_wk1_cost,
       ROUND(MEDIAN(wk1),3) AS median_wk1_cost, ROUND(QUANTILE_CONT(wk1,0.95),3) AS p95
FROM w GROUP BY 1 ORDER BY 1;

-- Subscription events in July
SELECT event_type, product_id, store, COUNT(*) n,
       ROUND(SUM(price_usd),2) price, ROUND(SUM(proceeds_usd),2) proceeds
FROM subscription_events
WHERE event_ts >= TIMESTAMPTZ '2026-07-01 00:00:00+00' AND event_ts < TIMESTAMPTZ '2026-08-01 00:00:00+00'
GROUP BY 1,2,3 ORDER BY 1,2,3;

-- Net cash proceeds, July (net of refunds)
SELECT ROUND(SUM(proceeds_usd),2) AS net_proceeds,
       ROUND(SUM(proceeds_usd) FILTER (WHERE product_id='lumen_pro_monthly'),2) AS monthly_only
FROM subscription_events
WHERE event_ts >= TIMESTAMPTZ '2026-07-01 00:00:00+00' AND event_ts < TIMESTAMPTZ '2026-08-01 00:00:00+00';

-- Cost by user segment: paid, trial only, no subscription
WITH seg AS (
  SELECT user_id,
    MAX(CASE WHEN event_type IN ('trial_converted','renewal') THEN 1 ELSE 0 END) AS paid,
    MAX(CASE WHEN event_type = 'trial_started' THEN 1 ELSE 0 END) AS trialed
  FROM subscription_events WHERE event_ts < TIMESTAMPTZ '2026-08-01 00:00:00+00'
  GROUP BY 1),
u AS (
  SELECT user_id, SUM(usd) AS usd FROM cost
  WHERE d BETWEEN DATE '2026-07-01' AND DATE '2026-07-31' AND user_id IS NOT NULL GROUP BY 1)
SELECT CASE WHEN s.paid=1 THEN 'paid' WHEN s.trialed=1 THEN 'trial only' ELSE 'no subscription' END AS segment,
       COUNT(*) users, ROUND(SUM(u.usd),2) AS usd, ROUND(AVG(u.usd),3) AS avg_usd
FROM u LEFT JOIN seg s USING (user_id)
GROUP BY 1 ORDER BY 3 DESC;

-- Summarize input sizes (sizes the nimbus-mini idea)
SELECT CASE WHEN input_tokens < 2000 THEN 'a <2k'
            WHEN input_tokens < 5000 THEN 'b 2-5k'
            WHEN input_tokens < 10000 THEN 'c 5-10k'
            ELSE 'd 10k+' END AS bucket,
       COUNT(*) n, ROUND(SUM(usd),2) AS usd
FROM cost
WHERE feature='summarize' AND d BETWEEN DATE '2026-07-01' AND DATE '2026-07-31'
GROUP BY 1 ORDER BY 1;
