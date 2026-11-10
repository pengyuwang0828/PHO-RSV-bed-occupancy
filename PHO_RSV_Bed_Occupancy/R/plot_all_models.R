# Set the project folder. Change this path only if you move the folder.

setwd("/Users/williamwang/Desktop/PHO_RSV_Bed_Occupancy")

stopifnot(dir.exists("data"), dir.exists("output"))
library(ggplot2)
actual <- read.csv("data/original_data.csv")
future <- read.csv("output/all_models_forecast.csv")
backtest <- subset(read.csv("output/backtest_predictions.csv"), stage == "holdout")
actual$week_start <- as.Date(actual$week_start)
future$week_start <- as.Date(future$week_start)
backtest$target <- as.Date(backtest$target)
models <- c("ETS", "ARIMAX", "Random_forest", "XGBoost")
future$model <- factor(future$model, levels = models)
backtest$model <- factor(backtest$model, levels = models)
dir.create("output/model_plots", showWarnings = FALSE)
theme_set(theme_minimal(base_size = 12) + theme(legend.position = "bottom"))
colors <- c(Observed = "#243f5a", Forecast = "#c4532c")
y_label <- "Average bed occupancy per 100,000 population"

# 2. Plot all available observations, including discontinued age definitions.
original <- subset(actual, !is.na(occupancy_rate))
admission_plot <- ggplot(original, aes(week_start, occupancy_rate)) +
  geom_point(color = "#243f5a") + facet_wrap(~age_group, scales = "free_y", ncol = 3) +
  labs(title = "RSV bed occupancy by age group in Ontario", x = "Week start", y = y_label,
    subtitle = "Age definitions changed in 2025; panels are not joined or added together.")
ggsave("output/model_plots/original_occupancy.png", admission_plot, width = 14, height = 13, dpi = 160)

# 3. Plot rolling predictions and final two-week forecasts for each current age group.
for (age in unique(future$age_group)) {
  b <- subset(backtest, age_group == age)
  b$horizon <- factor(b$horizon, levels = 1:2, labels = c("One week ahead", "Two weeks ahead"))
  test_plot <- ggplot(b, aes(target)) +
    geom_line(aes(y = actual, color = "Observed")) +
    geom_line(aes(y = predicted, color = "Forecast")) +
    facet_grid(model ~ horizon) + scale_color_manual(values = colors, name = NULL) +
    labs(title = paste("Rolling forecasts: age", age), x = "Target week", y = y_label)
  label <- gsub("[^A-Za-z0-9]+", "_", age)
  ggsave(paste0("output/model_plots/backtest_age_", label, ".png"), test_plot, width = 13, height = 10, dpi = 160)
  f <- subset(future, age_group == age)
  observed <- tail(subset(original, age_group == age), 12)
  future_plot <- ggplot() +
    geom_ribbon(data = f, aes(week_start, ymin = lower95, ymax = upper95), fill = "#c4dae6") +
    geom_ribbon(data = f, aes(week_start, ymin = lower80, ymax = upper80), fill = "#7cabc5") +
    geom_line(data = observed, aes(week_start, occupancy_rate, color = "Observed")) +
    geom_point(data = observed, aes(week_start, occupancy_rate, color = "Observed")) +
    geom_line(data = f, aes(week_start, forecast, color = "Forecast")) +
    geom_point(data = f, aes(week_start, forecast, color = "Forecast")) +
    facet_wrap(~model, ncol = 1) + scale_color_manual(values = colors, name = NULL) +
    labs(title = paste("Two-week forecasts: age", age), x = "Week start", y = y_label,
      subtitle = "80%/95% intervals: model-based (ETS/ARIMAX), empirical rolling errors (ML).")
  ggsave(paste0("output/model_plots/forecast_age_", label, ".png"), future_plot, width = 11, height = 11, dpi = 160)
}
print(admission_plot)
# Use print(test_plot) or print(future_plot) to view the last age group's comparisons.
