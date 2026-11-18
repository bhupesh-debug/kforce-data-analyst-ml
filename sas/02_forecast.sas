/* ================================================================
   Kforce Data Analyst ML project — SAS replication (02/04)
   02_forecast.sas — SLA + ticket-volume forecasting
   Models (same targets, same 61-day hold-out as R):
     1. Seasonal naive (value 7 days earlier)
     2. Holt-Winters additive (PROC ESM, seasonal period 7)
     3. ARIMA (PROC ARIMA)
     4. Linear regression on lag + calendar features (PROC REG)
     5. Random forest (PROC FOREST — SAS 9.4 M6+ / Viya only.
        If unavailable, skip model 5 and note it in the table.)
   Metrics: MAE, RMSE, MAPE on the hold-out.
   Run after 01_data_prep.sas. Results: models/sas_metrics.csv
   ================================================================ */
%let root = %sysfunc(pathname(WORK));  /* override as needed */
%let proc = &root./data/processed;
%let models = &root./models;

proc import datafile="&proc./daily_aggregate.csv" out=daily
    dbms=csv replace;
    guessingrows=1000;
run;
proc sort data=daily; by date; run;

/* --- Lag features -------------------------------------------------- */
data feat;
    set daily;
    sla_l1  = lag1(sla_attainment_pct);
    sla_l7  = lag7(sla_attainment_pct);
    sla_l14 = lag14(sla_attainment_pct);
    sla_l28 = lag28(sla_attainment_pct);
    vol_l1  = lag1(tickets_received);
    vol_l7  = lag7(tickets_received);
    vol_l14 = lag14(tickets_received);
    vol_l28 = lag28(tickets_received);
    dow = weekday(date);
    is_weekend = (dow in (1, 7));
    month = month(date);
    doy = juldate(date) - juldate(mdy(1, 1, year(date))) + 1;
    doy_sin = sin(2 * constant('pi') * doy / 365.25);
    doy_cos = cos(2 * constant('pi') * doy / 365.25);
    /* 7-day rolling mean of lagged SLA */
    sla_ma7 = mean(lag1(sla_attainment_pct), lag2(sla_attainment_pct),
                   lag3(sla_attainment_pct), lag4(sla_attainment_pct),
                   lag5(sla_attainment_pct), lag6(sla_attainment_pct),
                   lag7(sla_attainment_pct));
    sla_ma28 = mean(lag1(sla_attainment_pct), lag7(sla_attainment_pct),
                    lag14(sla_attainment_pct),
                    lag28(sla_attainment_pct));
    vol_dev_28d = (tickets_received - sla_ma28) / sla_ma28;
    /* Seasonal naive: value 7 days earlier */
    pred_naive = lag7(sla_attainment_pct);
    train = (test = 0);
run;

/* --- Holt-Winters additive (PROC ESM) ------------------------------ */
proc esm data=feat(where=(train=1)) out=hw_out lead=61
    print=(forecasts);
    id date interval=day;
    forecast sla_attainment_pct / model=addwinters;
run;
/* hw_out holds the 61-step forecast; merge back on date */
proc sql;
    create table scored as
    select a.*, b.forecast as pred_hw
    from feat as a left join hw_out as b on a.date = b.date;
quit;

/* --- ARIMA(1,0,1) on the training window --------------------------- */
proc arima data=feat(where=(train=1));
    identify var=sla_attainment_pct;
    estimate p=1 q=1;
    forecast lead=61 out=arima_out;
run;
proc sql;
    create table scored as
    select a.*, b.forecast as pred_arima
    from scored as a left join arima_out as b on a.date = b.date;
quit;

/* --- Linear regression on lag + calendar features (train only) ----- */
proc reg data=scored(where=(train=1)) outest=reg_est noprint;
    model sla_attainment_pct = sla_l1 sla_l7 sla_l14 sla_l28
        sla_ma7 sla_ma28 dow is_weekend month doy_sin doy_cos
        vol_dev_28d;
    output out=scored2 p=pred_lm;
run;

/* --- Random forest (PROC FOREST; 9.4 M6+ / Viya) ------------------- */
%macro try_forest;
    %if %sysfunc(exist(scored2)) %then %do;
        proc forest data=scored2(where=(train=1))
            maxtrees=500 maxdepth=8;
            target sla_attainment_pct / level=interval;
            input sla_l1 sla_l7 sla_l14 sla_l28 sla_ma7 sla_ma28
                  dow is_weekend month doy_sin doy_cos vol_dev_28d
                  / level=interval;
            score data=scored2 out=scored3;
        run;
    %end;
%mend;
%try_forest;

/* --- Metrics on the hold-out --------------------------------------- */
data metrics;
    set scored2;
    where test = 1;
    err_naive = sla_attainment_pct - pred_naive;
    err_hw    = sla_attainment_pct - pred_hw;
    err_arima = sla_attainment_pct - pred_arima;
    err_lm    = sla_attainment_pct - pred_lm;
    %if %sysfunc(exist(scored3)) %then %do;
        err_rf = sla_attainment_pct - P_sla_attainment_pct;
    %end;
run;
proc sql;
    create table sas_metrics as
    select "seasonal_naive" as model length=20,
           mean(abs(err_naive)) as mae,
           sqrt(mean(err_naive**2)) as rmse,
           mean(abs(err_naive)/sla_attainment_pct)*100 as mape,
           count(*) as n
    from metrics
    union all
    select "holt_winters", mean(abs(err_hw)),
           sqrt(mean(err_hw**2)),
           mean(abs(err_hw)/sla_attainment_pct)*100, count(*)
    from metrics
    union all
    select "arima", mean(abs(err_arima)),
           sqrt(mean(err_arima**2)),
           mean(abs(err_arima)/sla_attainment_pct)*100, count(*)
    from metrics
    union all
    select "linear", mean(abs(err_lm)),
           sqrt(mean(err_lm**2)),
           mean(abs(err_lm)/sla_attainment_pct)*100, count(*)
    from metrics
    %if %sysfunc(exist(scored3)) %then %do;
    union all
    select "random_forest", mean(abs(err_rf)),
           sqrt(mean(err_rf**2)),
           mean(abs(err_rf)/sla_attainment_pct)*100, count(*)
    from metrics
    %end;
    ;
quit;
proc print data=sas_metrics; run;
proc export data=sas_metrics outfile="&models./sas_metrics.csv"
    dbms=csv replace;
run;
