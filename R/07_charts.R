## Charts — base R graphics, generated from the actual model run.
## No hand-drawn or invented numbers.

NAVY <- "#1f4e79"; TEAL <- "#2e9e6b"; ORANGE <- "#d97706"
RED <- "#b91c1c"; GREY <- "#6b7280"

chart_forecast_vs_actual <- function(dates, actual, gbm_pred,
                                     hw_14, hw_actual_14, out_path) {
  png(out_path, width = 1200, height = 780, res = 120)
  par(mfrow = c(2, 1), mar = c(4, 4.5, 3, 1))
  plot(dates, actual, type = "l", col = NAVY, lwd = 2,
       main = "SLA attainment: actual vs 1-step-ahead forecast (61-day hold-out)",
       xlab = "", ylab = "SLA attainment (%)")
  lines(dates, gbm_pred, col = TEAL, lwd = 1.5, lty = 2)
  legend("bottomleft", c("Actual", "Gradient boosting (1-step-ahead)"),
         col = c(NAVY, TEAL), lwd = c(2, 1.5), lty = c(1, 2), bty = "n")
  grid()
  plot(seq_along(hw_actual_14), hw_actual_14, type = "b", pch = 16,
       col = NAVY, lwd = 1.5,
       main = "14-day-ahead forecast from end of training data",
       xlab = "Days ahead", ylab = "SLA attainment (%)")
  lines(seq_along(hw_14), hw_14, type = "b", pch = 17, col = ORANGE, lwd = 1.5)
  legend("bottomleft", c("Actual (first 14 hold-out days)",
                         "Holt-Winters 14-day recursive forecast"),
         col = c(NAVY, ORANGE), lwd = 1.5, pch = c(16, 17), bty = "n")
  grid()
  dev.off()
}

chart_model_comparison <- function(comp_df, out_path,
                                   metric = "mape",
                                   title = "Forecast error by model (SLA attainment, hold-out)") {
  df <- comp_df[order(comp_df[[metric]]), ]
  png(out_path, width = 1080, height = 540, res = 120)
  par(mar = c(5, 14, 3, 2))
  cols <- ifelse(seq_len(nrow(df)) == 1, TEAL, NAVY)
  bp <- barplot(rev(df[[metric]]), names.arg = rev(df$model),
                horiz = TRUE, col = rev(cols), las = 1,
                xlab = "MAPE (%) — lower is better", main = title)
  text(rev(df[[metric]]) + 0.02, bp,
       sprintf("%.2f", rev(df[[metric]])), pos = 4, cex = 0.9)
  grid(nx = TRUE, ny = FALSE)
  dev.off()
}

chart_feature_importance <- function(imp_df, out_path, top_n = 10) {
  df <- head(imp_df, top_n)
  df <- df[order(df$permutation_importance), ]
  png(out_path, width = 1080, height = 600, res = 120)
  par(mar = c(5, 22, 3, 2))
  barplot(df$permutation_importance, names.arg = df$feature,
          horiz = TRUE, col = NAVY, las = 1,
          xlab = "Permutation importance (drop in R-squared)",
          main = "What drives SLA attainment? (gradient boosting)")
  grid(nx = TRUE, ny = FALSE)
  dev.off()
}

chart_anomaly_timeline <- function(health, flags, out_path) {
  png(out_path, width = 1200, height = 600, res = 120)
  par(mar = c(6, 4.5, 3, 1))
  plot(health$date, health$health_score, type = "l", col = NAVY,
       lwd = 1,
       main = "Data-quality anomaly detection on the reporting pipeline (730 days)",
       xlab = "", ylab = "Health score (higher = worse)")
  flagged <- health[flags == 1, ]
  points(flagged$date, flagged$health_score, col = RED, pch = 16, cex = 0.9)
  truth <- health[health$is_anomaly == 1, ]
  points(truth$date, truth$health_score, col = ORANGE, pch = 1, cex = 1.4, lwd = 1.5)
  legend("bottom", inset = c(0, -0.38), horiz = TRUE, xpd = TRUE,
         bty = "n",
         c("Pipeline health score", "Flagged anomaly",
           "Injected incident (ground truth)"),
         col = c(NAVY, RED, ORANGE), lwd = c(1, NA, NA),
         pch = c(NA, 16, 1))
  grid()
  dev.off()
}

chart_sla_by_channel <- function(bench, out_path) {
  png(out_path, width = 1080, height = 540, res = 120)
  par(mar = c(5, 16, 3, 2))
  cols <- ifelse(bench$sla_attainment_pct >= 90, TEAL, ORANGE)
  bp <- barplot(bench$sla_attainment_pct, names.arg = bench$channel,
                horiz = TRUE, col = cols, las = 1, xlim = c(70, 100),
                ylim = c(0, 6.8),
                xlab = "Mean SLA attainment (%)",
                main = "Service-line benchmark: mean SLA attainment")
  abline(v = 90, col = RED, lty = 2, lwd = 1.5)
  text(90.5, 6.4, "90% SLA target", col = RED, pos = 4, cex = 0.9)
  text(bench$sla_attainment_pct + 0.4, bp,
       sprintf("%.1f%%", bench$sla_attainment_pct), pos = 4, cex = 0.9)
  grid(nx = TRUE, ny = FALSE)
  dev.off()
}

chart_correlation <- function(daily, out_path) {
  cols <- c("tickets_received", "backlog_open", "staffing_ratio",
            "avg_handle_time_min", "first_contact_resolution_pct",
            "system_uptime_pct", "sla_attainment_pct")
  corr <- cor(daily[, cols])
  png(out_path, width = 900, height = 780, res = 120)
  par(mar = c(8, 14, 3, 2))
  pal <- colorRampPalette(c("#b91c1c", "white", "#2e9e6b"))(100)
  image(1:7, 1:7, t(corr)[, 7:1], col = pal, zlim = c(-1, 1),
        axes = FALSE, xlab = "", ylab = "",
        main = "KPI correlation matrix (daily aggregate)")
  axis(1, at = 1:7, labels = gsub("_", "\n", cols), las = 2, cex.axis = 0.8)
  axis(2, at = 1:7, labels = rev(gsub("_", " ", cols)), las = 1, cex.axis = 0.8)
  for (i in 1:7) for (j in 1:7) {
    text(j, 8 - i, sprintf("%.2f", corr[i, j]), cex = 0.85,
         col = ifelse(abs(corr[i, j]) > 0.5, "white", "black"))
  }
  dev.off()
}
