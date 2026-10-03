-- Row counts
SELECT 'usage_events' AS t, COUNT(*) AS n FROM usage_events
UNION ALL SELECT 'model_pricing', COUNT(*) FROM model_pricing
UNION ALL SELECT 'provider_invoices', COUNT(*) FROM provider_invoices
UNION ALL SELECT 'finance_dashboard_daily', COUNT(*) FROM finance_dashboard_daily;

-- July totals: invoice and dashboard
SELECT 'july_invoice' AS what, ROUND(SUM(amount_usd),2) AS usd FROM provider_invoices WHERE billing_period_start = DATE '2026-07-01'
UNION ALL
SELECT 'july_dashboard', ROUND(SUM(cost_usd),2) FROM finance_dashboard_daily WHERE date_pt BETWEEN DATE '2026-07-01' AND DATE '2026-07-31';

-- Duplicate ids (expect event_id 0, request_id 2,509)
SELECT COUNT(*) - COUNT(DISTINCT event_id) AS dup_event_ids,
       COUNT(*) - COUNT(DISTINCT request_id) AS dup_request_ids
FROM usage_events;

-- Status mix
SELECT status, COUNT(*) AS n FROM usage_events GROUP BY 1;

-- Models and features in the logs (nimbus-large-0526 is not in model_pricing)
SELECT provider, model, feature, COUNT(*) AS n FROM usage_events GROUP BY 1,2,3 ORDER BY 1,2,3;

-- Ingestion lag
SELECT MEDIAN(ingested_ts - event_ts) AS med_lag, MAX(ingested_ts - event_ts) AS max_lag FROM usage_events;

-- Are duplicate request_ids identical copies? (expect 0)
SELECT COUNT(*) AS request_ids_with_differences FROM (
  SELECT request_id FROM usage_events GROUP BY 1
  HAVING COUNT(*) > 1 AND (COUNT(DISTINCT status) > 1
     OR COUNT(DISTINCT COALESCE(output_tokens,-1)) > 1
     OR COUNT(DISTINCT COALESCE(audio_seconds,-1)) > 1)
);
