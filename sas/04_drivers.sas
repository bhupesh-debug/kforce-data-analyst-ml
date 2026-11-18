/* ================================================================
   Kforce Data Analyst ML project — SAS replication (04/04)
   04_drivers.sas — what drives SLA attainment? + channel benchmark
   Method: OLS on same-day operational features with standardised
   coefficients (STB option) — the SAS analogue of the R permutation
   importance ranking. Same train/test split as R; coefficients are
   estimated on the training window only.
   Run after 01_data_prep.sas. Results: models/sas_drivers.csv,
   models/sas_channel_benchmark.csv
   ================================================================ */
%let root = %sysfunc(pathname(WORK));  /* override as needed */
%let proc = &root./data/processed;
%let models = &root./models;

proc import datafile="&proc./daily_aggregate.csv" out=daily
    dbms=csv replace;
    guessingrows=1000;
run;

/* --- Driver regression (training window only) ----------------------- */
proc reg data=daily(where=(test=0)) outest=reg_est noprint;
    model sla_attainment_pct = staffing_ratio backlog_ratio
        avg_handle_time_min system_uptime_pct
        first_contact_resolution_pct tickets_received csat_score / stb;
    output out=scored p=pred_sla;
run;
proc print data=reg_est; run;

/* --- Hold-out fit ---------------------------------------------------- */
proc corr data=scored(where=(test=1)) noprint
    outp=corr_out;
    var sla_attainment_pct pred_sla;
run;
proc print data=corr_out; run;

/* --- Standardised coefficients, ranked ------------------------------ */
proc transpose data=reg_est out=drivers_t;
    var staffing_ratio backlog_ratio avg_handle_time_min
        system_uptime_pct first_contact_resolution_pct
        tickets_received csat_score;
run;
data drivers;
    set drivers_t;
    rename _NAME_ = feature COL1 = std_beta;
    abs_beta = abs(std_beta);
run;
proc sort data=drivers; by descending abs_beta; run;
proc print data=drivers; run;
proc export data=drivers outfile="&models./sas_drivers.csv"
    dbms=csv replace;
run;

/* --- Channel benchmark ---------------------------------------------- */
proc import datafile="&proc./kpi_clean.csv" out=kpi dbms=csv replace;
    guessingrows=1000;
run;
proc sql;
    create table bench as
    select channel,
           mean(tickets_received) as avg_daily_tickets,
           mean(sla_attainment_pct) as sla_attainment_pct,
           mean(first_contact_resolution_pct)
               as first_contact_resolution_pct,
           mean(csat_score) as csat_score,
           mean(avg_handle_time_min) as avg_handle_time_min,
           mean(backlog_open) as avg_backlog,
           mean(sla_attainment_pct < 90) * 100 as sla_below_90_pct
    from kpi
    group by channel
    order by sla_attainment_pct desc;
quit;
proc print data=bench; run;
proc export data=bench outfile="&models./sas_channel_benchmark.csv"
    dbms=csv replace;
run;
