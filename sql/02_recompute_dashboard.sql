-- Dashboard July by category
SELECT category, ROUND(SUM(cost_usd),2) AS usd
FROM finance_dashboard_daily
WHERE date_pt BETWEEN '2026-07-01' AND '2026-07-31'
GROUP BY ROLLUP(category) ORDER BY 1;

-- Dashboard June (control)
SELECT ROUND(SUM(cost_usd),2) AS dashboard_june
FROM finance_dashboard_daily
WHERE date_pt BETWEEN '2026-06-01' AND '2026-06-30';

-- Deduplicated view: first-ingested row per request_id
CREATE OR REPLACE TEMP VIEW ev AS
SELECT * FROM usage_events
QUALIFY ROW_NUMBER() OVER (PARTITION BY request_id ORDER BY ingested_ts) = 1;

-- Billed units under the invoice rules, July UTC. Compare with the invoice line items
WITH e AS (
  SELECT *, CASE WHEN model LIKE 'nimbus-large%' THEN 'nimbus-large' ELSE model END AS billed_model
  FROM ev
  WHERE event_ts >= TIMESTAMPTZ '2026-07-01 00:00:00+00'
    AND event_ts <  TIMESTAMPTZ '2026-08-01 00:00:00+00'
)
SELECT billed_model,
  SUM(CASE WHEN status IN ('success','timeout') THEN input_tokens END) AS in_succ_plus_timeout,
  SUM(CASE WHEN status = 'success' THEN input_tokens END)              AS in_success_only,
  SUM(CASE WHEN status = 'success' THEN output_tokens END)             AS out_success,
  ROUND(SUM(CASE WHEN status IN ('success','timeout')
                 THEN CEIL(audio_seconds/15.0)*15 END)/60.0, 2)        AS vox_min_succ_timeout
FROM e GROUP BY 1 ORDER BY 1;

-- nimbus-large-0526: first and last seen (first seen Jul 10)
SELECT MIN(event_ts) AS first_seen, MAX(event_ts) AS last_seen,
       COUNT(*) AS n, COUNT(DISTINCT app_version) AS versions
FROM usage_events WHERE model = 'nimbus-large-0526';

-- Does the Jul 1-14 / Jul 15-31 output split match the invoice?
SELECT event_ts >= TIMESTAMPTZ '2026-07-15 00:00:00+00' AS from_jul15,
       SUM(output_tokens) AS out_tokens
FROM ev
WHERE model LIKE 'nimbus-large%' AND status = 'success'
  AND event_ts >= TIMESTAMPTZ '2026-07-01 00:00:00+00'
  AND event_ts <  TIMESTAMPTZ '2026-08-01 00:00:00+00'
GROUP BY 1 ORDER BY 1;

-- Why the dashboard is what it is: replica by feature under three status filters. The success_only column matches the dashboard
WITH b AS (
  SELECT *, CAST(timezone('America/Los_Angeles', event_ts) AS DATE) AS pt_date,
    CASE WHEN model LIKE 'nimbus-large%' THEN 'nimbus-large' ELSE model END AS bm
  FROM usage_events
),
c AS (
  SELECT *,
    COALESCE(CASE WHEN provider='vox' THEN audio_seconds/60.0*0.006 END,0)
    + COALESCE(CASE bm WHEN 'nimbus-large' THEN 3.0 WHEN 'nimbus-mini' THEN 0.15 WHEN 'nimbus-embed' THEN 0.02 END/1e6*input_tokens,0)
    + COALESCE(CASE bm WHEN 'nimbus-large' THEN 15.0 WHEN 'nimbus-mini' THEN 0.6 ELSE 0 END/1e6*output_tokens,0) AS cost
  FROM b WHERE pt_date BETWEEN DATE '2026-07-01' AND DATE '2026-07-31'
)
SELECT feature,
  ROUND(SUM(cost) FILTER (WHERE model<>'nimbus-large-0526'),2)                                         AS all_status,
  ROUND(SUM(cost) FILTER (WHERE model<>'nimbus-large-0526' AND status='success'),2)                    AS success_only,
  ROUND(SUM(cost) FILTER (WHERE model<>'nimbus-large-0526' AND status IN ('success','timeout')),2)      AS succ_timeout
FROM c GROUP BY ROLLUP(feature) ORDER BY 1;
