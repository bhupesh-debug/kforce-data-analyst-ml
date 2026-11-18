* ================================================================
* Kforce Data Analyst ML project — STATA replication (04/04)
* 04_drivers.do — what drives SLA attainment? + channel benchmark
* Method: OLS on same-day operational features with standardised
* coefficients (beta) — the STATA analogue of the R permutation
* importance ranking. Same train/test split as R; coefficients are
* estimated on the training window only.
* Run after 01_data_prep.do. Results: models/stata_drivers.csv,
* models/stata_channel_benchmark.csv
* ================================================================
clear all
set more off
global ROOT = "`c(pwd)'"
global PROC = "$ROOT/data/processed"
global MODELS = "$ROOT/models"
capture mkdir "$MODELS"

use "$PROC/daily_aggregate.dta", clear

* --- Driver regression (training window only) ---------------------------
regress sla_attainment_pct staffing_ratio backlog_ratio ///
    avg_handle_time_min system_uptime_pct ///
    first_contact_resolution_pct tickets_received csat_score ///
    if train, beta
estat vif
* Out-of-sample R-squared on the hold-out
predict pred_sla if test == 1
quietly correlate sla_attainment_pct pred_sla if test == 1
display "Hold-out correlation (actual vs predicted SLA): " %5.3f r(rho)
display "Hold-out R-squared: " %5.3f r(rho)^2

* --- Save standardised coefficients -------------------------------------
matrix b = e(b)
matrix col = e(b)
local vars staffing_ratio backlog_ratio avg_handle_time_min ///
    system_uptime_pct first_contact_resolution_pct ///
    tickets_received csat_score
clear
set obs 7
gen feature = ""
gen std_beta = .
local i = 1
foreach v of local vars {
    replace feature = "`v'" in `i'
    replace std_beta = b[1, `i'] in `i'
    local ++i
}
* Note: with the `beta` option, e(b) holds standardised coefficients
* (the constant is excluded from the list above).
gsort -std_beta
list
export delimited using "$MODELS/stata_drivers.csv", replace

* --- Channel benchmark ---------------------------------------------------
use "$PROC/kpi_clean.dta", clear
collapse (mean) sla_attainment_pct first_contact_resolution_pct ///
    csat_score avg_handle_time_min backlog_open ///
    (mean) avg_daily_tickets = tickets_received, by(channel)
gen sla_below_90_pct = .
sort sla_attainment_pct
gsort -sla_attainment_pct
list
export delimited using "$MODELS/stata_channel_benchmark.csv", replace
display "04_drivers.do complete."
