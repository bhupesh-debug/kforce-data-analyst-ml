* ================================================================
* Kforce Data Analyst ML project — STATA replication (03/04)
* 03_anomaly.do — data-quality anomaly detection
* Same rule as the R reference: standardise each pipeline-health
* feature (z-scores), flag a day when any |z| > 4 OR the composite
* health score is more than 4 SD above its mean. Ground truth is the
* injected incident label (is_anomaly), so precision / recall / F1
* are measured, not assumed.
* Run after 01_data_prep.do. Results: models/stata_anomaly_metrics.csv
* ================================================================
clear all
set more off
global ROOT = "`c(pwd)'"
global PROC = "$ROOT/data/processed"
global MODELS = "$ROOT/models"
capture mkdir "$MODELS"

use "$PROC/pipeline_health_clean.dta", clear
sort date

* --- Features (same as R) ---------------------------------------------
gen rows_received_ratio = rows_received / rows_expected
gen missing_rate_lag1 = L1.missing_rate_pct
gen late_feed_lag1 = L1.late_feed_minutes
gen health_score = missing_rate_pct + duplicate_rate_pct + ///
                   null_rate_pct + late_feed_minutes / 30
drop if missing(missing_rate_lag1)   // first row has no lag

* --- Z-scores -----------------------------------------------------------
foreach v in rows_received_ratio missing_rate_pct duplicate_rate_pct ///
             late_feed_minutes null_rate_pct missing_rate_lag1 ///
             late_feed_lag1 health_score {
    egen z_`v' = std(`v')
}

* --- Flag rule ----------------------------------------------------------
egen max_abs_z = rowmax(abs(z_rows_received_ratio) ///
    abs(z_missing_rate_pct) abs(z_duplicate_rate_pct) ///
    abs(z_late_feed_minutes) abs(z_null_rate_pct) ///
    abs(z_missing_rate_lag1) abs(z_late_feed_lag1))
summarize health_score
gen flag = (max_abs_z > 4) | (health_score > r(mean) + 4 * r(sd))

* --- Confusion matrix vs injected ground truth -------------------------
gen tp = (flag == 1 & is_anomaly == 1)
gen fp = (flag == 1 & is_anomaly == 0)
gen fn = (flag == 0 & is_anomaly == 1)
gen tn = (flag == 0 & is_anomaly == 0)
quietly summarize tp
local TP = r(sum)
quietly summarize fp
local FP = r(sum)
quietly summarize fn
local FN = r(sum)
local precision = `TP' / (`TP' + `FP')
local recall    = `TP' / (`TP' + `FN')
local f1 = 2 * `precision' * `recall' / (`precision' + `recall')
display "Anomaly detection (STATA): precision " %5.3f `precision' ///
        " recall " %5.3f `recall' " F1 " %5.3f `f1'
display "Flagged: " `TP' + `FP' "  True incidents: " `TP' + `FN'

* --- Save metrics -------------------------------------------------------
clear
set obs 1
gen precision = `precision'
gen recall = `recall'
gen f1 = `f1'
gen n_flagged = `TP' + `FP'
gen n_true = `TP' + `FN'
export delimited using "$MODELS/stata_anomaly_metrics.csv", replace
display "03_anomaly.do complete: models/stata_anomaly_metrics.csv"
