## Test suite — plain R assertions (no testthat dependency).
##
## Run from the project root:
##   Rscript tests/run_tests.R
## Exits non-zero on the first failure; prints PASS count on success.

ROOT <- getwd()
if (basename(ROOT) != "ml-project-kforce-data-analyst") {
  cand <- file.path(path.expand("~"), "workspace",
                    "ml-project-kforce-data-analyst")
  if (dir.exists(cand)) setwd(cand)
  ROOT <- getwd()
}
for (f in list.files(file.path(ROOT, "R"), pattern = "^0[2-7]_",
                     full.names = TRUE)) source(f)
suppressPackageStartupMessages({ library(randomForest); library(gbm) })
set.seed(42)  # reproducible test runs

passed <- 0L
check <- function(cond, label) {
  if (!isTRUE(cond)) stop("FAIL: ", label, call. = FALSE)
  passed <<- passed + 1L
  cat("PASS:", label, "\n")
}

SYN <- file.path(ROOT, "data", "synthetic")
PROC <- file.path(ROOT, "data", "processed")

## --- data generation -----------------------------------------------------
if (!file.exists(file.path(SYN, "kpi_daily.csv"))) {
  source(file.path(ROOT, "R", "01_data_generation.R"))
}
kpi <- load_kpi(file.path(SYN, "kpi_daily.csv"))
health <- load_health(file.path(SYN, "pipeline_health_daily.csv"))
check(nrow(kpi) == 730 * 5, "kpi_daily has 3650 rows (730 days x 5 channels)")
check(all(REQUIRED_KPI_COLS %in% names(kpi)), "kpi_daily has all required columns")
check(length(unique(kpi$channel)) == 5, "kpi_daily has 5 channels")
check(sum(health$is_anomaly) == 25, "pipeline_health has 25 injected incidents")
check(all(health$is_anomaly %in% c(0, 1)), "is_anomaly is binary")

## --- pipeline ------------------------------------------------------------
rep_kpi <- validate_frame(kpi, "kpi_daily")
check(rep_kpi$missing_cells == 0, "kpi_daily has zero missing cells")
check(rep_kpi$duplicate_rows == 0, "kpi_daily has zero duplicate rows")
check(rep_kpi$date_gaps == 0, "kpi_daily has zero date gaps")
check(length(rep_kpi$range_violations) == 0, "kpi_daily has zero range violations")
daily <- aggregate_daily(clean_kpi(kpi))
check(nrow(daily) == 730, "daily aggregate has 730 rows")
check(all(daily$sla_attainment_pct >= 0 &
            daily$sla_attainment_pct <= 100), "SLA in [0,100]")
check(all(c("staffing_ratio", "backlog_ratio") %in% names(daily)),
      "daily aggregate has derived ratios")

## --- features ------------------------------------------------------------
bf <- build_features(daily, "sla_attainment_pct",
                     include_operational = FALSE)
check(nrow(bf$frame) == 730 - 28, "feature frame drops first 28 lag rows")
check(all(bf$features %in% names(bf$frame)), "all features present in frame")
check(!any(is.na(bf$frame[, bf$features])), "no NA in feature columns")
sp <- time_split(bf$frame, test_days = 61)
check(nrow(sp$test) == 61, "time split gives 61 test days")
check(max(sp$train$date) < min(sp$test$date), "train precedes test in time")

## --- forecasting ---------------------------------------------------------
Xtr <- sp$train[, bf$features, drop = FALSE]
ytr <- sp$train$sla_attainment_pct
Xte <- sp$test[, bf$features, drop = FALSE]
yte <- sp$test$sla_attainment_pct
ml <- train_ml_forecasters(Xtr, ytr)
preds <- predict_ml(ml, Xte)
check(all(sapply(preds, length) == 61), "all ML models predict 61 values")
check(all(sapply(preds, function(p) all(is.finite(p)))),
      "all ML predictions finite")
m_gbm <- regression_metrics(yte, preds$gbm)
check(is.finite(m_gbm$mape) && m_gbm$mape < 10,
      "GBM SLA MAPE is finite and < 10%")
sn <- seasonal_naive_fit(ytr)
check(length(predict(sn, 14)) == 14, "seasonal naive predicts 14 steps")
hw <- holt_winters_forecast(ytr, steps = 14)
check(length(hw$forecast) == 14 && all(is.finite(hw$forecast)),
      "Holt-Winters 14-day forecast finite")

## --- anomaly detection ---------------------------------------------------
hf <- anomaly_features(health)
check(nrow(hf) == 729, "anomaly feature frame has 729 rows (1 lag row dropped)")
det <- detect_anomalies(hf, ANOMALY_FEATURES)
am <- anomaly_metrics(hf$is_anomaly, det$flag)
check(am$recall >= 0.5, "anomaly recall >= 0.50")
check(am$precision >= 0.3, "anomaly precision >= 0.30")
check(am$n_flagged > 0 && am$n_flagged < 100, "flagged count is sane")

## --- drivers -------------------------------------------------------------
bf_drv <- build_features(daily, "sla_attainment_pct",
                         include_operational = TRUE)
sp_drv <- time_split(bf_drv$frame, test_days = 61)
drv <- gbm::gbm.fit(
  x = as.data.frame(sp_drv$train[, bf_drv$features, drop = FALSE]),
  y = sp_drv$train$sla_attainment_pct, distribution = "gaussian",
  n.trees = 200, interaction.depth = 3, shrinkage = 0.05,
  bag.fraction = 0.8, n.minobsinnode = 10, verbose = FALSE)
imp <- permutation_importance(
  drv, as.data.frame(sp_drv$test[, bf_drv$features, drop = FALSE]),
  sp_drv$test$sla_attainment_pct, n_repeats = 3)
check(nrow(imp) == length(bf_drv$features),
      "permutation importance covers all driver features")
check(imp$permutation_importance[1] > 0,
      "top driver has positive importance")
bench <- channel_benchmark(kpi)
check(nrow(bench) == 5, "channel benchmark has 5 rows")
check(all(bench$sla_attainment_pct > 0), "benchmark SLA values positive")

cat(sprintf("\nAll %d tests passed.\n", passed))
