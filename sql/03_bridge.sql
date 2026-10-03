-- Bridge from the dashboard to the invoice, one change per column, ordered as listed.
-- Inferred dashboard rules: successes only, drops models with no price row, old 15 output price all month,
-- exact audio seconds, Pacific dates, no dedupe, onboarding_demo folded into summarization.
-- A = dashboard rules (6310.54, 0.05 off the real dashboard). G = the invoice (6860.56).
WITH b AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY request_id ORDER BY ingested_ts) AS rn,
    CAST(timezone('America/Los_Angeles', event_ts) AS DATE) AS pt_date,
    CASE WHEN model LIKE 'nimbus-large%' THEN 'nimbus-large' ELSE model END AS bm
  FROM usage_events
),
c AS (
  SELECT *,
    COALESCE(CASE WHEN provider='vox' THEN audio_seconds/60.0*0.006 END,0) AS vox_exact,
    COALESCE(CASE WHEN provider='vox' THEN CEIL(audio_seconds/15.0)*15/60.0*0.006 END,0) AS vox_round,
    COALESCE(CASE bm WHEN 'nimbus-large' THEN 3.0 WHEN 'nimbus-mini' THEN 0.15
                     WHEN 'nimbus-embed' THEN 0.02 END/1e6*input_tokens,0) AS in_cost,
    COALESCE(CASE bm WHEN 'nimbus-large' THEN 15.0 WHEN 'nimbus-mini' THEN 0.6 ELSE 0 END/1e6*output_tokens,0) AS out_cost,
    CASE WHEN bm='nimbus-large' AND event_ts >= TIMESTAMPTZ '2026-07-15 00:00:00+00'
         THEN 3.0/1e6*COALESCE(output_tokens,0) ELSE 0 END AS uplift,
    (pt_date BETWEEN DATE '2026-07-01' AND DATE '2026-07-31') AS pt_july,
    (event_ts >= TIMESTAMPTZ '2026-07-01 00:00:00+00'
     AND event_ts <  TIMESTAMPTZ '2026-08-01 00:00:00+00') AS utc_july
  FROM b
)
SELECT
 ROUND(SUM(vox_exact+in_cost+out_cost) FILTER (WHERE pt_july AND status='success' AND model<>'nimbus-large-0526'),2) AS A_dashboard_rules,
 ROUND(SUM(vox_exact+in_cost+out_cost) FILTER (WHERE pt_july AND status='success'),2) AS B_add_0526,
 ROUND(SUM(vox_exact+in_cost+out_cost+uplift) FILTER (WHERE pt_july AND status='success'),2) AS C_price_rise,
 ROUND(SUM(vox_exact+in_cost+out_cost+uplift) FILTER (WHERE pt_july AND status='success' AND rn=1),2) AS D_dedupe,
 ROUND(SUM(vox_exact+in_cost+out_cost+uplift) FILTER (WHERE pt_july AND status IN ('success','timeout') AND rn=1),2) AS E_add_timeouts,
 ROUND(SUM(vox_round+in_cost+out_cost+uplift) FILTER (WHERE pt_july AND status IN ('success','timeout') AND rn=1),2) AS F_vox_rounding,
 ROUND(SUM(vox_round+in_cost+out_cost+uplift) FILTER (WHERE utc_july AND status IN ('success','timeout') AND rn=1),2) AS G_utc_month
FROM c;
