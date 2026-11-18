* ================================================================
* Kforce Data Analyst ML project — SPSS replication (04/04)
* 04_drivers.sps — what drives SLA attainment? + channel benchmark
* Method: OLS on same-day operational features with standardised
* coefficients (Beta) — the SPSS analogue of the R permutation
* importance ranking. Same train/test split as R; coefficients are
* estimated on the training window only.
* Run after 01_data_prep.sps.
* ================================================================.
GET FILE="data/processed/daily_aggregate.sav".

* --- Driver regression (training window only). ---.
TEMPORARY.
SELECT IF (test = 0).
REGRESSION
  /MISSING LISTWISE
  /STATISTICS COEFF OUTS R ANOVA COLLIN TOL
  /DEPENDENT sla_attainment_pct
  /METHOD=ENTER staffing_ratio backlog_ratio avg_handle_time_min
   system_uptime_pct first_contact_resolution_pct tickets_received
   csat_score
  /SAVE PRED(pred_sla).
EXECUTE.

* --- Hold-out fit. ---.
TEMPORARY.
SELECT IF (test = 1).
CORRELATIONS
  /VARIABLES=sla_attainment_pct pred_sla
  /PRINT=TWOTAIL NOSIG
  /MISSING=PAIRWISE.

* --- Channel benchmark. ---.
GET FILE="data/processed/kpi_clean.sav".
MEANS TABLES=sla_attainment_pct first_contact_resolution_pct
  csat_score avg_handle_time_min backlog_open tickets_received
  BY channel
  /CELLS=MEAN COUNT.
