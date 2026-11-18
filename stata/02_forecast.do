* ================================================================
* Kforce Data Analyst ML project — STATA replication (02/04)
* 02_forecast.do — SLA + ticket-volume forecasting
* Models (same targets, same hold-out as R):
*   1. Seasonal naive (value 7 days earlier)
*   2. Holt-Winters additive (tssmooth hwinters, weekly seasonality)
*   3. ARIMA (arima, order chosen on the training window)
*   4. Linear regression on lag + calendar features
*   5. Random forest — OPTIONAL: requires the user-written `rforest`
*      package (ssc install rforest). If unavailable, skip model 5
*      and note it in the comparison table.
* Metrics: MAE, RMSE, MAPE on the 61-day hold-out.
* Run after 01_data_prep.do. Results saved to models/stata_metrics.csv
* ================================================================
clear all
set more off
global ROOT = "`c(pwd)'"
global PROC = "$ROOT/data/processed"
global MODELS = "$ROOT/models"
capture mkdir "$MODELS"

use "$PROC/daily_aggregate.dta", clear
tsset date

* --- Features: lags, rolling means, calendar --------------------------
foreach v in sla_attainment_pct tickets_received {
    gen `v'_l1  = L1.`v'
    gen `v'_l7  = L7.`v'
    gen `v'_l14 = L14.`v'
    gen `v'_l28 = L28.`v'
    gen `v'_ma7  = (L1.`v' + L2.`v' + L3.`v' + L4.`v' + ///
                   L5.`v' + L6.`v' + L7.`v') / 7
    gen `v'_ma28 = (L1.`v' + L7.`v' + L14.`v' + L28.`v') / 4
}
gen dow = dow(date)
gen is_weekend = (dow == 0 | dow == 6)
gen month = month(date)
gen doy = doy(date)
gen doy_sin = sin(2 * c(pi) * doy / 365.25)
gen doy_cos = cos(2 * c(pi) * doy / 365.25)
gen vol_dev_28d = (tickets_received - tickets_received_ma28) / ///
                  tickets_received_ma28

* --- Hold-out: last 61 days -------------------------------------------
gen train = (test == 0)

* --- Helper: metric computation ---------------------------------------
capture program drop mymetrics
program define mymetrics, rclass
    syntax varlist(min=2 max=2), GENerate(name)
    tempvar err abserr
    gen `err' = `1' - `2'
    gen `abserr' = abs(`err')
    quietly summarize `abserr'
    return scalar mae = r(mean)
    quietly summarize `err'
    return scalar rmse = sqrt(r(Var) + r(mean)^2)
    quietly summarize `abserr' if `1' != 0
    gen `generate' = `abserr' / abs(`1') * 100 if `1' != 0
    quietly summarize `generate'
    return scalar mape = r(mean)
    drop `err' `abserr'
end

* --- Target 1: SLA attainment -----------------------------------------
* Seasonal naive
gen pred_naive = L7.sla_attainment_pct
* Holt-Winters (additive, weekly seasonality), fit on train only
tssmooth hwinters hw_sla = sla_attainment_pct if train, ///
    parms(0.3 0.1 0.3) s(7) forecast(61)
* ARIMA(1,0,1) on the training window
arima sla_attainment_pct if train, arima(1,0,1)
predict pred_arima if test == 1, y
* Linear regression on lag + calendar features (train only)
regress sla_attainment_pct sla_attainment_pct_l1 ///
    sla_attainment_pct_l7 sla_attainment_pct_l14 ///
    sla_attainment_pct_l28 sla_attainment_pct_ma7 ///
    sla_attainment_pct_ma28 dow is_weekend month doy_sin doy_cos ///
    vol_dev_28d if train
predict pred_lm if test == 1

* Random forest (optional, user package)
capture which rforest
if _rc == 0 {
    rforest sla_attainment_pct sla_attainment_pct_l1 ///
        sla_attainment_pct_l7 sla_attainment_pct_l14 ///
        sla_attainment_pct_l28 sla_attainment_pct_ma7 ///
        sla_attainment_pct_ma28 dow is_weekend month doy_sin ///
        doy_cos vol_dev_28d if train, type(reg) ntree(500)
    predict pred_rf if test == 1
}
else {
    display "NOTE: rforest not installed — random forest skipped."
    display "Run: ssc install rforest"
}

* --- Metrics on the hold-out ------------------------------------------
tempfile res
postfile handle str20 model str20 target float(mae rmse mape n) ///
    using `res', replace
foreach m in naive hw_sla pred_arima pred_lm pred_rf {
    capture confirm variable `m'
    if _rc == 0 {
        quietly mymetrics sla_attainment_pct `m', generate(mape_tmp)
        post handle ("`m'") ("sla_attainment_pct") ///
            (r(mae)) (r(rmse)) (r(mape)) (61)
        drop mape_tmp
    }
}
postclose handle
use `res', clear
sort mape
list
export delimited using "$MODELS/stata_metrics.csv", replace
display "02_forecast.do complete: models/stata_metrics.csv"
