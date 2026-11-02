# Offline preparation. Run from the repository root; never invoked by Shiny.
library(terra)
library(sf)
source("R/spatial.R")
terraOptions(memmax=0.5, progress=0)
root <- "data/prepared"
if (file.exists(file.path(root,"index.rds"))) stop("Prepared data already exists. Move data/prepared aside before rebuilding.")
dir.create(root,recursive=TRUE,showWarnings=FALSE)
files <- sort(list.files("input",pattern="^worldcover_raw_5km_full-.*\\.tif$",full.names=TRUE))
if (length(files)!=8L) stop("Expected eight downloaded WorldCover tiles.")
boundaries <- rnaturalearth::ne_countries(scale="medium",returnclass="sf")
boundaries <- boundaries[match(unname(COUNTRIES),boundaries$name),]
if (any(is.na(boundaries$name))) stop("Missing country boundary.")
blocks <- list(); totals <- matrix(0,length(COUNTRIES),length(DEFAULTS),dimnames=list(names(COUNTRIES),names(DEFAULTS)))
all_bounds <- c(Inf,-Inf,Inf,-Inf); input_hashes <- character()
for (file in files) {
  message("Preparing ",basename(file))
  slope_file <- sub("worldcover_raw_5km_full","mangrove_barrier_5km_slope_full",file)
  raw <- rast(file); slope <- rast(slope_file)
  stopifnot(compareGeom(raw,slope),is.lonlat(raw),nlyr(raw)==1L)
  input_hashes <- c(input_hashes,tools::md5sum(c(file,slope_file)))
  # Geographic cells on each row have the same area; calculate only one column.
  strip <- rast(nrows=nrow(raw),ncols=1,xmin=xmin(raw),xmax=xmin(raw)+res(raw)[1],ymin=ymin(raw),ymax=ymax(raw),crs=crs(raw))
  row_area <- as.vector(values(cellSize(strip,unit="ha",transform=FALSE)))
  readStart(raw); readStart(slope)
  for (row in seq.int(1L,nrow(raw),by=128L)) {
    nr <- min(128L,nrow(raw)-row+1L)
    v <- readValues(raw,row=row,nrows=nr,mat=FALSE)
    sv <- readValues(slope,row=row,nrows=nr,mat=FALSE)
    supported <- v %in% as.integer(names(DEFAULTS))
    if (any(!is.na(v) & v != 0 & !supported)) stop("Unsupported land-cover class in ",file)
    if (any(sv %in% 1:3 & !supported)) stop("Slope cells lack land-cover data; update sparse schema before preparing.")
    if (any(!is.na(sv) & !sv %in% 0:3)) stop("Unsupported slope-reference class.")
    valid <- which(supported)
    if (!length(valid)) next
    cells <- (row-1)*ncol(raw)+valid
    xy <- xyFromCell(raw,cells)
    d <- data.frame(x=xy[,1],y=xy[,2],code=as.integer(v[valid]),slope=as.integer(sv[valid]),area_ha=row_area[rowFromCell(raw,cells)])
    country <- sf::st_intersects(sf::st_as_sf(d,coords=c("x","y"),crs=4326),boundaries)
    for (i in seq_along(COUNTRIES)) {
      keep <- vapply(country,function(z) i %in% z,logical(1))
      if (any(keep)) { a <- tapply(d$area_ha[keep],d$code[keep],sum); totals[i,names(a)] <- totals[i,names(a)]+a }
    }
    name <- sprintf("cells-%04d.rds",length(blocks)+1L)
    saveRDS(d,file.path(root,name),compress="gzip")
    b <- data.frame(file=name,xmin=min(d$x),xmax=max(d$x),ymin=min(d$y),ymax=max(d$y),cells=nrow(d))
    blocks[[length(blocks)+1L]] <- b
    all_bounds <- c(min(all_bounds[1],b$xmin),max(all_bounds[2],b$xmax),min(all_bounds[3],b$ymin),max(all_bounds[4],b$ymax))
  }
  readStop(raw); readStop(slope)
}
index <- list(version=1L,blocks=do.call(rbind,blocks),bounds=all_bounds,
              cell_resolution=res(raw),source_md5=input_hashes,prepared_at=format(Sys.time(),tz="UTC",usetz=TRUE),
              area_method="Geodesic cell area; center-in-polygon inclusion; input grid approximately 100 m")
summary <- expand.grid(country=rownames(totals),code=as.integer(colnames(totals)),stringsAsFactors=FALSE)
summary$area_ha <- as.vector(totals)
write.csv(summary,file.path(root,"countries.csv"),row.names=FALSE)
overview <- render_grid(list(root=root,index=index),all_bounds+c(-0.001,0.001,-0.001,0.001))
writeRaster(overview,file.path(root,"overview.tif"),datatype="INT1U",NAflag=255,gdal=c("COMPRESS=DEFLATE"),overwrite=TRUE)
# Publish completion marker last, so an interrupted build cannot start the app.
saveRDS(index,file.path(root,"index.rds"))
message("Prepared ",sum(index$blocks$cells)," populated cells in ",nrow(index$blocks)," blocks.")
