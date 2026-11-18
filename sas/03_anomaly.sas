/* ================================================================
   Kforce Data Analyst ML project — SAS replication (03/04)
   03_anomaly.sas — data-quality anomaly detection
   Same rule as the R reference: standardise each pipeline-health
   feature (PROC STDIZE), flag a day when any |z| > 4 OR the composite
   health score is more than 4 SD above its mean. Ground truth is the
   injected incident label (is_anomaly), so precision / recall / F1
   are measured, not assumed.
   Run after 01_data_prep.sas. Results: models/sas_anomaly_metrics.csv
   ================================================================ */
%let root = %sysfunc(pathname(WORK));  /* override as needed */
%let proc = &root./data/processed;
%let models = &root./models;

proc import datafile="&proc./pipeline_health_clean.csv" out=health
    dbms=csv replace;
    guessingrows=1000;
run;
proc sort data=health; by date; run;

data feat;
    set health;
    rows_received_ratio = rows_received / rows_expected;
    health_score = missing_rate_pct + duplicate_rate_pct
                 + null_rate_pct + late_feed_minutes / 30;
    missing_rate_lag1 = lag1(missing_rate_pct);
    late_feed_lag1 = lag1(late_feed_minutes);
    if _n_ = 1 then delete;
run;

/* --- Z-scores ------------------------------------------------------- */
proc stdize data=feat out=feat_z method=std;
    var rows_received_ratio missing_rate_pct duplicate_rate_pct
        late_feed_minutes null_rate_pct missing_rate_lag1
        late_feed_lag1;
run;

/* --- Flag rule ------------------------------------------------------ */
proc means data=feat noprint;
    var health_score;
    output out=hs_stats mean=hs_mean std=hs_sd;
run;
data flagged;
    if _n_ = 1 then set hs_stats;
    set feat_z;
    max_abs_z = max(abs(rows_received_ratio), abs(missing_rate_pct),
                    abs(duplicate_rate_pct), abs(late_feed_minutes),
                    abs(null_rate_pct), abs(missing_rate_lag1),
                    abs(late_feed_lag1));
    flag = (max_abs_z > 4) or
           (health_score > hs_mean + 4 * hs_sd);
run;

/* --- Confusion matrix vs injected ground truth ---------------------- */
proc freq data=flagged noprint;
    tables is_anomaly * flag / out=conf;
run;
proc sql noprint;
    select sum(count) into :tp from conf
        where is_anomaly = 1 and flag = 1;
    select sum(count) into :fp from conf
        where is_anomaly = 0 and flag = 1;
    select sum(count) into :fn from conf
        where is_anomaly = 1 and flag = 0;
    select sum(count) into :tn from conf
        where is_anomaly = 0 and flag = 0;
quit;
%let tp = &tp; %let fp = &fp; %let fn = &fn;
%let precision = %sysevalf(&tp / (&tp + &fp));
%let recall    = %sysevalf(&tp / (&tp + &fn));
%let f1 = %sysevalf(2 * &precision * &recall / (&precision + &recall));
%put NOTE: Anomaly detection (SAS): precision=&precision recall=&recall F1=&f1;
%put NOTE: Flagged=%eval(&tp + &fp) True incidents=%eval(&tp + &fn);

data sas_anomaly_metrics;
    precision = &precision; recall = &recall; f1 = &f1;
    n_flagged = &tp + &fp; n_true = &tp + &fn;
run;
proc export data=sas_anomaly_metrics
    outfile="&models./sas_anomaly_metrics.csv" dbms=csv replace;
run;
