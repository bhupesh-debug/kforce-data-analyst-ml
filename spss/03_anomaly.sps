* ================================================================
* Kforce Data Analyst ML project — SPSS replication (03/04)
* 03_anomaly.sps — data-quality anomaly detection
* Same rule as the R reference: standardise each pipeline-health
* feature (z-scores via DESCRIPTIVES /SAVE), flag a day when any
* |z| > 4 OR the composite health score is more than 4 SD above its
* mean. Ground truth is the injected incident label (is_anomaly),
* so precision / recall / F1 are measured via CROSSTABS.
* Run after 01_data_prep.sps.
* ================================================================.
GET FILE="data/processed/pipeline_health_clean.sav".
SORT CASES BY date.

* --- Features (same as R). ---.
COMPUTE rows_received_ratio = rows_received / rows_expected.
COMPUTE health_score = missing_rate_pct + duplicate_rate_pct
  + null_rate_pct + late_feed_minutes / 30.
EXECUTE.
CREATE missing_rate_lag1 = LAG(missing_rate_pct,1).
CREATE late_feed_lag1 = LAG(late_feed_minutes,1).
EXECUTE.
SELECT IF (NOT MISSING(missing_rate_lag1)).
EXECUTE.

* --- Z-scores. ---.
DESCRIPTIVES VARIABLES=rows_received_ratio missing_rate_pct
  duplicate_rate_pct late_feed_minutes null_rate_pct
  missing_rate_lag1 late_feed_lag1 health_score
  /SAVE
  /STATISTICS=MEAN STDDEV MIN MAX.
EXECUTE.

* --- Flag rule (thresholds computed from the data, not hard-coded). ---.
COMPUTE max_abs_z = MAX(ABS(Zrows_received_ratio),
  ABS(Zmissing_rate_pct), ABS(Zduplicate_rate_pct),
  ABS(Zlate_feed_minutes), ABS(Znull_rate_pct),
  ABS(Zmissing_rate_lag1), ABS(Zlate_feed_lag1)).
EXECUTE.
AGGREGATE
  /OUTFILE="models/spss_health_threshold.sav"
  /BREAK=
  /hs_mean hs_sd = MEAN(health_score) SD(health_score).
MATCH FILES /FILE=* /TABLE="models/spss_health_threshold.sav" /BY.
EXECUTE.
COMPUTE flag = (max_abs_z > 4) OR (health_score > hs_mean + 4 * hs_sd).
EXECUTE.
VARIABLE LABELS flag "Anomaly flag (1 = flagged)".
VALUE LABELS flag 0 "Normal" 1 "Flagged".
VALUE LABELS is_anomaly 0 "Normal" 1 "Injected incident".

* --- Confusion matrix vs injected ground truth. ---.
CROSSTABS
  /TABLES=is_anomaly BY flag
  /FORMAT=AVALUE TABLES
  /CELLS=COUNT ROW COLUMN TOTAL.
* Precision = TP / (TP + FP); Recall = TP / (TP + FN);
* F1 = 2 * P * R / (P + R). Read TP/FP/FN from the table above.
