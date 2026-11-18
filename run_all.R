## run_all.R — end-to-end orchestrator.
##
## Run from the project root:
##   Rscript run_all.R
##
## Outputs:
##   data/synthetic/*.csv          generated data
##   data/processed/*.csv          cleaned + daily aggregate
##   models/best_model.rds         gradient-boosting SLA forecaster
##   models/metrics.csv            all evaluation metrics
##   reports/charts/*.png          six charts (real numbers only)
##   reports/model_report.md       metrics + findings

ROOT <- getwd()
if (basename(ROOT) != "ml-project-kforce-data-analyst") {
  # Allow running from anywhere by locating the project root.
  cand <- file.path(path.expand("~"), "workspace",
                    "ml-project-kforce-data-analyst")
  if (dir.exists(cand)) setwd(cand)
  ROOT <- getwd()
}
## Fixed seed so the whole pipeline is reproducible run to run.
set.seed(42)
for (f in list.files(file.path(ROOT, "R"), pattern = "^0[2-7]_",
                     full.names = TRUE)) source(f)

suppressPackageStartupMessages({
  library(randomForest)
  library(gbm)
})

SYN <- file.path(ROOT, "data", "synthetic")
PROC <- file.path(ROOT, "data", "processed")
CHARTS <- file.path(ROOT, "reports", "charts")
MODELS <- file.path(ROOT, "models")
dir.create(CHARTS, showWarnings = FALSE, recursive = TRUE)
dir.create(MODELS, showWarnings = FALSE, recursive = TRUE)

## ---- 1. Data -----------------------------------------------------------
if (!file.exists(file.path(SYN, "kpi_daily.csv"))) {
  source(file.path(ROOT, "R", "01_data_generation.R"))
}
pipe <- run_pipeline(SYN, PROC)
daily <- pipe$daily
kpi <- pipe$kpi
health <- pipe$health
cat(sprintf("Daily aggregate: %d days (%s to %s)\n", nrow(daily),
            min(daily$date), max(daily$date)))
cat(sprintf("Data quality: kpi missing=%d dup=%d gaps=%d; health missing=%d dup=%d gaps=%d\n",
            pipe$quality_reports$kpi$missing_cells,
            pipe$quality_reports$kpi$duplicate_rows,
            pipe$quality_reports$kpi$date_gaps,
            pipe$quality_reports$health$missing_cells,
            pipe$quality_reports$health$duplicate_rows,
            pipe$quality_reports$health$date_gaps))

## ---- 2. Forecasting (Problem 1) ----------------------------------------
## Design decision: the forecaster uses ONLY lag + calendar features
## (known before the day starts). Same-day operational features are
## explanatory, not forecasting inputs -- using them would leak.
TARGETS <- c("sla_attainment_pct", "tickets_received")
all_metrics <- list()
forecast_store <- list()

for (target in TARGETS) {
  bf <- build_features(daily, target, include_operational = FALSE)
  fr <- bf$frame; feats <- bf$features
  sp <- time_split(fr, test_days = 61)
  train <- sp$train; test <- sp$test
  Xtr <- train[, feats, drop = FALSE]; ytr <- train[[target]]
  Xte <- test[, feats, drop = FALSE]; yte <- test[[target]]

  # Seasonal naive (value 7 days earlier, from the full series).
  full_y <- fr[[target]]
  test_idx <- which(fr$date %in% test$date)
  naive_pred <- full_y[test_idx - 7]

  # Holt-Winters on the training series.
  hw <- holt_winters_forecast(ytr, steps = 14)
  hw_test_pred <- as.numeric(predict(
    hw$fit, n.ahead = nrow(test)))

  ml <- train_ml_forecasters(Xtr, ytr)
  ml_pred <- predict_ml(ml, Xte)

  res <- list(
    seasonal_naive = regression_metrics(yte, naive_pred),
    holt_winters = regression_metrics(yte, hw_test_pred),
    linear = regression_metrics(yte, ml_pred$linear),
    random_forest = regression_metrics(yte, ml_pred$random_forest),
    gradient_boosting = regression_metrics(yte, ml_pred$gbm))
  for (nm in names(res)) {
    all_metrics[[length(all_metrics) + 1]] <- data.frame(
      target = target, model = nm, mae = res[[nm]]$mae,
      rmse = res[[nm]]$rmse, mape = res[[nm]]$mape, n = res[[nm]]$n,
      stringsAsFactors = FALSE)
  }
  forecast_store[[target]] <- list(
    test = test, yte = yte, ml_pred = ml_pred,
    hw_14 = hw$forecast,
    hw_actual_14 = yte[seq_len(14)],
    gbm_model = ml$gradient_boosting, feats = feats)
  cat(sprintf("[%s] best MAPE: %s %.2f%%\n", target,
              names(which.min(sapply(res, `[[`, "mape"))),
              min(sapply(res, `[[`, "mape"))))
}

