# Run from the project root after analysis; no model retraining is needed.
if (basename(getwd()) == "scripts") setwd("..")
library(readxl)
raw <- read_excel("data/RSV_source.xlsx", skip=2, col_types=c("date","numeric","text","date","date"))
a <- read.csv("data/original_data.csv")
stopifnot(identical(as.character(as.Date(raw[[1]])),a$week_start),
          identical(as.numeric(raw[[2]]),a$occupancy_rate), identical(raw[[3]],a$age_group))
b <- read.csv("output/backtest_predictions.csv")
s <- read.csv("output/model_comparison.csv")
f <- read.csv("output/all_models_forecast.csv")
q <- read.csv("output/selected_forecast.csv")
stopifnot(setequal(unique(b$model),c("ETS","ARIMA","Random_forest","XGBoost")),
          all(b$origin < b$target), all(f$forecast >= 0), all(f$lower95 >= 0),
          all(f$lower95 <= f$lower80), all(f$lower80 <= f$upper80), all(f$upper80 <= f$upper95))
# Recompute all metrics from individual rolling predictions.
for(j in seq_len(nrow(s))) {
 z <- b[b$age_group==s$age_group[j] & b$model==s$model[j] & b$stage==s$stage[j],]
 if(s$horizon[j]!="combined") z <- z[z$horizon==as.integer(s$horizon[j]),]
 e <- z$actual-z$predicted
 stopifnot(nrow(z)==s$forecasts[j], abs(sqrt(mean(e^2))-s$RMSE[j])<1e-8,
           abs(mean(abs(e))-s$MAE[j])<1e-8)
}
for(age in unique(q$age_group)) {
 z <- b[b$age_group==age,]
 stopifnot(max(z$target[z$stage=="development"])<min(z$target[z$stage=="holdout"]))
 rank <- s[s$age_group==age & s$stage=="holdout" & s$horizon=="combined",]
 rank <- rank[order(rank$RMSE,rank$MAE),]
 selected <- q[q$age_group==age,]
 history <- a[a$age_group==age & !is.na(a$occupancy_rate),]
 stopifnot(nrow(selected)==2, all(selected$model==rank$model[1]),
           all(diff(as.Date(history$week_start))==7),
           all(as.Date(selected$week_start)==max(as.Date(history$week_start))+7*selected$horizon))
}
# Load just the feature definition and verify that later observations cannot affect it.
env <- new.env()
for(e in parse("R/RSV_analysis.R")) {
 if(is.call(e) && identical(e[[1]],as.name("<-")) && identical(e[[2]],as.name("features"))) eval(e,env)
}
v <- seq_len(60)/10
for(h in 1:2) {
 changed <- v; changed[27:60] <- 999
 stopifnot(identical(env$features(v,26,h),env$features(v[1:26],26,h)),
           identical(env$features(v,26,h),env$features(changed,26,h)))
}
for(file in c("scripts/main.R",list.files("R",full.names=TRUE,pattern="\\.R$"))) invisible(parse(file))
cat("PASS: source data, temporal splits, feature leakage, metrics, selections, intervals and syntax.\n")
