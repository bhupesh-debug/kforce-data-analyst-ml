* ================================================================
* Kforce Data Analyst ML project — STATA replication (01/04)
* 01_data_prep.do — load, validate, clean, aggregate, split
* Same data, same train/test split as the R reference implementation:
*   train = 2024-01-01 .. 2025-10-31 (669 days)
*   test  = 2025-11-01 .. 2025-12-30 (61 days)
* Run from the project root in Stata:
*   do stata/01_data_prep.do
* Requires: Stata 17+ (no user packages needed)
* ================================================================
clear all
set more off

global ROOT = "`c(pwd)'"
global SYN  = "$ROOT/data/synthetic"
global PROC = "$ROOT/data/processed"
capture mkdir "$PROC"

* --- Load channel-level KPI data -------------------------------------
import delimited "$SYN/kpi_daily.csv", clear varnames(1)
gen date2 = date(date, "YMD")
format date2 %td
drop date
rename date2 date
label variable date "Service date"

* --- Validation: missing values, duplicates, range violations --------
misstable summarize
duplicates report date channel
assert sla_attainment_pct >= 0 & sla_attainment_pct <= 100
assert first_contact_resolution_pct >= 0 & ///
       first_contact_resolution_pct <= 100
assert csat_score >= 1 & csat_score <= 5
assert system_uptime_pct >= 0 & system_uptime_pct <= 100
assert tickets_received >= 0

* --- Clean: sort, drop exact duplicates, clip ranges -----------------
sort channel date
duplicates drop date channel, force
replace sla_attainment_pct = 100 if sla_attainment_pct > 100
replace sla_attainment_pct = 0   if sla_attainment_pct < 0

* --- Aggregate to one row per day (forecasting grain) -----------------
* Volume-weighted SLA and FCR; sums for volumes; means elsewhere.
gen w_sla = tickets_received * sla_attainment_pct
gen w_fcr = tickets_received * first_contact_resolution_pct
collapse (sum) tickets_received tickets_resolved backlog_open ///
    staffing_hours w_sla w_fcr ///
    (mean) avg_handle_time_min csat_score system_uptime_pct, by(date)
gen sla_attainment_pct = w_sla / tickets_received
gen first_contact_resolution_pct = w_fcr / tickets_received
gen staffing_ratio = staffing_hours / (tickets_received / 6.8)
gen backlog_ratio  = backlog_open / tickets_received
drop w_sla w_fcr
sort date

* --- Time split flag --------------------------------------------------
gen test = (date >= td(01nov2025))
tab test

save "$PROC/daily_aggregate.dta", replace
save "$PROC/kpi_clean.dta", replace

* --- Pipeline health log (same validation) ----------------------------
import delimited "$SYN/pipeline_health_daily.csv", clear varnames(1)
gen date2 = date(date, "YMD")
format date2 %td
drop date
rename date2 date
misstable summarize
assert missing_rate_pct >= 0 & missing_rate_pct <= 100
save "$PROC/pipeline_health_clean.dta", replace

display "01_data_prep.do complete: daily_aggregate.dta + pipeline_health_clean.dta"
