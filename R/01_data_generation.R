## Synthetic operational / service-performance dataset (R implementation)
##
## Models a multi-channel service operation of the kind a Kforce Data
## Analyst supports: five service channels, daily ticket volumes,
## service KPIs, and a reporting-pipeline health log with injected
## data-quality incidents.
##
## ALL DATA IS SYNTHETIC (set.seed(42), fixed seed, reproducible).
## No real client, company, or personal data is used.
##
## Outputs (data/synthetic/):
##   kpi_daily.csv (one row per channel per day, 730 days x 5 channels)
##   pipeline_health_daily.csv (one row per day, 730 days)
##
## Run:  Rscript R/01_data_generation.R [out_dir]

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else "data/synthetic"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
set.seed(42)

N_DAYS <- 730L
START <- as.Date("2024-01-01")
CHANNELS <- c("Helpdesk", "Onboarding", "Billing Support",
              "Field Service", "Publishing Ops")

# base = mean tickets/day, trend = daily growth, aht = mean handle time
# (min), fcr = first-contact resolution, csat = mean CSAT (1-5),
# sla_base = channel baseline SLA (service complexity: Onboarding and
# Field Service run lower because the work is longer and less routine)
PROFILE <- list(
  "Helpdesk"        = list(base = 420, trend = 0.0006, aht = 9.5,  fcr = 0.74, csat = 4.2, sla_base = 97.5),
  "Onboarding"      = list(base = 150, trend = 0.0011, aht = 22.0, fcr = 0.68, csat = 4.4, sla_base = 94.0),
  "Billing Support" = list(base = 260, trend = 0.0004, aht = 12.0, fcr = 0.71, csat = 4.0, sla_base = 96.5),
  "Field Service"   = list(base = 190, trend = 0.0008, aht = 18.0, fcr = 0.66, csat = 4.3, sla_base = 95.0),
  "Publishing Ops"  = list(base = 110, trend = 0.0009, aht = 14.0, fcr = 0.70, csat = 4.1, sla_base = 95.5)
)

# Weekly seasonality (Mon..Sun): demand peaks midweek, collapses at weekends.
WEEKDAY_MULT <- c(1.18, 1.22, 1.20, 1.12, 1.02, 0.42, 0.30)

dates <- seq(START, by = "day", length.out = N_DAYS)
dow <- as.integer(format(dates, "%u"))          # 1 = Monday
doy <- as.integer(format(dates, "%j"))
seasonal <- 1 + 0.10 * sin(2 * pi * (doy - 300) / 365.25)

kpi <- do.call(rbind, lapply(CHANNELS, function(ch) {
  p <- PROFILE[[ch]]
  trend <- 1 + p$trend * (0:(N_DAYS - 1))
  lambda <- p$base * trend * WEEKDAY_MULT[dow] * seasonal
  received <- rpois(N_DAYS, lambda)
  # Resolution lags demand; backlog accumulates then clears.
  # Capacity averages ~1.5% above demand so backlog stays bounded
  # but visible (a capacity mean below demand would make backlog
  # explode and pin SLA at its floor — a generator bug caught in
  # testing; a mean far above demand would erase backlog entirely).
  resolved <- numeric(N_DAYS); backlog <- numeric(N_DAYS)
  carry <- 0
  for (i in seq_len(N_DAYS)) {
    capacity <- received[i] * runif(1, 0.95, 1.08)
    resolved[i] <- min(received[i] + carry, capacity)
    carry <- received[i] + carry - resolved[i]
    backlog[i] <- carry
  }
  staffing <- received / runif(N_DAYS, 6.0, 7.5) * runif(N_DAYS, 0.95, 1.05)
  uptime <- pmin(pmax(rnorm(N_DAYS, 99.4, 0.5), 96), 100)
  staffing_ratio <- staffing / pmax(received / 6.8, 1)
  backlog_ratio <- backlog / pmax(received, 1)
  # SLA attainment: driven by staffing coverage, backlog pressure,
  # handle time and uptime -- the driver structure Problem 3 exploits.
  # sla_base is the channel's service-complexity baseline.
  sla <- p$sla_base + 6.0 * (staffing_ratio - 1) - 14.0 * backlog_ratio -
    0.25 * (p$aht - 12) / 10 + 1.2 * (uptime - 99.4) + rnorm(N_DAYS, 0, 1.6)
  sla <- pmin(pmax(sla, 68), 99.5)
  aht <- pmin(pmax(rnorm(N_DAYS, p$aht, p$aht * 0.12) +
                     0.02 * backlog_ratio * 100, 3), 60)
  fcr <- pmin(pmax(rnorm(N_DAYS, p$fcr, 0.04) - 0.05 * backlog_ratio,
                   0.45), 0.92) * 100
  csat <- pmin(pmax(rnorm(N_DAYS, p$csat, 0.18) +
                      0.02 * (sla - 90) / 10, 1), 5)
  data.frame(
    date = dates, channel = ch,
    tickets_received = as.integer(received),
    tickets_resolved = as.integer(round(resolved)),
    backlog_open = as.integer(round(backlog)),
    avg_handle_time_min = round(aht, 2),
    first_contact_resolution_pct = round(fcr, 2),
    csat_score = round(csat, 2),
    sla_attainment_pct = round(sla, 2),
    staffing_hours = round(staffing, 1),
    system_uptime_pct = round(uptime, 2),
    stringsAsFactors = FALSE
  )
}))

