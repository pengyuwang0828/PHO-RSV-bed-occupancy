# 1. Open PHO_RSV_Bed_Occupancy.Rproj before running this script.
if (basename(getwd()) == "scripts") setwd("..")
stopifnot(dir.exists("data"), dir.exists("output"))
library(readxl)
library(forecast)
library(ranger)
library(xgboost)

# 2. Explicit numeric typing is essential: automatic guessing can turn early rates into logical values.
raw <- read_excel("data/RSV_source.xlsx", skip = 2,
  col_types = c("date", "numeric", "text", "date", "date"))
all_data <- data.frame(week_start = as.Date(raw[[1]]), occupancy_rate = raw[[2]], age_group = raw[[3]])
write.csv(all_data, "data/original_data.csv", row.names = FALSE)
latest <- max(all_data$week_start)
groups <- unique(all_data$age_group[all_data$week_start == latest & !is.na(all_data$occupancy_rate)])
models <- c("ETS", "ARIMA", "Random_forest", "XGBoost")

# 3. Short-series features use only information available at the forecast origin.
# Two separate ML models predict weeks 1 and 2. Parameters are fixed, not tuned on holdout data.
features <- function(v, t, h) {
  lag <- c(0, 1, 2, 3, 4, 8, 13)
  x <- setNames(v[t - lag], paste0("lag", lag))
  x <- c(x,
         mean4 = mean(v[(t - 3):t]), mean8 = mean(v[(t - 7):t]),
         change1 = v[t] - v[t - 1], change4 = v[t] - v[t - 4])
  as.data.frame(as.list(x))
}

predict_four <- function(v) {
  z <- ts(v, frequency = 1)
  fitted <- list(
    ETS = ets(z, model = "ZZN", allow.multiplicative.trend = FALSE),
    ARIMA = auto.arima(z, seasonal = FALSE, stepwise = TRUE, approximation = TRUE,
      max.p = 2, max.q = 2, max.P = 1, max.Q = 1, max.d = 1, max.D = 1))
  result <- list()
  for (m in c("ETS", "ARIMA")) {
    fc <- forecast(fitted[[m]], h = 2, level = c(80, 95))
    result[[m]] <- data.frame(model = m, horizon = 1:2, forecast = as.numeric(fc$mean),
      lower80 = as.numeric(fc$lower[, "80%"]), upper80 = as.numeric(fc$upper[, "80%"]),
      lower95 = as.numeric(fc$lower[, "95%"]), upper95 = as.numeric(fc$upper[, "95%"]))
  }
  
  for (m in c("Random_forest", "XGBoost")) {
    prediction <- numeric(2)
    fitted[[m]] <- list()
    for (h in 1:2) {
      origins <- 14:(length(v) - h)
      x <- do.call(rbind, lapply(origins, function(t) features(v, t, h)))
      target <- v[origins + h]
      new_x <- features(v, length(v), h)
      seed <- 20261029 + 1000 * h + length(v)
      if (m == "Random_forest") {
        fit <- ranger(x = x, y = target, num.trees = 300, mtry = 4,
          min.node.size = 3, seed = seed, num.threads = 1)
        prediction[h] <- predict(fit, data = new_x)$predictions
      } else {
        fit <- xgb.train(params = list(objective = "reg:squarederror", max_depth = 2,
          eta = 0.05, min_child_weight = 5, subsample = 0.8, colsample_bytree = 0.8,
          lambda = 10, nthread = 1, seed = seed),
          data = xgb.DMatrix(as.matrix(x), label = target), nrounds = 150, verbose = 0)
        prediction[h] <- predict(fit, xgb.DMatrix(as.matrix(new_x)))
      }
      fitted[[m]][[h]] <- fit
    }
    result[[m]] <- data.frame(model = m, horizon = 1:2, forecast = prediction,
      lower80 = NA, upper80 = NA, lower95 = NA, upper95 = NA)
  }
  result <- do.call(rbind, result)
  bounds <- c("lower80", "upper80", "lower95", "upper95")
  result[bounds] <- lapply(result[bounds], function(x) pmax(0, x))
  result$forecast <- pmax(0, result$forecast)
  list(predictions = result, fitted = fitted)
}


