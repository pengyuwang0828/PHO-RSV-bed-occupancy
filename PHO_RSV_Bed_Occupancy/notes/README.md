# RSV bed occupancy by age group

## Run

Open `scripts/PHO_RSV_Bed_Occupancy.Rproj`, then Source `main.R`. Each R file starts with one explicit `setwd("/Users/williamwang/Desktop/PHO_RSV_Bed_Occupancy")` line. If you move the folder, update that path in the files you run. No automatic path detection is used. Install `readxl`, `forecast`, `ranger`, `xgboost`, `ggplot2` if needed. To run checks, use `source("test/test_project.R")` from the root, or `source("../test/test_project.R")` from `scripts/`.

Folders: `data/` holds the Excel and extracted data; `R/` holds analysis/plotting code; `output/` holds results, fitted models and `model_plots/`; `notes/` holds this README; `test/` holds checks; `scripts/` holds entry files.

## Method

Compare **ETS, ARIMAX, Random forest and ordinary XGBoost** separately for each of eight current age groups. Only ARIMA has been replaced by ARIMAX; transfer XGBoost has been removed. Ordinary XGBoost remains a 150-round model trained on the current group's history, without pretraining. ETS and random forest settings are unchanged.

The target is **average bed occupancy per 100,000 population**, not admissions or patient counts. Read the Excel metric explicitly as numeric. Current age groups each have 60 weeks from 2025-08-31 to 2026-10-18. Start training with 26 weeks, expand weekly and predict horizons 1/2. Development uses 15 origins; the final 18-week comparison uses 17 origins. Select the lowest combined RMSE per group, with MAE as a tiebreaker. The comparison period selects models and is not an extra independent test.

## Old-group external predictors for ARIMAX

Old groups stopped reporting, so they are not observed contemporaneous covariates. For each old group, fit a bounded seasonal ARIMA to its historical rates strictly **before 2025-08-31** (ending 2025-08-24). Freeze that model and forecast its subsequent weekly path through the two final target weeks. Those projected paths are the external predictors, available at every subsequent rolling origin without future outcome leakage.

Mappings: 0-4 to <1/1/2-4; 18-64 to 18-49/50-64; 65+ to 65-74/75+. For 5-17, use **two separate regressors**, old 5-11 and old 12-17 projections; never sum or average their rates without population weights.

At each origin, fit `auto.arima(current_history, xreg = projected_old_history, seasonal = FALSE, ...)`. The regression coefficients and ARIMA errors use only the observed current-group training history. Supply the next two projected old-group values to `forecast(..., xreg = future_external_values)`. A constant regressor is omitted using that origin's training data only; if no regressor varies, the fit reduces to ARIMA errors without an external effect. Usage is recorded in `output/arimax_regressor_audit.csv`.

The old rates do not become actual historical observations for new age groups. Forecasting the stopped source series involves long extrapolation. ARIMAX prediction intervals are **conditional on the projected external paths** and do not propagate uncertainty in the old-group forecasts. Coefficients may be unstable with 26-60 target weeks; the experiment cannot establish a causal age-group relationship.

## Other models and outputs

ETS uses automatic nonseasonal error/trend selection. RF uses 300 trees, mtry 4 and node size 3. Ordinary XGBoost uses 150 rounds, depth 2, learning rate 0.05 and L2 penalty 10. ML features are origin/current values, lags through 13 weeks, recent means and changes, with separate horizon models. Settings are fixed without holdout tuning.

ML intervals use rolling error quantiles (development errors only for holdout intervals). Negative forecasts/bounds are clipped to zero. Final target weeks start **2026-10-25 and 2026-11-01**, relative to the source file. Short, predominantly low-occupancy validation limits conclusions about winter performance; revisions and age-definition changes add uncertainty.

| Age group | Selected model | Holdout RMSE |
|---|---|---:|
| <1 | ARIMAX | 0.2597 |
| 1 | ETS | 0.1175 |
| 2 to 4 | ARIMAX | 0.0786 |
| 5 to 17 | ETS | 0.0298 |
| 18 to 49 | ETS | 0.0000 |
| 50 to 64 | ETS | 0.0373 |
| 65 to 74 | ARIMAX | 0.0334 |
| 75+ | ARIMAX | 0.0691 |

`output/selected_forecast.csv` contains final selected forecasts; `all_models_forecast.csv`, `model_comparison.csv` and `backtest_predictions.csv` contain the four-model results. `external_predictors.csv` records source history cutoffs and projected external values; `external_source_models.rds` saves frozen source fits. Graphs are in `output/model_plots/`. `print(admission_plot)` shows original history; `print(test_plot)` and `print(future_plot)` show the last age group's comparisons. All comments are in English; no separate report is generated.