## ---- Pipeline health: daily reporting-pipeline log -------------------
set.seed(43)
rows_expected <- sample(4800:5200, N_DAYS, replace = TRUE)
missing <- pmin(pmax(rnorm(N_DAYS, 0.4, 0.25), 0), 3)
duplicate <- pmin(pmax(rnorm(N_DAYS, 0.15, 0.10), 0), 2)
late <- pmin(pmax(rnorm(N_DAYS, 8, 6), 0), 60)
null_rate <- pmin(pmax(rnorm(N_DAYS, 0.3, 0.2), 0), 2.5)
drift <- integer(N_DAYS)
is_anomaly <- integer(N_DAYS)
anomaly_type <- rep("none", N_DAYS)

# Inject ~25 incidents: late feed, missing batch, duplicate load, null spike.
incident_days <- sample(30:(N_DAYS - 5), 25, replace = FALSE)
incident_kinds <- sample(c("late_feed", "missing_batch",
                           "duplicate_load", "null_spike"), 25,
                         replace = TRUE)
for (k in seq_along(incident_days)) {
  d <- incident_days[k]; kind <- incident_kinds[k]
  is_anomaly[d] <- 1L; anomaly_type[d] <- kind
  if (kind == "late_feed")      late[d] <- runif(1, 120, 300)
  if (kind == "missing_batch")  missing[d] <- runif(1, 6, 14)
  if (kind == "duplicate_load") duplicate[d] <- runif(1, 5, 12)
  if (kind == "null_spike")     null_rate[d] <- runif(1, 5, 11)
}
drift[400:401] <- 1L   # known schema-drift event (2 days), not an anomaly

rows_received <- pmax(0, as.integer(rows_expected * (1 - missing / 100)))
health <- data.frame(
  date = dates,
  rows_expected = rows_expected,
  rows_received = rows_received,
  missing_rate_pct = round(missing, 2),
  duplicate_rate_pct = round(duplicate, 2),
  late_feed_minutes = round(late, 1),
  null_rate_pct = round(null_rate, 2),
  schema_drift_flag = drift,
  is_anomaly = is_anomaly,
  anomaly_type = anomaly_type,
  stringsAsFactors = FALSE
)

write.csv(kpi, file.path(out_dir, "kpi_daily.csv"), row.names = FALSE)
write.csv(health, file.path(out_dir, "pipeline_health_daily.csv"),
          row.names = FALSE)
cat(sprintf("kpi_daily: %d rows x %d cols\n", nrow(kpi), ncol(kpi)))
cat(sprintf("pipeline_health: %d rows x %d cols, %d injected incidents\n",
            nrow(health), ncol(health), sum(health$is_anomaly)))
