## Driver analysis + benchmarking (Problem 3).
##
## Question: which operational levers actually move SLA attainment?
## Method: gradient boosting on same-day operational features, ranked
## by permutation importance (shuffle one feature, measure the drop in
## out-of-sample R-squared). Permutation importance is model-agnostic,
## so STATA / SPSS / SAS can reproduce the same ranking with their own
## standardised regression coefficients — the cross-tool check.
##
## Also: a per-channel benchmark table (dashboard-ready).

permutation_importance <- function(model, X, y, n_repeats = 10,
                                   seed = 42) {
  set.seed(seed)
  base_pred <- as.numeric(predict(model, newdata = X, n.trees = 500))
  base_r2 <- 1 - sum((y - base_pred)^2) / sum((y - mean(y))^2)
  imp <- sapply(names(X), function(col) {
    drops <- numeric(n_repeats)
    for (r in seq_len(n_repeats)) {
      Xp <- X
      Xp[[col]] <- sample(Xp[[col]])
      pr <- as.numeric(predict(model, newdata = Xp, n.trees = 500))
      r2 <- 1 - sum((y - pr)^2) / sum((y - mean(y))^2)
      drops[r] <- base_r2 - r2
    }
    mean(drops)
  })
  df <- data.frame(feature = names(imp),
                   permutation_importance = as.numeric(imp),
                   stringsAsFactors = FALSE)
  df[order(-df$permutation_importance), ]
}

channel_benchmark <- function(kpi) {
  agg <- do.call(rbind, lapply(split(kpi, kpi$channel), function(d) {
    data.frame(
      channel = d$channel[1],
      avg_daily_tickets = round(mean(d$tickets_received), 1),
      sla_attainment_pct = round(mean(d$sla_attainment_pct), 2),
      first_contact_resolution_pct =
        round(mean(d$first_contact_resolution_pct), 2),
      csat_score = round(mean(d$csat_score), 2),
      avg_handle_time_min = round(mean(d$avg_handle_time_min), 2),
      avg_backlog = round(mean(d$backlog_open), 1),
      sla_below_90_pct = round(mean(d$sla_attainment_pct < 90) * 100, 1),
      stringsAsFactors = FALSE)
  }))
  agg[order(-agg$sla_attainment_pct), ]
}
