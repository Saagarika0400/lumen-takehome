# Lumen take-home: code

## Layout
```
sql/01_checks.sql               row counts, duplicates, status mix, models, ingestion lag
sql/02_recompute_dashboard.sql  dashboard by category, billed units vs invoice, dashboard rules
sql/03_bridge.sql               dashboard to invoice bridge, one change per column
sql/04_unit_economics.sql       cost view, categories, active users, cohorts, revenue, segments
sql/05_experiment.sql           onboarding_v2 setup checks, D1 and D7-13
TwinMind_Assessment_final.ipynb the same analysis with notes
```

## Run it
1. `pip install duckdb pandas scipy statsmodels`

The SQL files must run in one connection, because later files use views built earlier
(`ev`, `cost`, `expu`, `act`). `run_all.py` does that. If you run them by hand in the DuckDB
CLI, run `SET TimeZone='UTC';` first and keep one session open.

## Notes
- Every query was run first in the notebook. These files are copies of those queries.
- The bridge amounts depend on the order of the steps. They are ordered as listed in the file.
