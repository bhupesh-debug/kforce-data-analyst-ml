## Feature engineering for the daily-aggregate operational series.
##
## Features are deliberately interpretable -- a Data Analyst must be
## able to explain every input to a stakeholder. No black-box embeddings.
##
## Lag / rolling: lag_1/7/14/28 of the target, 7- and 28-day rolling
## mean/std, volume deviation from the 28-day rolling mean.
## Calendar: day_of_week, is_weekend, month, day-of-year sin/cos.
## Operational (same-day, known at forecast time for the driver model):
## staffing_ratio, backlog_ratio, avg handle time, uptime, FCR.

LAG_FEATURES <- c("lag_1", "lag_7", "lag_14", "lag_28",
                  "roll_mean_7", "roll_std_7", "roll_mean_28",
                  "vol_dev_28d")
CALENDAR_FEATURES <- c("day_of_week", "is_weekend", "month",
                       "doy_sin", "doy_cos")
OPERATIONAL_FEATURES <- c("staffing_ratio", "backlog_ratio",
  "avg_handle_time_min", "system_uptime_pct",
  "first_contact_resolution_pct", "tickets_received",
  "tickets_resolved", "csat_score")

add_calendar <- function(df) {
  df$day_of_week <- as.integer(format(df$date, "%u"))
  df$is_weekend <- as.integer(df$day_of_week >= 6)
  df$month <- as.integer(format(df$date, "%m"))
  doy <- as.integer(format(df$date, "%j"))
  df$doy_sin <- sin(2 * pi * doy / 365.25)
  df$doy_cos <- cos(2 * pi * doy / 365.25)
  df
}

shift <- function(x, n) c(rep(NA, n), head(x, -n))

roll_mean <- function(x, n) {
  out <- rep(NA_real_, length(x))
  cs <- c(0, cumsum(ifelse(is.na(x), 0, x)))
  cnt <- c(0, cumsum(!is.na(x)))
  for (i in seq_along(x)) {
    if (i > n) {
      out[i] <- (cs[i] - cs[i - n]) / (cnt[i] - cnt[i - n])
    }
  }
  out
}

roll_sd <- function(x, n) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    if (i > n) out[i] <- sd(x[(i - n):(i - 1)], na.rm = TRUE)
  }
  out
}

add_lags <- function(df, target) {
  df <- df[order(df$date), ]
  s <- df[[target]]
  df$lag_1 <- shift(s, 1)
  df$lag_7 <- shift(s, 7)
  df$lag_14 <- shift(s, 14)
  df$lag_28 <- shift(s, 28)
  df$roll_mean_7 <- roll_mean(shift(s, 1), 7)
  df$roll_std_7 <- roll_sd(shift(s, 1), 7)
  df$roll_mean_28 <- roll_mean(shift(s, 1), 28)
  vol <- df$tickets_received
  df$vol_dev_28d <- (vol - roll_mean(shift(vol, 1), 28)) /
    roll_mean(shift(vol, 1), 28)
  df
}

## Returns list(frame, features). Rows with NA lags (first 28 days)
## are dropped; the caller keeps the date column for splitting.
build_features <- function(daily, target, include_operational = TRUE) {
  df <- add_calendar(daily)
  df <- add_lags(df, target)
  feats <- c(LAG_FEATURES, CALENDAR_FEATURES)
  if (include_operational) {
    feats <- c(feats, setdiff(OPERATIONAL_FEATURES, target))
  }
  keep <- complete.cases(df[, c(feats, target)])
  list(frame = df[keep, ], features = feats)
}

anomaly_features <- function(health) {
  df <- health[order(health$date), ]
  df$rows_received_ratio <- df$rows_received / df$rows_expected
  df$missing_rate_lag1 <- shift(df$missing_rate_pct, 1)
  df$late_feed_lag1 <- shift(df$late_feed_minutes, 1)
  df$health_score <- df$missing_rate_pct + df$duplicate_rate_pct +
    df$null_rate_pct + df$late_feed_minutes / 30
  df <- df[complete.cases(df), ]
  rownames(df) <- NULL
  df
}

ANOMALY_FEATURES <- c("rows_received_ratio", "missing_rate_pct",
  "duplicate_rate_pct", "late_feed_minutes", "null_rate_pct",
  "missing_rate_lag1", "late_feed_lag1")
## NOTE: health_score is NOT in the feature set — it is a linear
## combination of the other features, so including it would make any
## covariance-based method singular. It is used only as the composite
## threshold in detect_anomalies().
