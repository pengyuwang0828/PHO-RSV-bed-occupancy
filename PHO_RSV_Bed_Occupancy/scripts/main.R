# Open the .Rproj in scripts, then Source this file.
# All analysis paths are relative to the parent project folder.
if (basename(getwd()) == "scripts") setwd("..")
source("R/RSV_analysis.R")
source("R/plot_all_models.R")
