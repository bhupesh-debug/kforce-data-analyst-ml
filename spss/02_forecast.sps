* ================================================================
* Kforce Data Analyst ML project — SPSS replication (02/04)
* 02_forecast.sps — SLA + ticket-volume forecasting
* Models (same targets, same 61-day hold-out as R):
*   1. Seasonal naive (value 7 days earlier)
*   2. Holt-Winters additive (EXSMOOTH)
*   3. Linear regression on lag + calendar features (REGRESSION)
* Metrics: MAE, RMSE, MAPE on the hold-out.
* Note: SPSS has no built-in random forest / gradient boosting in
* base Statistics. The tree-based models are therefore the R-only
* part of the comparison; the linear + smoothing models are the
* cross-tool check. Run after 01_data_prep.sps.
* ================================================================.
GET FILE="data/processed/daily_aggregate.sav".
SORT CASES BY date.

* --- Lag features (CREATE in TIME SERIES). ---.
CREATE sla_l1 = LAG(sla_attainment_pct,1).
CREATE sla_l7 = LAG(sla_attainment_pct,7).
CREATE sla_l14 = LAG(sla_attainment_pct,14).
CREATE sla_l28 = LAG(sla_attainment_pct,28).
CREATE vol_l1 = LAG(tickets_received,1).
CREATE vol_l7 = LAG(tickets_received,7).
CREATE vol_l14 = LAG(tickets_received,14).
CREATE vol_l28 = LAG(tickets_received,28).
* 7-day rolling mean of lagged SLA (MA function in TIME SERIES).
CREATE sla_ma7 = MA(sla_attainment_pct,7,1).
CREATE sla_ma28 = MA(sla_attainment_pct,28,1).
* Calendar features.
COMPUTE dow = XDATE.WEEKDAY(date).
COMPUTE is_weekend = (dow = 1 OR dow = 7).
COMPUTE month = XDATE.MONTH(date).
COMPUTE doy = XDATE.JDAY(date).
COMPUTE doy_sin = SIN(2 * 3.14159265 * doy / 365.25).
COMPUTE doy_cos = COS(2 * 3.14159265 * doy / 365.25).
COMPUTE vol_dev_28d = (tickets_received - sla_ma28) / sla_ma28.
EXECUTE.

* --- Seasonal naive: forecast = value 7 days earlier. ---.
COMPUTE pred_naive = sla_l7.
EXECUTE.

* --- Holt-Winters additive (weekly seasonality). ---.
* EXSMOOTH writes forecasts to the active file; fit on train only.
TEMPORARY.
SELECT IF (test = 0).
EXSMOOTH
  /VARIABLES = sla_attainment_pct
  /MODEL = WINTERS
  /PERIOD = 7
  /FORECAST = 61.
EXECUTE.
* The forecast values are stored in the new variable FIT_1 / ERR_1.
* Rename for the metric step.
RENAME VARIABLES (FIT_1 = pred_hw).
EXECUTE.

* --- Linear regression on lag + calendar features (train only). ---.
TEMPORARY.
SELECT IF (test = 0).
REGRESSION
  /MISSING LISTWISE
  /STATISTICS COEFF OUTS R ANOVA
  /DEPENDENT sla_attainment_pct
  /METHOD=ENTER sla_l1 sla_l7 sla_l14 sla_l28 sla_ma7 sla_ma28
   dow is_weekend month doy_sin doy_cos vol_dev_28d
  /SAVE PRED(pred_lm).
EXECUTE.

* --- Metrics on the hold-out (test = 1). ---.
TEMPORARY.
SELECT IF (test = 1).
COMPUTE err_naive = sla_attainment_pct - pred_naive.
COMPUTE err_hw = sla_attainment_pct - pred_hw.
COMPUTE err_lm = sla_attainment_pct - pred_lm.
COMPUTE ape_naive = ABS(err_naive) / sla_attainment_pct * 100.
COMPUTE ape_hw = ABS(err_hw) / sla_attainment_pct * 100.
COMPUTE ape_lm = ABS(err_lm) / sla_attainment_pct * 100.
EXECUTE.
TEMPORARY.
SELECT IF (test = 1).
DESCRIPTIVES VARIABLES=err_naive err_hw err_lm ape_naive ape_hw ape_lm
  /STATISTICS=MEAN STDDEV MIN MAX.
* RMSE = SQRT(MEAN(err^2)); compute via AGGREGATE for the record.
TEMPORARY.
SELECT IF (test = 1).
COMPUTE err2_naive = err_naive ** 2.
COMPUTE err2_hw = err_hw ** 2.
COMPUTE err2_lm = err_lm ** 2.
EXECUTE.
TEMPORARY.
SELECT IF (test = 1).
AGGREGATE
  /OUTFILE="models/spss_metrics.sav"
  /BREAK=test
  /rmse_naive rmse_hw rmse_lm = MEAN(err2_naive err2_hw err2_lm)
  /mape_naive mape_hw mape_lm = MEAN(ape_naive ape_hw ape_lm).
GET FILE="models/spss_metrics.sav".
COMPUTE rmse_naive = SQRT(rmse_naive).
COMPUTE rmse_hw = SQRT(rmse_hw).
COMPUTE rmse_lm = SQRT(rmse_lm).
EXECUTE.
LIST VARIABLES=rmse_naive rmse_hw rmse_lm mape_naive mape_hw mape_lm.
SAVE OUTFILE="models/spss_metrics.sav".
