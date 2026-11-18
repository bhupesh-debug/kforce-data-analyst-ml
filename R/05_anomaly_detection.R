## Data-quality anomaly detection (Problem 2).
##
## Approach: explainable statistical detection, not a black box.
##   1. Standardise each pipeline-health feature (z-scores).
##   2. Flag a day when any single feature is more than 4 standard
##      deviations out, OR the composite health score is more than
##      4 SD above its mean.
## The rule is deliberately simple so it can be replicated exactly in
## STATA, SPSS and SAS (z-scores + threshold) — that is what makes
## the cross-tool comparison fair. A Mahalanobis-distance version was
## tried first and dropped: the health score is a linear combination
## of the other features, so the covariance matrix is singular.
## Ground truth is the injected incident label (is_anomaly) from the
## generator, so precision / recall / F1 are honest, measured numbers.

anomaly_metrics <- function(y_true, y_pred) {
  tp <- sum(y_true == 1 & y_pred == 1)
  fp <- sum(y_true == 0 & y_pred == 1)
  fn <- sum(y_true == 1 & y_pred == 0)
  precision <- if (tp + fp > 0) tp / (tp + fp) else 0
  recall <- if (tp + fn > 0) tp / (tp + fn) else 0
  f1 <- if (precision + recall > 0) {
    2 * precision * recall / (precision + recall)
  } else 0
  list(precision = precision, recall = recall, f1 = f1,
       n_flagged = sum(y_pred), n_true = sum(y_true), tp = tp,
       fp = fp, fn = fn)
}

detect_anomalies <- function(feat_df, feature_cols, z_cut = 4) {
  X <- as.matrix(feat_df[, feature_cols, drop = FALSE])
  Z <- scale(X)  # z-scores, centred on the full history
  max_z <- apply(abs(Z), 1, max)
  hs <- feat_df$health_score
  hs_threshold <- mean(hs) + 4 * sd(hs)
  flag <- as.integer(max_z > z_cut | hs > hs_threshold)
  list(flag = flag, max_z = max_z, health_score = hs,
       hs_threshold = hs_threshold, z_cut = z_cut)
}
