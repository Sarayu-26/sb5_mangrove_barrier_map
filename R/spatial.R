# Runtime spatial operations use prepared, sparse cells, never the regional mosaics.
COUNTRIES <- c(costa_rica="Costa Rica", panama="Panama", colombia="Colombia", ecuador="Ecuador", peru="Peru")
LC_CLASSES <- c(`10`="Tree cover", `20`="Shrubland", `30`="Grassland", `40`="Cropland", `50`="Built-up", `60`="Bare / sparse veg", `80`="Permanent water", `90`="Herbaceous wetland", `100`="Moss / lichen")
DEFAULTS <- c(`10`=1, `20`=1, `30`=2, `40`=3, `50`=3, `60`=1, `80`=2, `90`=1, `95`=0, `100`=1)
BARRIER_COLORS <- c(`1`="#4ade80", `2`="#facc15", `3`="#f87171")

load_products <- function(root="data/prepared") {
  path <- file.path(root, "index.rds")
  if (!file.exists(path)) stop("Prepared data missing. Run Rscript scripts/prepare_data.R before starting Shiny.")
  index <- readRDS(path)
  if (!identical(index$version, 1L)) stop("Unsupported prepared-data version; rebuild products.")
  files <- c(index$blocks$file, "overview.tif", "countries.csv")
  if (!all(file.exists(file.path(root, files)))) stop("Incomplete prepared data; rebuild products.")
  list(root=root, index=index, overview=terra::rast(file.path(root,"overview.tif")),
       countries=read.csv(file.path(root,"countries.csv")))
}

polygon_geometry <- function(coords_json) {
  tryCatch({
    rings <- jsonlite::fromJSON(coords_json, simplifyVector=FALSE)
    rings <- lapply(rings, function(ring) {
      if (length(ring) < 4L) stop("A ring needs at least four coordinates.")
      m <- do.call(rbind, lapply(ring, function(p) {
        p <- as.numeric(unlist(p)); if (length(p)!=2L) stop("Invalid coordinate."); p
      }))
      if (any(!is.finite(m)) || any(abs(m[,1])>180) || any(abs(m[,2])>90)) stop("Invalid coordinate.")
      m
    })
    if (sum(vapply(rings,nrow,integer(1))) > 2000L) stop("Polygon is too complex (maximum 2,000 vertices).")
    p <- sf::st_sfc(sf::st_polygon(rings), crs=4326)
    if (!isTRUE(sf::st_is_valid(p))) stop("Draw a valid polygon without crossing edges.")
    p
  }, error=function(e) stop("Invalid polygon: ", conditionMessage(e), call.=FALSE))
}

visit_cells <- function(products, bounds, fn) {
  b <- products$index$blocks
  selected <- which(b$xmax>=bounds[1] & b$xmin<=bounds[2] & b$ymax>=bounds[3] & b$ymin<=bounds[4])
  for (i in selected) {
    d <- readRDS(file.path(products$root,b$file[i]))
    d <- d[d$x>=bounds[1] & d$x<=bounds[2] & d$y>=bounds[3] & d$y<=bounds[4],,drop=FALSE]
    if (nrow(d)) fn(d)
  }
  invisible(NULL)
}

polygon_areas <- function(products, geometry) {
  bb <- sf::st_bbox(geometry)
  sums <- setNames(numeric(length(DEFAULTS)), names(DEFAULTS))
  visit_cells(products,unname(bb[c(1,3,2,4)]), function(d) {
    # Center-in-polygon rule, including holes; reported areas are complete cell areas.
    pts <- sf::st_as_sf(d,coords=c("x","y"),crs=4326)
    keep <- lengths(sf::st_intersects(pts,geometry)) > 0L
    if (any(keep)) {
      a <- tapply(d$area_ha[keep], d$code[keep], sum)
      sums[names(a)] <<- sums[names(a)] + a
    }
  })
  data.frame(code=as.integer(names(sums)), area_ha=unname(sums))
}

classify_areas <- function(areas, classification) {
  d <- areas[as.character(areas$code) %in% names(LC_CLASSES) & areas$area_ha>0,,drop=FALSE]
  d$name <- unname(LC_CLASSES[as.character(d$code)])
  d$pct <- if (sum(d$area_ha)>0) 100*d$area_ha/sum(d$area_ha) else numeric(nrow(d))
  d$score <- unname(classification[as.character(d$code)])
  d$barrier <- c("Low","Medium","High")[d$score]
  d$color <- unname(BARRIER_COLORS[as.character(d$score)])
  d[order(-d$area_ha),,drop=FALSE]
}

# Fixed-size render grid; categorical counts are accumulated one disk block at a time.
render_grid <- function(products, bounds, max_dimension=768L) {
  stopifnot(length(bounds)==4L, all(is.finite(bounds)), bounds[2]>bounds[1], bounds[4]>bounds[3])
  step <- max(c((bounds[2]-bounds[1])/max_dimension, (bounds[4]-bounds[3])/max_dimension, products$index$cell_resolution))
  r <- terra::rast(xmin=bounds[1],xmax=bounds[2],ymin=bounds[3],ymax=bounds[4],
                   ncols=max(1,ceiling((bounds[2]-bounds[1])/step)),
                   nrows=max(1,ceiling((bounds[4]-bounds[3])/step)),crs="EPSG:4326")
  codes <- as.integer(names(DEFAULTS)); n <- terra::ncell(r)
  lc <- matrix(0L,n,length(codes)); slope <- matrix(0L,n,3L)
  visit_cells(products,bounds,function(d) {
    cell <- terra::cellFromXY(r,as.matrix(d[,c("x","y")]))
    k <- match(d$code,codes); ok <- !is.na(cell) & !is.na(k)
    lc[] <<- lc + matrix(tabulate(cell[ok]+(k[ok]-1L)*n,nbins=n*length(codes)),n)
    ok <- !is.na(cell) & d$slope %in% 1:3
    slope[] <<- slope + matrix(tabulate(cell[ok]+(d$slope[ok]-1L)*n,nbins=n*3L),n)
  })
  raw <- codes[max.col(lc,ties.method="first")]; raw[rowSums(lc)==0] <- NA
  sl <- max.col(slope,ties.method="first"); sl[rowSums(slope)==0] <- NA
  mang <- ifelse(lc[,match(95L,codes)]>0,1,NA)
  out <- c(r,r,r); terra::values(out) <- cbind(raw,sl,mang)
  names(out) <- c("landcover","slope","mangrove"); out
}