## ---- 3. Anomaly detection (Problem 2) ----------------------------------
hf <- anomaly_features(health)
det <- detect_anomalies(hf, ANOMALY_FEATURES)
anom_metrics <- anomaly_metrics(hf$is_anomaly, det$flag)
cat(sprintf("Anomaly detection: precision %.3f recall %.3f F1 %.3f (%d flagged, %d true)\n",
            anom_metrics$precision, anom_metrics$recall,
            anom_metrics$f1, anom_metrics$n_flagged,
            anom_metrics$n_true))

## ---- 4. Driver analysis + benchmarking (Problem 3) ---------------------
bf_drv <- build_features(daily, "sla_attainment_pct",
                         include_operational = TRUE)
fr_drv <- bf_drv$frame; feats_drv <- bf_drv$features
sp_drv <- time_split(fr_drv, test_days = 61)
drv_model <- gbm::gbm.fit(
  x = as.data.frame(sp_drv$train[, feats_drv, drop = FALSE]),
  y = sp_drv$train$sla_attainment_pct, distribution = "gaussian",
  n.trees = 500, interaction.depth = 3, shrinkage = 0.05,
  bag.fraction = 0.8, n.minobsinnode = 10, verbose = FALSE)
imp <- permutation_importance(
  drv_model,
  as.data.frame(sp_drv$test[, feats_drv, drop = FALSE]),
  sp_drv$test$sla_attainment_pct)
bench <- channel_benchmark(kpi)
cat("Top 3 SLA drivers:\n")
print(head(imp, 3), row.names = FALSE)

## ---- 5. Save models + metrics ------------------------------------------
saveRDS(forecast_store[["sla_attainment_pct"]]$gbm_model,
        file.path(MODELS, "best_model.rds"))
metrics_df <- do.call(rbind, all_metrics)
write.csv(metrics_df, file.path(MODELS, "metrics.csv"),
          row.names = FALSE)
write.csv(imp, file.path(MODELS, "driver_importance.csv"),
          row.names = FALSE)
write.csv(bench, file.path(MODELS, "channel_benchmark.csv"),
          row.names = FALSE)
anom_df <- data.frame(
  metric = c("precision", "recall", "f1", "n_flagged", "n_true",
             "tp", "fp", "fn"),
  value = c(anom_metrics$precision, anom_metrics$recall,
            anom_metrics$f1, anom_metrics$n_flagged,
            anom_metrics$n_true, anom_metrics$tp,
            anom_metrics$fp, anom_metrics$fn))
write.csv(anom_df, file.path(MODELS, "anomaly_metrics.csv"),
          row.names = FALSE)

## ---- 6. Charts ----------------------------------------------------------
fs <- forecast_store[["sla_attainment_pct"]]
chart_forecast_vs_actual(fs$test$date, fs$yte, fs$ml_pred$gbm,
                         fs$hw_14, fs$hw_actual_14,
                         file.path(CHARTS, "forecast_vs_actual.png"))
sla_comp <- metrics_df[metrics_df$target == "sla_attainment_pct", ]
chart_model_comparison(sla_comp,
                       file.path(CHARTS, "model_comparison.png"))
vol_comp <- metrics_df[metrics_df$target == "tickets_received", ]
chart_model_comparison(vol_comp,
                       file.path(CHARTS, "model_comparison_volume.png"),
                       title = "Forecast error by model (ticket volume, hold-out)")
chart_feature_importance(imp, file.path(CHARTS, "feature_importance.png"))
hf$health_score <- hf$missing_rate_pct + hf$duplicate_rate_pct +
  hf$null_rate_pct + hf$late_feed_minutes / 30
