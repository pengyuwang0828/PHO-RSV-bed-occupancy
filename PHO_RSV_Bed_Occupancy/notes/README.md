# RSV bed occupancy by age group

## Run

Install `readxl`, `forecast`, `ranger`, `xgboost` and `ggplot2` if needed. Set `folder` at the top of both scripts. In RStudio, Source `RSV_analysis.R`, then `plot_all_models.R`. Use `print(admission_plot)` for the original data. All plots are saved in `output/model_plots/`.

## Approach

- Forecast **average bed occupancy per 100,000 population**, not admissions or patient counts. Keep decimal values. Excel values are explicitly read as numeric because automatic type guessing can incorrectly return logical values.
- Age definitions changed in 2025. Forecast the eight current groups separately using their 60 complete weeks, **2025-08-31 to 2026-10-18**. Discontinued groups appear only in the original-data plot. Do not splice different definitions or sum age-specific rates.
- Compare **ETS, ARIMA, Random forest and XGBoost**, using an expanding training window starting at **26 weeks**. Development: 15 rolling origins. Final 18-week comparison: 17 origins. At each origin, predict weeks 1 and 2 without using future outcomes.
- ETS and ARIMA are nonseasonal because each current age definition has only about one year of history. ML uses lags through 13 weeks, recent averages and changes; separate models predict each horizon. RF: 300 trees, mtry 4, node size 3. XGBoost: 150 rounds, depth 2, learning rate 0.05, L2 penalty 10. Settings are fixed, not optimized on the comparison period.
- Choose the lowest combined two-horizon **RMSE for each group**, with MAE as a tiebreaker. Refit on all 60 weeks. Forecast weeks start **2026-10-25 and 2026-11-01**, relative to the file's latest observation.
- ETS/ARIMA intervals are model-based; ML intervals use rolling out-of-sample error quantiles. Holdout intervals use only development errors. Final intervals use all known rolling errors. Negative bounds and predictions are clipped to zero.

## Selected models

| Age group | Selected model | Comparison RMSE |
|---|---|---:|
| <1 | ARIMA | 0.260 |
| 1 | ETS | 0.118 |
| 2 to 4 | ETS | 0.082 |
| 5 to 17 | ARIMA | 0.030 |
| 18 to 49 | ETS | 0.000 |
| 50 to 64 | ARIMA | 0.034 |
| 65 to 74 | ETS | 0.034 |
| 75+ | ARIMA | 0.075 |

`output/selected_forecast.csv` contains the selected forecasts and intervals; `output/all_models_forecast.csv` contains all four models. `output/model_comparison.csv` gives scores by group and horizon, and `output/backtest_predictions.csv` gives individual predictions. `data/original_data.csv` preserves missing values and all age definitions. Model objects and R session details are also saved.

The comparison period is used to choose models, not an additional independent test. The short series, small effective ML sample and predominantly low-occupancy comparison period limit conclusions about future winter performance. Empirical intervals have no coverage guarantee; reporting revisions and age-definition changes add uncertainty.
