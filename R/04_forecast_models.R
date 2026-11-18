## Forecasting models (Problem 1).
##
## Baselines (interpretable, auditable):
##   - Seasonal naive: forecast = value one week ago
##   - Holt-Winters additive (stats::HoltWinters, weekly seasonality)
## Machine learning (same lag + calendar features everywhere):
##   - Linear regression (lm) on scaled features
##   - Random forest (randomForest)
##   - Gradient boosting (gbm)
##
## Evaluation is strictly time-based: the last 61 days are the hold-out.
## Metrics: MAE, RMSE, MAPE.

regression_metrics <- function(y_true, y_pred) {
  y_true <- as.numeric(y_true); y_pred <- as.numeric(y_pred)
  err <- y_true - y_pred
  list(mae = mean(abs(err)),
       rmse = sqrt(mean(err^2)),
       mape = mean(abs(err) / pmax(abs(y_true), 1e-9)) * 100,
       n = length(y_true))
}

seasonal_naive_fit <- function(y, period = 7) {
  structure(list(tail = tail(as.numeric(y), period), period = period),
            class = "seasonal_naive")
}

predict.seasonal_naive <- function(object, steps, ...) {
  rep_len(object$tail, steps)
}

## Holt-Winters on the training series; returns the fitted model and a
## 14-day recursive forecast.
holt_winters_forecast <- function(y_train, steps = 14) {
  ts_y <- ts(as.numeric(y_train), frequency = 7)
  ## suppressWarnings: HoltWinters' optimiser occasionally reports
  ## "ABNORMAL_TERMINATION_IN_LNSRCH" on noisy series; the fitted
  ## model is still valid (verified: finite 14-day forecast).
  fit <- suppressWarnings(HoltWinters(ts_y, seasonal = "additive"))
  list(fit = fit, forecast = as.numeric(predict(fit, n.ahead = steps)))
}

## One-step-ahead predictions on the test frame for an ML model that
## was trained on lag features (lags are precomputed, so prediction is
## a plain predict() call).
train_ml_forecasters <- function(X_train, y_train) {
  X_train <- as.data.frame(X_train)
  list(
    linear = lm(y_train ~ ., data = cbind(y_train = y_train, X_train)),
    random_forest = randomForest::randomForest(
      x = X_train, y = y_train, ntree = 500, mtry = max(2, floor(ncol(X_train) / 3)),
      nodesize = 5, importance = TRUE),
    gbm = gbm::gbm.fit(
      x = X_train, y = y_train, distribution = "gaussian",
      n.trees = 500, interaction.depth = 3, shrinkage = 0.05,
      bag.fraction = 0.8, n.minobsinnode = 10, verbose = FALSE)
  )
}

predict_ml <- function(models, X_test) {
  X_test <- as.data.frame(X_test)
  list(
    linear = as.numeric(predict(models$linear,
                                newdata = X_test)),
    random_forest = as.numeric(predict(models$random_forest,
                                       newdata = X_test)),
    gbm = as.numeric(predict(models$gbm, newdata = X_test,
                             n.trees = 500))
  )
}