# 4. Evaluate each current age group separately; do not add age-specific rates.
all_backtests <- list(); all_scores <- list(); all_forecasts <- list(); saved_models <- list()
for (age in groups) {
  dat <- all_data[all_data$age_group == age & !is.na(all_data$occupancy_rate), ]
  dat <- dat[order(dat$week_start), ]
  stopifnot(!anyDuplicated(dat$week_start), all(diff(dat$week_start) == 7), all(dat$occupancy_rate >= 0))
  y <- dat$occupancy_rate
  n <- length(y)
  initial <- 26; test_weeks <- 18
  stopifnot(n > initial + test_weeks + 2)
  development <- initial:(n - test_weeks - 2)
  holdout <- (n - test_weeks):(n - 2)
  rows <- list()
  for (i in c(development, holdout)) {
    z <- predict_four(y[1:i])$predictions
    z$stage <- if (i %in% development) "development" else "holdout"
    z$origin <- dat$week_start[i]
    z$target <- dat$week_start[i + z$horizon]
    z$actual <- y[i + z$horizon]
    rows[[length(rows) + 1]] <- z
  }
  backtest <- do.call(rbind, rows)
  backtest$predicted <- backtest$forecast
  backtest$error <- backtest$actual - backtest$predicted

  # Holdout ML intervals use development rolling errors only.
  error_quantiles <- function(m, h, stages) {
    e <- backtest$error[backtest$model == m & backtest$horizon == h & backtest$stage %in% stages]
    as.numeric(quantile(e, c(.025, .10, .90, .975), type = 8))
  }
  for (m in c("Random_forest", "XGBoost")) for (h in 1:2) {
    k <- backtest$model == m & backtest$horizon == h & backtest$stage == "holdout"
    q <- error_quantiles(m, h, "development")
    backtest$lower95[k] <- pmax(0, backtest$predicted[k] + q[1])
    backtest$upper95[k] <- pmax(0, backtest$predicted[k] + q[4])
  }

  # 5. Rank by combined two-horizon RMSE; use MAE to break exact ties.
  scores <- list()
  for (stage in c("development", "holdout")) for (m in models) for (h in 0:2) {
    z <- backtest[backtest$stage == stage & backtest$model == m, ]
    if (h > 0) z <- z[z$horizon == h, ]
    scores[[length(scores) + 1]] <- data.frame(stage = stage, model = m,
      horizon = if (h == 0) "combined" else as.character(h), forecasts = nrow(z),
      RMSE = sqrt(mean(z$error^2)), MAE = mean(abs(z$error)),
      coverage95 = if (all(is.na(z$lower95))) NA else mean(z$actual >= z$lower95 & z$actual <= z$upper95))
  }
  scores <- do.call(rbind, scores)
  ranking <- subset(scores, stage == "holdout" & horizon == "combined")
  ranking <- ranking[order(ranking$RMSE, ranking$MAE), ]
  winner <- ranking$model[1]

  # 6. Refit on all observed weeks and forecast the next two weeks.
  final <- predict_four(y)
  future <- final$predictions
  for (m in c("Random_forest", "XGBoost")) for (h in 1:2) {
    k <- future$model == m & future$horizon == h
    q <- error_quantiles(m, h, c("development", "holdout"))
    future[k, c("lower95", "lower80", "upper80", "upper95")] <- pmax(0, future$forecast[k] + q)
  }
  future$week_start <- max(dat$week_start) + 7 * future$horizon
  future$week_end <- future$week_start + 6
  future$selected <- future$model == winner
  future$interval_method <- ifelse(future$model %in% c("ETS", "ARIMA"),
    "model-based nominal", "empirical rolling residual quantiles")
  future$age_group <- age; scores$age_group <- age; backtest$age_group <- age
  all_forecasts[[age]] <- future; all_scores[[age]] <- scores; all_backtests[[age]] <- backtest
  saved_models[[age]] <- final$fitted
  cat("Completed age group:", age, "Selected model:", winner, "\n")
}
future <- do.call(rbind, all_forecasts)
scores <- do.call(rbind, all_scores)
backtest <- do.call(rbind, all_backtests)
write.csv(future, "output/all_models_forecast.csv", row.names = FALSE)
write.csv(subset(future, selected), "output/selected_forecast.csv", row.names = FALSE)
write.csv(scores, "output/model_comparison.csv", row.names = FALSE)
write.csv(backtest, "output/backtest_predictions.csv", row.names = FALSE)
saveRDS(saved_models, "output/fitted_models.rds")
capture.output(sessionInfo(), file = "output/session_info.txt")
print(subset(future, selected)[c("age_group", "model", "week_start", "forecast", "lower95", "upper95")])
