# Official GMW v3 2020 archive: https://zenodo.org/records/6894273
# Keep complete source tiles intersecting the region, including all Galapagos islands.
library(terra)
source("R/gmw.R")
args <- commandArgs(trailingOnly=TRUE)
if (length(args)!=1L) stop("Usage: Rscript scripts/prepare_gmw.R /path/to/gmw_v3_2020_gtiff.zip")
expected <- "c85f7528de7df83e5701f3b162ac37b4"
if (unname(tools::md5sum(args[1]))!=expected) stop("Archive checksum differs from the official GMW v3 2020 release.")
root <- "data/gmw"
if (dir.exists(root)) stop("Move existing data/gmw aside before rebuilding.")
workspace <- tempfile("gmw-"); dir.create(workspace)
unzip(args[1],exdir=workspace)
files <- list.files(workspace,pattern="\\.tif$",recursive=TRUE,full.names=TRUE)
if (!length(files)) stop("No TIFFs found in archive.")
dir.create(root,recursive=TRUE)
# Broad regional envelope, independent of TIFF inputs; full intersecting tiles retained.
bounds <- c(-96,-68,-20,12)
rows <- list()
for (file in files) {
  r <- rast(file); e <- as.vector(ext(r))
  if (e[2]<=bounds[1] || e[1]>=bounds[2] || e[4]<=bounds[3] || e[3]>=bounds[4]) next
  stopifnot(is.lonlat(r),nlyr(r)==1L)
  name <- basename(file)
  if (!file.copy(file,file.path(root,name))) stop("Cannot copy GMW tile.")
  rows[[length(rows)+1L]] <- data.frame(file=name,xmin=e[1],xmax=e[2],ymin=e[3],ymax=e[4])
}
index <- list(tiles=do.call(rbind,rows),bounds=bounds,year=2020L,version="3.0",
              source="https://zenodo.org/records/6894273",archive_md5=expected,
              license="CC BY 4.0",scope="Complete tiles intersecting 96W–68W, 20S–12N; includes neighboring coastlines")
index$tile_md5 <- tools::md5sum(file.path(root,index$tiles$file))
names(index$tile_md5) <- index$tiles$file
preview <- render_gmw(list(root=root,index=index),bounds)
writeRaster(preview,file.path(root,"overview.tif"),datatype="INT1U",NAflag=255,gdal="COMPRESS=DEFLATE")
saveRDS(index,file.path(root,"index.rds"))
unlink(workspace,recursive=TRUE)
message("Prepared ",nrow(index$tiles)," complete GMW tiles.")
