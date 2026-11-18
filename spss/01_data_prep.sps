* ================================================================
* Kforce Data Analyst ML project — SPSS replication (01/04)
* 01_data_prep.sps — load, validate, clean, aggregate, split
* Same data, same train/test split as the R reference implementation:
*   train = 2024-01-01 .. 2025-10-31 (669 days)
*   test  = 2025-11-01 .. 2025-12-30 (61 days)
* Run from the project root. Adjust the FILE paths if your working
* directory differs. Requires SPSS Statistics 28+ (base only).
* ================================================================.
* --- Load channel-level KPI data. ---.
GET DATA /TYPE=TXT
  /FILE="data/synthetic/kpi_daily.csv"
  /ENCODING="UTF8"
  /DELIMITERS=","
  /QUALIFIER='"'
  /ARRANGEMENT=DELIMITED
  /FIRSTCASE=2
  /VARIABLES=
  date A10
  channel A20
  tickets_received F8.0
  tickets_resolved F8.0
  backlog_open F8.0
  avg_handle_time_min F8.2
  first_contact_resolution_pct F8.2
  csat_score F8.2
  sla_attainment_pct F8.2
  staffing_hours F8.1
  system_uptime_pct F8.2.
CACHE.
EXECUTE.
ALTER TYPE date (DATE10).
FORMATS date (DATE10).

* --- Validation: descriptives + range checks. ---.
DESCRIPTIVES VARIABLES=tickets_received tickets_resolved backlog_open
  avg_handle_time_min first_contact_resolution_pct csat_score
  sla_attainment_pct staffing_hours system_uptime_pct
  /STATISTICS=MEAN STDDEV MIN MAX.
FREQUENCIES VARIABLES=channel.
* Range assertions (any case listed is a data-quality failure).
SELECT IF (sla_attainment_pct >= 0 AND sla_attainment_pct <= 100
  AND first_contact_resolution_pct >= 0
  AND first_contact_resolution_pct <= 100
  AND csat_score >= 1 AND csat_score <= 5
  AND system_uptime_pct >= 0 AND system_uptime_pct <= 100
  AND tickets_received >= 0).
EXECUTE.

* --- Clean: sort and drop exact duplicates. ---.
SORT CASES BY channel date.
MATCH FILES /FILE=* /BY channel date /FIRST=keep_first.
SELECT IF (keep_first = 1).
EXECUTE.
DELETE VARIABLES keep_first.
SAVE OUTFILE="data/processed/kpi_clean.sav".

* --- Aggregate to one row per day (forecasting grain). ---.
* Volume-weighted SLA and FCR; sums for volumes; means elsewhere.
COMPUTE w_sla = tickets_received * sla_attainment_pct.
COMPUTE w_fcr = tickets_received * first_contact_resolution_pct.
EXECUTE.
AGGREGATE
  /OUTFILE="data/processed/daily_aggregate.sav"
  /BREAK=date
  /tickets_received tickets_resolved backlog_open staffing_hours
   w_sla w_fcr = SUM(tickets_received tickets_resolved backlog_open
   staffing_hours w_sla w_fcr)
  /avg_handle_time_min csat_score system_uptime_pct
   = MEAN(avg_handle_time_min csat_score system_uptime_pct).
GET FILE="data/processed/daily_aggregate.sav".
COMPUTE sla_attainment_pct = w_sla / tickets_received.
COMPUTE first_contact_resolution_pct = w_fcr / tickets_received.
COMPUTE staffing_ratio = staffing_hours / (tickets_received / 6.8).
COMPUTE backlog_ratio = backlog_open / tickets_received.
DELETE VARIABLES w_sla w_fcr.
* --- Time split flag (test = last 61 days). ---.
COMPUTE test = (date >= DATE.DMY(01,11,2025)).
EXECUTE.
FREQUENCIES VARIABLES=test.
SAVE OUTFILE="data/processed/daily_aggregate.sav".

* --- Pipeline health log (same validation). ---.
GET DATA /TYPE=TXT
  /FILE="data/synthetic/pipeline_health_daily.csv"
  /ENCODING="UTF8"
  /DELIMITERS=","
  /QUALIFIER='"'
  /ARRANGEMENT=DELIMITED
  /FIRSTCASE=2
  /VARIABLES=
  date A10
  rows_expected F8.0
  rows_received F8.0
  missing_rate_pct F8.2
  duplicate_rate_pct F8.2
  late_feed_minutes F8.1
  null_rate_pct F8.2
  schema_drift_flag F8.0
  is_anomaly F8.0
  anomaly_type A20.
CACHE.
EXECUTE.
ALTER TYPE date (DATE10).
FORMATS date (DATE10).
DESCRIPTIVES VARIABLES=rows_expected rows_received missing_rate_pct
  duplicate_rate_pct late_feed_minutes null_rate_pct
  /STATISTICS=MEAN STDDEV MIN MAX.
SAVE OUTFILE="data/processed/pipeline_health_clean.sav".