chart_anomaly_timeline(hf, det$flag,
                       file.path(CHARTS, "anomaly_timeline.png"))
chart_sla_by_channel(bench, file.path(CHARTS, "sla_by_channel.png"))
chart_correlation(daily, file.path(CHARTS, "correlation_heatmap.png"))

## ---- 7. Model report ----------------------------------------------------
sla_best <- sla_comp[which.min(sla_comp$mape), ]
vol_best <- vol_comp[which.min(vol_comp$mape), ]
report <- sprintf(
"# Model report — Kforce Data Analyst ML project

*Generated by `Rscript run_all.R` on %s. All data is synthetic
(set.seed 42/43). All metrics are measured on the 61-day time-based
hold-out (2025-11-01 to 2025-12-30), never on training data.*

## Data
- Daily aggregate: %d days (%s to %s); channel grain: %d rows
  (5 channels x 730 days).
- Data-quality validation: kpi_daily missing=%d, duplicates=%d,
  date gaps=%d; pipeline_health missing=%d, duplicates=%d, gaps=%d.
- Pipeline-health log: %d injected data-quality incidents.

## Problem 1 — KPI / service-performance forecasting
| model | target | MAE | RMSE | MAPE (%%) |
|---|---|---|---|---|
%s

Best SLA forecaster: **%s** (MAPE %.2f%%). Best volume forecaster:
**%s** (MAPE %.2f%%). Holt-Winters 14-day-ahead MAPE on the first
14 hold-out days: %.2f%%.

## Problem 2 — Data-quality anomaly detection
Z-score rule on 8 pipeline-health features: flag a day when any
feature is more than 4 SD out, or the composite health score is
more than 4 SD above its mean.
Precision %.3f, recall %.3f, F1 %.3f — %d days flagged, %d true
incidents (%d caught, %d missed, %d false alarms).

## Problem 3 — What drives SLA attainment
Top 3 drivers (permutation importance, gradient boosting):
1. %s (%.4f)
2. %s (%.4f)
3. %s (%.4f)

Channel benchmark (mean SLA): %s.

## Honest limits
- Synthetic data: magnitudes and rankings are illustrative, not
  evidence about any real client.
- R is the executable reference implementation. The STATA (.do),
  SPSS (.sps) and SAS (.sas) scripts replicate the same data, splits
  and metrics; they were authored and syntax-reviewed but not executed
  on this machine (commercial software not installed) — run them in
  the licensed application to reproduce the comparison table.
- Same-day operational features are used only for driver analysis,
  never for forecasting (that would leak).
",
  format(Sys.Date(), "%Y-%m-%d"), nrow(daily), min(daily$date),
  max(daily$date), nrow(kpi),
  pipe$quality_reports$kpi$missing_cells,
  pipe$quality_reports$kpi$duplicate_rows,
  pipe$quality_reports$kpi$date_gaps,
  pipe$quality_reports$health$missing_cells,
  pipe$quality_reports$health$duplicate_rows,
  pipe$quality_reports$health$date_gaps,
  sum(health$is_anomaly),
  paste(apply(metrics_df, 1, function(r) sprintf(
    "| %s | %s | %.2f | %.2f | %.2f |", r["model"], r["target"],
    as.numeric(r["mae"]), as.numeric(r["rmse"]),
    as.numeric(r["mape"]))), collapse = "\n"),
  sla_best$model, sla_best$mape, vol_best$model, vol_best$mape,
  regression_metrics(fs$hw_actual_14, fs$hw_14)$mape,
  anom_metrics$precision, anom_metrics$recall, anom_metrics$f1,
  anom_metrics$n_flagged, anom_metrics$n_true, anom_metrics$tp,
  anom_metrics$fn, anom_metrics$fp,
  imp$feature[1], imp$permutation_importance[1],
  imp$feature[2], imp$permutation_importance[2],
  imp$feature[3], imp$permutation_importance[3],
  paste(sprintf("%s %.1f%%", bench$channel,
                bench$sla_attainment_pct), collapse = ", "))
writeLines(report, file.path(ROOT, "reports", "model_report.md"))
cat("Done. Report:", file.path(ROOT, "reports", "model_report.md"), "\n")
