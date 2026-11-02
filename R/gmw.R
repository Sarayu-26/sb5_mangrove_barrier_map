# Independent GMW display coverage; never clipped to the land-cover input footprint.
GMW_LABEL <- "Mangroves (GMW v3, 2020)"
load_gmw <- function(root="data/gmw") {
  path <- file.path(root,"index.rds")
  if (!file.exists(path)) stop("GMW data missing. Run Rscript scripts/prepare_gmw.R <downloaded ZIP>.")
  index <- readRDS(path)
  if (!all(file.exists(file.path(root,c(index$tiles$file,"overview.tif"))))) stop("Incomplete GMW data.")
  list(root=root,index=index,overview=terra::rast(file.path(root,"overview.tif")))
}

render_gmw <- function(gmw, bounds, max_dimension=768L) {
  stopifnot(length(bounds)==4L,all(is.finite(bounds)),bounds[2]>bounds[1],bounds[4]>bounds[3])
  step <- max(diff(bounds[1:2]),diff(bounds[3:4]))/max_dimension
  target <- terra::rast(xmin=bounds[1],xmax=bounds[2],ymin=bounds[3],ymax=bounds[4],
                        ncols=max(1L,ceiling(diff(bounds[1:2])/step)),
                        nrows=max(1L,ceiling(diff(bounds[3:4])/step)),crs="EPSG:4326")
  result <- rep(NA_real_,terra::ncell(target))
  b <- gmw$index$tiles
  selected <- which(b$xmax>bounds[1] & b$xmin<bounds[2] & b$ymax>bounds[3] & b$ymin<bounds[4])
  for (i in selected) {
    tile <- terra::rast(file.path(gmw$root,b$file[i]))
    tile <- terra::crop(tile,terra::ext(target),snap="out")
    # Max aggregation keeps narrow mangroves visible when zoomed out.
    warped <- terra::resample(tile,target,method="max")
    present <- which(terra::values(warped,mat=FALSE)==1)
    result[present] <- 1
  }
  terra::values(target) <- result
  target
}
