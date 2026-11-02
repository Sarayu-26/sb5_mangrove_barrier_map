# Run only after preparation and tests. No publication is performed here.
source("R/spatial.R")
p <- load_products()
files <- c("app.R","DESCRIPTION",list.files("R",full.names=TRUE),list.files("data/prepared",full.names=TRUE))
rsconnect::writeManifest(appDir=".",appFiles=files)
cat("Manifest written for",length(files),"files.\n")
