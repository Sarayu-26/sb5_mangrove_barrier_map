source("R/gmw.R")
# A single native cell must survive aggregation, independently of land-cover extent.
root <- tempfile(); dir.create(root)
r <- terra::rast(nrows=100,ncols=100,xmin=-92,xmax=-91,ymin=-1,ymax=0,crs="EPSG:4326")
terra::values(r) <- 0
r[5050] <- 1
terra::writeRaster(r,file.path(root,"tile.tif"))
fixture <- list(root=root,index=list(tiles=data.frame(file="tile.tif",xmin=-92,xmax=-91,ymin=-1,ymax=0)))
a <- render_gmw(fixture,c(-92,-91,-1,0),10L)
stopifnot(terra::ncell(a)==100,sum(terra::values(a)==1,na.rm=TRUE)>=1,
          all(is.na(terra::values(a)) | terra::values(a)==1))
empty <- render_gmw(fixture,c(10,11,10,11),10L)
stopifnot(all(is.na(terra::values(empty))))
unlink(root,recursive=TRUE)
# Real Galapagos coverage, including western islands outside the previous footprint.
gmw <- load_gmw()
stopifnot(identical(unname(tools::md5sum(file.path(gmw$root,gmw$index$tiles$file))),unname(gmw$index$tile_md5)))
gal <- render_gmw(gmw,c(-92.2,-89,-1.6,0.8))
stopifnot(any(terra::values(gal)==1,na.rm=TRUE),terra::ncell(gal)<=768^2)
western <- terra::crop(gal,terra::ext(-92.2,-91,-1.6,0.8))
stopifnot(any(terra::values(western)==1,na.rm=TRUE))
# Every study country has mapped coverage in a representative coastal window.
windows <- list(c(-86,-83,8,11),c(-83,-77,7,10),c(-79,-77,1,7),c(-81,-78,-4,1),c(-81,-80,-4,-3))
for (b in windows) stopifnot(any(terra::values(render_gmw(gmw,b,128L))==1,na.rm=TRUE))
cat("PASS: GMW source checksums, narrow-feature preservation, empty coverage, western Galapagos and five country windows.\n")
