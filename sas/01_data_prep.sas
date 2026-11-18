/* ================================================================
   Kforce Data Analyst ML project — SAS replication (01/04)
   01_data_prep.sas — load, validate, clean, aggregate, split
   Same data, same train/test split as the R reference implementation:
     train = 2024-01-01 .. 2025-10-31 (669 days)
     test  = 2025-11-01 .. 2025-12-30 (61 days)
   Run from the project root in SAS (9.4 M6+ or SAS Viya).
   Adjust the path macro if your working directory differs.
   ================================================================ */
%let root = %sysfunc(pathname(WORK));  /* override: %let root = /path/to/project; */
%let syn  = &root./data/synthetic;
%let proc = &root./data/processed;
%let models = &root./models;

options nocenter;

/* --- Load channel-level KPI data ---------------------------------- */
proc import datafile="&syn./kpi_daily.csv" out=kpi_raw
    dbms=csv replace;
    guessingrows=1000;
run;

data kpi;
    set kpi_raw;
    date2 = input(date, yymmdd10.);
    format date2 yymmdd10.;
    drop date;
    rename date2 = date;
run;

/* --- Validation: missing values, duplicates, ranges --------------- */
proc means data=kpi n nmiss min max;
    var tickets_received tickets_resolved backlog_open
        avg_handle_time_min first_contact_resolution_pct csat_score
        sla_attainment_pct staffing_hours system_uptime_pct;
run;
proc sort data=kpi out=kpi_sorted nodupkey;
    by channel date;
run;
data _null_;
    set kpi end=last;
    if sla_attainment_pct < 0 or sla_attainment_pct > 100 then
        put "ERROR: sla_attainment_pct out of range on " date;
    if first_contact_resolution_pct < 0 or
       first_contact_resolution_pct > 100 then
        put "ERROR: FCR out of range on " date;
    if csat_score < 1 or csat_score > 5 then
        put "ERROR: csat_score out of range on " date;
    if system_uptime_pct < 0 or system_uptime_pct > 100 then
        put "ERROR: uptime out of range on " date;
    if tickets_received < 0 then
        put "ERROR: negative tickets on " date;
run;

/* --- Aggregate to one row per day (forecasting grain) ------------- */
/* Volume-weighted SLA and FCR; sums for volumes; means elsewhere. */
proc sql;
    create table daily as
    select date,
           sum(tickets_received) as tickets_received,
           sum(tickets_resolved) as tickets_resolved,
           sum(backlog_open) as backlog_open,
           sum(staffing_hours) as staffing_hours,
           sum(tickets_received * sla_attainment_pct)
               / sum(tickets_received) as sla_attainment_pct,
           sum(tickets_received * first_contact_resolution_pct)
               / sum(tickets_received) as first_contact_resolution_pct,
           mean(avg_handle_time_min) as avg_handle_time_min,
           mean(csat_score) as csat_score,
           mean(system_uptime_pct) as system_uptime_pct
    from kpi_sorted
    group by date
    order by date;
quit;

data daily;
    set daily;
    staffing_ratio = staffing_hours / (tickets_received / 6.8);
    backlog_ratio  = backlog_open / tickets_received;
    test = (date >= '01NOV2025'd);
run;

proc export data=daily outfile="&proc./daily_aggregate.csv"
    dbms=csv replace;
run;
proc export data=kpi_sorted outfile="&proc./kpi_clean.csv"
    dbms=csv replace;
run;

/* --- Pipeline health log (same validation) ------------------------ */
proc import datafile="&syn./pipeline_health_daily.csv"
    out=health_raw dbms=csv replace;
    guessingrows=1000;
run;
data health;
    set health_raw;
    date2 = input(date, yymmdd10.);
    format date2 yymmdd10.;
    drop date;
    rename date2 = date;
run;
proc means data=health n nmiss min max;
    var rows_expected rows_received missing_rate_pct duplicate_rate_pct
        late_feed_minutes null_rate_pct;
run;
proc export data=health outfile="&proc./pipeline_health_clean.csv"
    dbms=csv replace;
run;
proc freq data=daily;
    tables test;
run;
