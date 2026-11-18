## Data pipeline: load, validate, clean, aggregate, time-split.
##
## This is the "monitor data quality and troubleshoot integrity issues"
## step: every load runs a validation suite and returns a data-quality
## report (missing values, duplicates, range violations, date gaps)
## before any modelling happens.
##
## Source as functions; run_all.R calls run_pipeline().

REQUIRED_KPI_COLS <- c("date", "channel", "tickets_received",
  "tickets_resolved", "backlog_open", "avg_handle_time_min",
  "first_contact_resolution_pct", "csat_score", "sla_attainment_pct",
  "staffing_hours", "system_uptime_pct")

REQUIRED_HEALTH_COLS <- c("date", "rows_expected", "rows_received",
  "missing_rate_pct", "duplicate_rate_pct", "late_feed_minutes",
  "null_rate_pct", "schema_drift_flag", "is_anomaly", "anomaly_type")

load_kpi <- function(path) {
  df <- read.csv(path, stringsAsFactors = FALSE)
  df$date <- as.Date(df$date)
  missing <- setdiff(REQUIRED_KPI_COLS, names(df))
  if (length(missing)) stop("kpi_daily missing columns: ",
                            paste(missing, collapse = ", "))
  df
}

load_health <- function(path) {
  df <- read.csv(path, stringsAsFactors = FALSE)
  df$date <- as.Date(df$date)
  missing <- setdiff(REQUIRED_HEALTH_COLS, names(df))
  if (length(missing)) stop("pipeline_health missing columns: ",
                            paste(missing, collapse = ", "))
  df
}

validate_frame <- function(df, name) {
  expected <- seq(min(df$date), max(df$date), by = "day")
  gaps <- length(setdiff(expected, unique(df$date)))
  violations <- list()
  checks <- list(
    sla_attainment_pct = c(0, 100),
    first_contact_resolution_pct = c(0, 100),
    csat_score = c(1, 5), system_uptime_pct = c(0, 100),
    tickets_received = c(0, Inf), missing_rate_pct = c(0, 100),
    duplicate_rate_pct = c(0, 100), null_rate_pct = c(0, 100))
  for (col in names(checks)) {
    if (col %in% names(df)) {
      lo <- checks[[col]][1]; hi <- checks[[col]][2]
      bad <- sum(df[[col]] < lo | df[[col]] > hi, na.rm = TRUE)
      if (bad > 0) violations[[col]] <- bad
    }
  }
  list(name = name, rows = nrow(df),
       missing_cells = sum(is.na(df)),
       duplicate_rows = sum(duplicated(df)),
       date_min = as.character(min(df$date)),
       date_max = as.character(max(df$date)),
       date_gaps = gaps, range_violations = violations)
}

clean_kpi <- function(df) {
  df <- df[order(df$channel, df$date), ]
  df <- df[!duplicated(df[, c("date", "channel")]), ]
  df$tickets_received <- pmax(df$tickets_received, 0)
  df$tickets_resolved <- pmax(df$tickets_resolved, 0)
  df$backlog_open <- pmax(df$backlog_open, 0)
  df$sla_attainment_pct <-
    pmin(pmax(df$sla_attainment_pct, 0), 100)
  df$first_contact_resolution_pct <-
    pmin(pmax(df$first_contact_resolution_pct, 0), 100)
  df$csat_score <- pmin(pmax(df$csat_score, 1), 5)
  df$system_uptime_pct <- pmin(pmax(df$system_uptime_pct, 0), 100)
  rownames(df) <- NULL
  df
}

aggregate_daily <- function(kpi) {
  # Volume-weighted SLA / FCR; sums for volumes; means elsewhere.
  agg <- aggregate(
    cbind(tickets_received, tickets_resolved, backlog_open,
          staffing_hours) ~ date, data = kpi, FUN = sum)
  means <- aggregate(
    cbind(avg_handle_time_min, csat_score, system_uptime_pct) ~ date,
    data = kpi, FUN = mean)
  agg <- merge(agg, means, by = "date")
  w_sla <- tapply(kpi$tickets_received * kpi$sla_attainment_pct,
                  kpi$date, sum)
  w_fcr <- tapply(kpi$tickets_received *
                    kpi$first_contact_resolution_pct, kpi$date, sum)
  agg$sla_attainment_pct <- as.numeric(w_sla) / agg$tickets_received
  agg$first_contact_resolution_pct <-
    as.numeric(w_fcr) / agg$tickets_received
  agg$staffing_ratio <- agg$staffing_hours / (agg$tickets_received / 6.8)
  agg$backlog_ratio <- agg$backlog_open / agg$tickets_received
  agg[order(agg$date), ]
}

time_split <- function(df, test_days = 61) {
  df <- df[order(df$date), ]
  cut <- nrow(df) - test_days
  list(train = df[seq_len(cut), ], test = df[(cut + 1):nrow(df), ])
}

run_pipeline <- function(synthetic_dir, processed_dir) {
  dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
  kpi <- load_kpi(file.path(synthetic_dir, "kpi_daily.csv"))
  health <- load_health(file.path(synthetic_dir,
                                  "pipeline_health_daily.csv"))
  reports <- list(kpi = validate_frame(kpi, "kpi_daily"),
                  health = validate_frame(health, "pipeline_health"))
  kpi_clean <- clean_kpi(kpi)
  daily <- aggregate_daily(kpi_clean)
  write.csv(kpi_clean, file.path(processed_dir, "kpi_clean.csv"),
            row.names = FALSE)
  write.csv(daily, file.path(processed_dir, "daily_aggregate.csv"),
            row.names = FALSE)
  write.csv(health, file.path(processed_dir,
                              "pipeline_health_clean.csv"),
            row.names = FALSE)
  list(kpi = kpi_clean, daily = daily, health = health,
       quality_reports = reports)
}
