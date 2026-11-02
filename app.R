library(shiny)
library(leaflet)
library(terra)
library(raster)
library(leaflet.extras)
library(dplyr)
library(sf)
library(jsonlite)
library(png)
library(rnaturalearth)

# ── 1. Load & prepare rasters ─────────────────────────────────────────────────

countries <- c("costa_rica", "panama", "colombia", "ecuador", "peru")
country_labels <- c(
  costa_rica = "Costa Rica",
  panama     = "Panama",
  colombia   = "Colombia (Pacific)",
  ecuador    = "Ecuador",
  peru       = "Peru"
)

# Country boundary polygons for accurate masking (loaded once at startup)
ne_names <- c("Costa Rica", "Panama", "Colombia", "Ecuador", "Peru")
country_polys <- setNames(lapply(ne_names, function(nm) {
  sf_poly <- ne_countries(country = nm, scale = "medium", returnclass = "sf")
  terra::vect(sf_poly)
}), countries)

load_full <- function(prefix, agg_fun="modal") {
  files <- sort(list.files("input", pattern=paste0("^", prefix, "-[0-9]"), full.names=TRUE))
  if (length(files) == 0) stop(paste("No tiles found for:", prefix))
  message("  Found ", length(files), " tiles for ", prefix)
  r <- if (length(files) > 1) mosaic(sprc(lapply(files, rast)), fun="first") else rast(files[1])
  r[r == 0] <- NA
  r <- project(r, "EPSG:4326")
  aggregate(r, fact=5, fun=agg_fun)
}

# Load raw tiles once at full resolution, derive all products from it
load_full_hires <- function(prefix) {
  files <- sort(list.files("input", pattern=paste0("^", prefix, "-[0-9]"), full.names=TRUE))
  if (length(files) == 0) stop(paste("No tiles found for:", prefix))
  message("  Found ", length(files), " tiles for ", prefix)
  r <- if (length(files) > 1) mosaic(sprc(lapply(files, rast)), fun="first") else rast(files[1])
  r[r == 0] <- NA
  project(r, "EPSG:4326")
}

message("Loading rasters...")
raw_hires    <- load_full_hires("worldcover_raw_5km_full")
slope_hires  <- load_full_hires("mangrove_barrier_5km_slope_full")

# Aggregate to ~500m for barrier map display and polygon classification
raw_mosaic   <- aggregate(raw_hires,   fact=5, fun="modal")
slope_mosaic <- aggregate(slope_hires, fact=5, fun="modal")

# Free slope hires immediately — only needed for slope_mosaic
rm(slope_hires); gc()

# ── 2. Constants ──────────────────────────────────────────────────────────────

LC_CLASSES <- c(
  "10"  = "Tree cover",
  "20"  = "Shrubland",
  "30"  = "Grassland",
  "40"  = "Cropland",
  "50"  = "Built-up",
  "60"  = "Bare / sparse veg",
  "80"  = "Permanent water",
  "90"  = "Herbaceous wetland",
  "100" = "Moss / lichen"
)

DEFAULTS <- c(`10`=1,`20`=1,`30`=2,`40`=3,`50`=3,
              `60`=1,`80`=2,`90`=1,`95`=0,`100`=1)

BARRIER_COLORS <- c("1"="#4ade80","2"="#facc15","3"="#f87171")
PIXEL_AREA_HA  <- (500*500)/10000   # after fact=5 aggregation, pixels are ~500m

barrier_pal <- colorFactor(
  palette  = c("#4ade80","#facc15","#f87171"),
  domain   = c(1,2,3),
  na.color = "transparent"
)

mangrove_pal <- colorFactor(
  palette  = "#166534",
  domain   = 1,
  na.color = "transparent"
)

# ── 3. Helpers ────────────────────────────────────────────────────────────────

reclassify_raster <- function(r, cls_map) {
  from <- as.numeric(names(cls_map))
  to   <- as.numeric(cls_map)
  rcl  <- matrix(c(from, to), ncol=2)
  classify(r, rcl, others=NA)
}

# Pre-render a terra SpatRaster to a cached Raster object for leaflet
# Cache lives in memory keyed by a string tag; reclassified layers use
# the serialised cls_map as their key so the map only redraws on real changes.
raster_cache <- new.env(hash=TRUE, parent=emptyenv())

get_cached_raster <- function(key, make_fn) {
  if (!exists(key, envir=raster_cache)) {
    assign(key, make_fn(), envir=raster_cache)
  }
  get(key, envir=raster_cache)
}

# No aggregation — mangroves are thin coastal strips, any aggregation loses them
mangrove_mosaic <- ifel(raw_hires == 95, 1, NA)

# Free raw_hires — mangrove_mosaic and raw_mosaic are all we need
rm(raw_hires); gc()

# Pre-cache mosaicked rasters for leaflet (static, built once at startup)
message("Pre-caching mosaicked rasters...")
slope_rl    <- get_cached_raster("slope_mosaic",    function() as(slope_mosaic,    "Raster"))
mangrove_rl <- get_cached_raster("mangrove_mosaic", function() as(mangrove_mosaic, "Raster"))

message("Startup complete.")

# ── 4. Annotation persistence ─────────────────────────────────────────────────

ANNOTATIONS_FILE <- "input/annotations.csv"

load_annotations <- function() {
  if (file.exists(ANNOTATIONS_FILE)) {
    read.csv(ANNOTATIONS_FILE, stringsAsFactors=FALSE)
  } else {
    data.frame(id=character(), map=character(), type=character(),
               coords_json=character(), label=character(),
               timestamp=character(), stringsAsFactors=FALSE)
  }
}

save_annotation <- function(map_id, type, coords, label="") {
  ann <- load_annotations()
  new_row <- data.frame(
    id          = as.character(Sys.time()),
    map         = map_id,
    type        = type,
    coords_json = jsonlite::toJSON(coords),
    label       = label,
    timestamp   = as.character(Sys.time()),
    stringsAsFactors = FALSE
  )
  write.csv(rbind(ann, new_row), ANNOTATIONS_FILE, row.names=FALSE)
}

draw_saved_annotations <- function(proxy, map_id) {
  ann <- load_annotations()
  ann <- ann[ann$map == map_id, ]
  if (nrow(ann) == 0) return()
  for (i in seq_len(nrow(ann))) {
    coords <- tryCatch(jsonlite::fromJSON(ann$coords_json[i]), error=function(e) NULL)
    if (is.null(coords)) next
    tryCatch({
      if (ann$type[i] %in% c("Polygon", "Rectangle")) {
        ring <- coords[[1]]
        lngs <- sapply(ring, `[[`, 1)
        lats <- sapply(ring, `[[`, 2)
        proxy %>% addPolygons(
          lng         = lngs,
          lat         = lats,
          group       = "drawn",
          color       = "#facc15",
          weight      = 2,
          fillOpacity = 0.1,
          layerId     = paste0("saved_", map_id, "_", i)
        )
      }
    }, error = function(e) NULL)
  }
}

# Extract pixel values inside a drawn polygon from a SpatRaster
poly_to_vect <- function(coords_json) {
  coords <- tryCatch(jsonlite::fromJSON(coords_json, simplifyVector=FALSE), error=function(e) NULL)
  if (is.null(coords)) return(NULL)
  ring <- tryCatch({ r <- coords; while (is.list(r) && is.list(r[[1]])) r <- r[[1]]; r }, error=function(e) NULL)
  if (is.null(ring) || length(ring) < 3) return(NULL)
  lngs <- tryCatch(sapply(ring, function(p) p[[1]]), error=function(e) NULL)
  lats <- tryCatch(sapply(ring, function(p) p[[2]]), error=function(e) NULL)
  if (is.null(lngs) || is.null(lats)) return(NULL)
  poly_sf <- tryCatch(sf::st_sfc(sf::st_polygon(list(cbind(lngs, lats))), crs=4326), error=function(e) NULL)
  if (is.null(poly_sf)) return(NULL)
  tryCatch(terra::vect(poly_sf), error=function(e) NULL)
}

extract_mangrove_ha <- function(coords_json) {
  poly_sv <- poly_to_vect(coords_json)
  if (is.null(poly_sv)) return(NA)
  extracted <- tryCatch(terra::extract(mangrove_mosaic, poly_sv), error=function(e) NULL)
  if (is.null(extracted) || ncol(extracted) < 2) return(0)
  pixels <- sum(extracted[,2] == 1, na.rm=TRUE)
  round(pixels * PIXEL_AREA_HA)
}

extract_polygon_stats <- function(terra_raster, coords_json, cls_map) {
  poly_sv   <- poly_to_vect(coords_json)
  if (is.null(poly_sv)) return(NULL)
  extracted <- tryCatch(terra::extract(terra_raster, poly_sv), error=function(e) NULL)
  if (is.null(extracted) || ncol(extracted) < 2) return(NULL)
  vals <- tryCatch(extracted[,2], error=function(e) NULL)
  if (is.null(vals)) return(NULL)
  vals <- vals[!is.na(vals) & vals != 0 & vals != 95]
  if (length(vals) == 0) return(NULL)
  lc_df <- as.data.frame(table(vals)) %>%
    rename(code=vals, pixels=Freq) %>%
    mutate(
      code    = as.numeric(as.character(code)),
      name    = LC_CLASSES[as.character(code)],
      area_ha = round(pixels * PIXEL_AREA_HA),
      pct     = round(pixels / sum(pixels) * 100, 1),
      score   = cls_map[as.character(code)],
      barrier = c("1"="Low","2"="Medium","3"="High")[as.character(score)]
    ) %>%
    filter(!is.na(name)) %>%
    arrange(desc(pixels))
  lc_df
}

# ── 5. UI ─────────────────────────────────────────────────────────────────────

ui <- fluidPage(
  tags$head(tags$style(HTML("
    @import url('https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600&family=DM+Mono:wght@400;500&display=swap');
    body { font-family:'DM Sans',sans-serif; background:#0e1a14; color:#e2ead4; margin:0; padding:0; }
    h1 { font-size:15px; font-weight:600; color:#4ade80; margin:0; }
    .subtitle { font-size:11px; color:#7a9a7a; font-family:'DM Mono',monospace; margin-top:2px; }
    .wip-badge { font-family:'DM Mono',monospace; font-size:10px; background:rgba(122,79,0,0.1);
                 border:1px solid rgba(250,204,21,0.25); color:#facc15; padding:3px 10px;
                 border-radius:20px; letter-spacing:0.08em; }
    .header-bar { background:#162019; border-bottom:1px solid #2a3d2e; padding:10px 20px;
                  display:flex; align-items:center; justify-content:space-between; }
    .nav-tabs { background:#162019 !important; border-bottom:1px solid #2a3d2e !important; padding-left:10px; }
    .nav-tabs > li > a { color:#7a9a7a !important; font-size:12px; font-weight:500;
                         background:none !important; border:none !important;
                         border-bottom:2px solid transparent !important; }
    .nav-tabs > li.active > a, .nav-tabs > li.active > a:hover {
      color:#4ade80 !important; border-bottom:2px solid #4ade80 !important;
      background:#1f3328 !important; }
    .tab-content { background:#0e1a14; }
    .sidebar-panel { background:#162019; border-right:1px solid #2a3d2e;
                     padding:14px; height:calc(100vh - 90px); overflow-y:auto;
                     width:260px; float:left; }
    .map-panel { margin-left:260px; height:calc(100vh - 90px); }
    .section-label { font-size:10px; font-weight:600; letter-spacing:0.12em;
                     text-transform:uppercase; color:#7a9a7a; margin-bottom:10px; margin-top:14px; }
    .legend-item { display:flex; align-items:center; gap:8px; margin-bottom:7px; font-size:12px; }
    .legend-dot { width:12px; height:12px; border-radius:2px; flex-shrink:0; }
    .class-row { background:#1a2b1e; border:1px solid #2a3d2e; border-radius:5px;
                 padding:7px 9px; margin-bottom:8px; }
    .class-row label { font-size:11px; display:block; margin-bottom:4px; font-weight:500; }
    .class-code { font-family:'DM Mono',monospace; font-size:9px; color:#7a9a7a; margin-left:3px; }
    .class-row .form-group { margin-bottom:0; }
    .class-row select { width:100%; background:#0e1a14; border:1px solid #2a3d2e;
                        color:#e2ead4; font-size:11px; padding:3px 5px; border-radius:3px; }
    .reset-btn { width:100%; margin-top:10px; padding:6px; background:none;
                 border:1px solid #2a3d2e; color:#7a9a7a; font-size:11px;
                 border-radius:4px; cursor:pointer; }
    .dl-btn { width:100%; margin-top:6px; padding:6px; background:rgba(74,222,128,0.08);
              border:1px solid rgba(74,222,128,0.25); color:#4ade80; font-size:11px;
              border-radius:4px; cursor:pointer; font-family:'DM Sans',sans-serif; }
    .dl-btn:disabled { opacity:0.35; cursor:default; }
    .poly-stats { background:#1a2b1e; border:1px solid #2a3d2e; border-radius:5px;
                  padding:10px; margin-top:8px; font-size:11px; }
    .stats-wrap { padding:24px; overflow-y:auto; height:calc(100vh - 90px); }
    .stats-grid { display:grid; grid-template-columns:1fr 1fr; gap:18px; margin-bottom:20px; }
    .stats-card { background:#162019; border:1px solid #2a3d2e; border-radius:7px; padding:14px; }
    .stats-card h4 { font-size:10px; font-weight:600; letter-spacing:0.1em;
                     text-transform:uppercase; color:#7a9a7a; margin-bottom:12px; }
    .country-tag { font-family:'DM Mono',monospace; font-size:9px; padding:2px 6px;
                   background:rgba(74,222,128,0.08); border:1px solid rgba(74,222,128,0.2);
                   border-radius:2px; color:#4ade80; float:right; }
    .note-box { background:rgba(122,79,0,0.06); border:1px solid rgba(250,204,21,0.2);
                border-radius:5px; padding:10px 14px; font-size:11px; color:#7a9a7a;
                line-height:1.6; margin-bottom:16px; }
    .note-box strong { color:#facc15; }
    table.stats-tbl { width:100%; border-collapse:collapse; font-size:11px; }
    table.stats-tbl th { text-align:left; font-size:10px; color:#7a9a7a; padding:3px 6px;
                         border-bottom:1px solid #2a3d2e; font-family:'DM Mono',monospace; font-weight:400; }
    table.stats-tbl td { padding:5px 6px; border-bottom:1px solid #1e2e22; }
    table.stats-tbl tr:last-child td { border-bottom:none; }
    .divider { border-top:1px solid #2a3d2e; margin:12px 0; }
    .leaflet-container { background:#0e1a14 !important; }
    .form-group { margin-bottom:0 !important; }
    .about-wrap { padding:32px 48px; max-width:860px; overflow-y:auto; height:calc(100vh - 90px); }
    .about-wrap h2 { font-size:22px; font-weight:600; color:#4ade80; margin-bottom:4px; }
    .about-wrap h3 { font-size:12px; font-weight:600; letter-spacing:0.12em; text-transform:uppercase;
                     color:#7a9a7a; margin-top:28px; margin-bottom:10px; border-bottom:1px solid #2a3d2e;
                     padding-bottom:6px; }
    .about-wrap p { font-size:13px; line-height:1.75; color:#c8d8c0; margin-bottom:12px; }
    .about-wrap a { color:#4ade80; text-decoration:none; }
    .about-wrap a:hover { text-decoration:underline; }
    .about-tbl { width:100%; border-collapse:collapse; font-size:12px; margin-bottom:16px; }
    .about-tbl th { text-align:left; font-size:10px; color:#7a9a7a; padding:4px 10px;
                    border-bottom:1px solid #2a3d2e; font-family:'DM Mono',monospace; font-weight:400; }
    .about-tbl td { padding:7px 10px; border-bottom:1px solid #1e2e22; color:#c8d8c0; }
    .about-tbl tr:last-child td { border-bottom:none; }
    .step-row { display:flex; gap:14px; margin-bottom:12px; align-items:flex-start; }
    .step-num { font-family:'DM Mono',monospace; font-size:11px; color:#4ade80;
                background:rgba(74,222,128,0.08); border:1px solid rgba(74,222,128,0.2);
                border-radius:3px; padding:2px 7px; flex-shrink:0; margin-top:2px; }
    .step-text { font-size:13px; line-height:1.6; color:#c8d8c0; }
    .step-text strong { color:#e2ead4; }
    .cite { font-family:'DM Mono',monospace; font-size:10px; color:#7a9a7a; line-height:1.8; }
    .status-bar { display:flex; gap:10px; align-items:center; margin-top:28px;
                  padding:10px 14px; background:#162019; border:1px solid #2a3d2e; border-radius:6px; }
    .status-dot { width:8px; height:8px; border-radius:50%; background:#facc15; flex-shrink:0; }
  "))),
  
  div(class="header-bar",
      div(
        h1("Mangrove Migration Barriers — Eastern Tropical Pacific"),
        div(class="subtitle",
            "Costa Rica · Panama · Colombia · Ecuador · Peru  |  5km coastal buffer · ESA WorldCover 2021 · GMW v3 2020")
      ),
      span(class="wip-badge", "WORK IN PROGRESS")
  ),
  
  tabsetPanel(id="main_tabs",
              
              # ── Tab 0: About ──────────────────────────────────────────────────────────
              tabPanel("About",
                       div(class="about-wrap",
                           
                           h2("Mangrove Migration Barriers — Eastern Tropical Pacific"),
                           p(style="font-family:'DM Mono',monospace;font-size:11px;color:#7a9a7a;margin-bottom:24px",
                             "Conservation International · SB5 Climate Adaptation · October 2026"),
                           
                           tags$h3("What this tool shows"),
                           p("Mangroves are highly productive coastal ecosystems that provide storm protection, carbon storage,
          and fisheries habitat. Under sea-level rise, mangroves can survive by migrating landward — but only
          if suitable land is available inland."),
                           p("This tool maps ", tags$strong("potential barriers to landward mangrove migration"), " along the
          Eastern Tropical Pacific coast (Costa Rica, Panama, Colombia, Ecuador, Peru). It classifies land
          use within a ", tags$strong("5 km inland buffer"), " of current mangrove extent using ESA WorldCover
          satellite data, then assigns each pixel a barrier score based on how likely that land use is to
          prevent migration."),
                           p("Terrain steepness is included: land rising more than 5° behind the coast is always classified
          as High barrier regardless of land cover, since mangroves cannot migrate uphill."),
                           
                           tags$h3("Barrier classification"),
                           tags$table(class="about-tbl",
                                      tags$thead(tags$tr(
                                        tags$th("Score"), tags$th("Label"), tags$th("Land cover classes (default)")
                                      )),
                                      tags$tbody(
                                        tags$tr(tags$td(style="color:#4ade80","Low"),    tags$td("Low barrier"),
                                                tags$td("Tree cover, Shrubland, Bare / sparse veg, Herbaceous wetland, Moss / lichen")),
                                        tags$tr(tags$td(style="color:#facc15","Medium"), tags$td("Medium barrier"),
                                                tags$td("Grassland, Permanent water")),
                                        tags$tr(tags$td(style="color:#f87171","High"),   tags$td("High barrier"),
                                                tags$td("Cropland, Built-up area")),
                                        tags$tr(tags$td(style="color:#166534","—"),      tags$td("Mangrove (excluded)"),
                                                tags$td("ESA class 95 — shown separately as current extent"))
                                      )
                           ),
                           p(style="font-size:11px;color:#7a9a7a;",
                             "Default scores reflect expert judgment and can be adjusted in real time using the dropdowns
           on the 5km Land Cover tab. Reclassify grassland as High barrier if cattle ranching is the
           dominant land use in your area of interest."),
                           
                           tags$h3("How to use it"),
                           div(class="step-row",
                               div(class="step-num", "01"),
                               div(class="step-text", tags$strong("Select a country"), " — the maps show all five countries
              simultaneously at zoom 5; pan and zoom into your region of interest.")
                           ),
                           div(class="step-row",
                               div(class="step-num", "02"),
                               div(class="step-text", tags$strong("Adjust barrier scores"), " — use the dropdowns in the
              Tab 1 sidebar to reclassify land cover types for your context. The map updates live.")
                           ),
                           div(class="step-row",
                               div(class="step-num", "03"),
                               div(class="step-text", tags$strong("Draw a polygon"), " — use the draw tool (pentagon icon)
              on either map to outline your area of interest. Summary statistics appear in the sidebar.")
                           ),
                           div(class="step-row",
                               div(class="step-num", "04"),
                               div(class="step-text", tags$strong("Download stats"), " — click ", tags$em("Download polygon
              stats (.csv)"), " to export area (ha) and percentage by land cover class for your polygon.")
                           ),
                           div(class="step-row",
                               div(class="step-num", "05"),
                               div(class="step-text", tags$strong("Check the Statistics tab"), " — see full land cover
              breakdowns by country for the entire 5km coastal buffer.")
                           ),
                           
                           tags$h3("Data sources"),
                           div(class="cite",
                               div("ESA WorldCover 2021 v200 (10m) · ", tags$a(href="https://worldcover2021.esa.int","worldcover2021.esa.int")),
                               div("Global Mangrove Watch v3.0 (2020) · ", tags$a(href="https://www.jaxa.jp/projects/sat/alos2/","JAXA / Aberystwyth University")),
                               div("SRTM 30m Digital Elevation Model · NASA / USGS"),
                               div("Coastal buffer and slope composite processed in Google Earth Engine · aggregated to ~500m for display")
                           ),
                           
                           tags$h3("Known limitations"),
                           p("Grassland (ESA class 30) is classified as Medium barrier by default but may include cleared
          cattle pasture, which is a de-facto High barrier. A Human Modification Index overlay to
          distinguish natural grassland from agricultural conversion is planned."),
                           p("The 5km buffer is a conservative inland distance. Mangrove migration potential also depends
          on elevation gradients, soil salinity and freshwater inflow, which are not yet included."),
                           p("Annotation polygons drawn on the map persist for the current server session only and reset
          on redeployment."),
                           
                           div(class="status-bar",
                               div(class="status-dot"),
                               div(style="font-size:11px;color:#7a9a7a;font-family:'DM Mono',monospace",
                                   "Work in progress · Conservation International SB5 · October 2026")
                           )
                       )
              ),
              
              # ── Tab 1: Barrier Map (land cover + slope) ───────────────────────────────
              tabPanel("Barrier Map",
                       div(style="position:relative;",
                           div(class="sidebar-panel",
                               
                               div(class="section-label", "Legend"),
                               div(class="legend-item", div(class="legend-dot",style="background:#166534"), "Mangroves (GMW 2020)"),
                               div(class="legend-item", div(class="legend-dot",style="background:#4ade80"), "Low barrier"),
                               div(class="legend-item", div(class="legend-dot",style="background:#facc15"), "Medium barrier"),
                               div(class="legend-item", div(class="legend-dot",style="background:#f87171"), "High barrier (incl. slope >5°)"),
                               
                               div(class="section-label", style="margin-top:16px", "Reclassify land cover"),
                               p(style="font-size:10px;color:#7a9a7a;margin-bottom:10px;line-height:1.5",
                                 "Adjust barrier scores per class. Slope >5° is always High. Map updates live."),
                               
                               lapply(names(LC_CLASSES), function(code) {
                                 div(class="class-row",
                                     tags$label(LC_CLASSES[code], tags$span(class="class-code", paste0("#",code))),
                                     selectInput(
                                       inputId  = paste0("lc_",code),
                                       label    = NULL,
                                       choices  = c("Low barrier"=1,"Medium barrier"=2,"High barrier"=3),
                                       selected = DEFAULTS[code],
                                       width    = "100%"
                                     )
                                 )
                               }),
                               
                               actionButton("reset_btn", "Reset to defaults", class="reset-btn"),
                               
                               div(class="section-label", style="margin-top:16px", "Draw & Export"),
                               p(style="font-size:10px;color:#7a9a7a;line-height:1.5;margin-bottom:8px",
                                 "Draw a polygon to see land cover breakdown for that area."),
                               
                               uiOutput("poly_stats_slope"),
                               
                               downloadButton("dl_poly_slope", "Download polygon stats (.csv)",
                                              class="dl-btn", style="margin-top:8px")
                           ),
                           div(class="map-panel",
                               leafletOutput("map_slope", height="calc(100vh - 90px)")
                           )
                       )
              ),
              
              # ── Tab 3: Statistics ─────────────────────────────────────────────────────
              tabPanel("Statistics",
                       div(class="stats-wrap",
                           h2(style="font-size:16px;font-weight:600;color:#4ade80;margin-bottom:4px",
                              "Land Cover Statistics — 5km Coastal Buffer"),
                           p(style="font-size:12px;color:#7a9a7a;font-family:'DM Mono',monospace;margin-bottom:16px",
                             "Pixel counts from raw WorldCover classes · ~500m resolution after aggregation · Pacific coast only"),
                           div(class="note-box",
                               tags$strong("How to use:"),
                               " These totals cover the full 5km buffer per country. For site-specific stats,
            draw a polygon on the Barrier Map tab and download the CSV from the sidebar."
                           ),
                           uiOutput("stats_cards"),
                           div(class="note-box",
                               tags$strong("Known limitation:"),
                               " Grassland (#30) = Medium barrier — may include cleared cattle pasture (High).
            Human Modification Index integration pending."
                           )
                       )
              )
  )
)

# ── 6. Server ─────────────────────────────────────────────────────────────────

server <- function(input, output, session) {
  
  # Current classification from dropdowns
  current_cls <- reactive({
    cls <- DEFAULTS
    for (code in names(LC_CLASSES)) {
      val <- input[[paste0("lc_",code)]]
      if (!is.null(val)) cls[code] <- as.numeric(val)
    }
    cls
  })
  
  # Debounced classification — waits 600ms after last dropdown change before firing
  current_cls_d <- debounce(current_cls, 600)
  
  # Cache key for current classification — only redraws when dropdowns actually change
  cls_key <- reactive({ paste(current_cls_d(), collapse="-") })
  
  # Reset button
  observeEvent(input$reset_btn, {
    for (code in names(LC_CLASSES)) {
      updateSelectInput(session, paste0("lc_",code), selected=DEFAULTS[code])
    }
  })
  
  # Reactive: last drawn polygon coords_json
  last_poly_slope <- reactiveVal(NULL)
  
  # ── Barrier Map (slope composite) ───────────────────────────────────────────
  output$map_slope <- renderLeaflet({
    m <- leaflet(options=leafletOptions(zoomControl=TRUE)) %>%
      addProviderTiles(providers$Esri.WorldGrayCanvas) %>%
      setView(lng=-80, lat=4, zoom=5) %>%
      addDrawToolbar(
        targetGroup         = "drawn",
        polylineOptions     = FALSE,
        circleOptions       = FALSE,
        circleMarkerOptions = FALSE,
        rectangleOptions    = FALSE,
        markerOptions       = FALSE,
        polygonOptions      = drawPolygonOptions(
          shapeOptions = drawShapeOptions(color="#facc15", fillOpacity=0.1)
        ),
        editOptions = editToolbarOptions(selectedPathOptions = selectedPathOptions())
      ) %>%
      addLayersControl(
        overlayGroups = "drawn",
        options       = layersControlOptions(collapsed=FALSE)
      )
    
    m <- m %>% addRasterImage(slope_rl,    colors=barrier_pal,  opacity=0.8, layerId="slope_mosaic")
    m <- m %>% addRasterImage(mangrove_rl, colors=mangrove_pal, opacity=1,   layerId="mang_mosaic", maxBytes=256*1024*1024)
    m %>% addLegend(
      position = "bottomright",
      colors   = c("#166534","#4ade80","#facc15","#f87171"),
      labels   = c("Mangroves","Low barrier","Medium barrier","High barrier (incl. slope)"),
      title    = "Migration Barrier", opacity=0.9
    )
  })
  
  observeEvent(input$map_slope_draw_new_feature, {
    f <- input$map_slope_draw_new_feature
    if (f$geometry$type == "Polygon") {
      last_poly_slope(jsonlite::toJSON(f$geometry$coordinates))
      save_annotation("map_slope", "Polygon", f$geometry$coordinates)
    }
  })
  
  observeEvent(input$map_slope_draw_deleted_features, {
    last_poly_slope(NULL)
  })
  
  # Polygon stats panel — land cover breakdown with current classification
  output$poly_stats_slope <- renderUI({
    coords_json <- last_poly_slope()
    if (is.null(coords_json)) {
      return(p(style="font-size:10px;color:#7a9a7a;font-style:italic",
               "No polygon drawn yet."))
    }
    cls      <- current_cls_d()
    df       <- extract_polygon_stats(raw_mosaic, coords_json, cls)
    mang_ha  <- extract_mangrove_ha(coords_json)
    if (is.null(df) || nrow(df) == 0) {
      return(p(style="font-size:10px;color:#7a9a7a", "No barrier pixels in polygon."))
    }
    div(class="poly-stats",
        p(style="font-size:10px;color:#4ade80;margin-bottom:6px;font-weight:600",
          "Land cover inside polygon:"),
        tags$table(class="stats-tbl",
                   tags$thead(tags$tr(tags$th("Class"), tags$th("Area (ha)"), tags$th("Barrier"))),
                   tags$tbody(
                     lapply(seq_len(nrow(df)), function(i) {
                       row   <- df[i,]
                       color <- BARRIER_COLORS[as.character(row$score)]
                       if (is.na(color)) color <- "#7a9a7a"
                       tags$tr(
                         tags$td(row$name),
                         tags$td(style="font-family:'DM Mono',monospace", format(row$area_ha, big.mark=",")),
                         tags$td(style=paste0("color:",color), row$barrier)
                       )
                     }),
                     if (!is.na(mang_ha) && mang_ha > 0)
                       tags$tr(
                         tags$td(style="color:#166534", "Mangrove (GMW 2020)"),
                         tags$td(style="font-family:'DM Mono',monospace", format(mang_ha, big.mark=",")),
                         tags$td(style="color:#166534", "—")
                       )
                   )
        )
    )
  })
  
  # Download polygon stats — land cover breakdown
  output$dl_poly_slope <- downloadHandler(
    filename = function() paste0("polygon_stats_", format(Sys.time(),"%Y%m%d_%H%M"), ".csv"),
    content  = function(file) {
      coords_json <- last_poly_slope()
      if (is.null(coords_json)) {
        write.csv(data.frame(note="No polygon drawn"), file, row.names=FALSE)
        return()
      }
      cls     <- current_cls_d()
      results <- extract_polygon_stats(raw_mosaic, coords_json, cls)
      if (is.null(results) || nrow(results) == 0) {
        write.csv(data.frame(note="No barrier pixels found in polygon"), file, row.names=FALSE)
      } else {
        write.csv(results[, c("name","area_ha","pct","barrier")], file, row.names=FALSE)
      }
    }
  )
  
  # ── Tab 3: Country-level stats ───────────────────────────────────────────────
  output$stats_cards <- renderUI({
    cls <- current_cls_d()
    # Total regional mangrove for % calculation
    total_mang_ha <- round(sum(values(mangrove_mosaic) == 1, na.rm=TRUE) * PIXEL_AREA_HA)
    
    cards <- lapply(countries, function(ctry) {
      poly  <- country_polys[[ctry]]
      r     <- mask(crop(raw_mosaic,      poly), poly)
      vals  <- as.vector(values(r))
      vals  <- vals[!is.na(vals) & vals != 0]
      
      mang_r      <- mask(crop(mangrove_mosaic, poly), poly)
      mang_pixels <- sum(values(mang_r) == 1, na.rm=TRUE)
      mang_ha     <- round(mang_pixels * PIXEL_AREA_HA)
      mang_pct    <- if (total_mang_ha > 0) round(mang_ha / total_mang_ha * 100, 1) else 0
      
      lc_counts <- as.data.frame(table(vals)) %>%
        rename(code=vals, pixels=Freq) %>%
        mutate(
          code    = as.numeric(as.character(code)),
          name    = LC_CLASSES[as.character(code)],
          area_ha = round(pixels * PIXEL_AREA_HA),
          pct     = round(pixels / sum(pixels) * 100, 1),
          score   = cls[as.character(code)],
          color   = BARRIER_COLORS[as.character(score)]
        ) %>%
        filter(!is.na(name)) %>%
        arrange(desc(pixels))
      
      barrier_counts <- lc_counts %>%
        filter(!is.na(score) & score > 0) %>%
        group_by(score) %>%
        summarise(area_ha=sum(area_ha), .groups="drop")
      total_barrier <- sum(barrier_counts$area_ha)
      
      lc_rows <- lapply(seq_len(nrow(lc_counts)), function(i) {
        row   <- lc_counts[i,]
        color <- if (!is.na(row$color)) row$color else "#4a5a4e"
        tags$tr(
          tags$td(style=paste0("color:",color), row$name),
          tags$td(style="font-family:'DM Mono',monospace", format(row$area_ha, big.mark=",")),
          tags$td(style="font-family:'DM Mono',monospace;color:#7a9a7a", paste0(row$pct,"%"))
        )
      })
      
      barrier_rows <- lapply(list(
        list(label="Low",    score=1, color="#4ade80"),
        list(label="Medium", score=2, color="#facc15"),
        list(label="High",   score=3, color="#f87171")
      ), function(b) {
        ha  <- barrier_counts$area_ha[barrier_counts$score == b$score]
        ha  <- if (length(ha)==0) 0 else ha
        pct <- if (total_barrier>0) round(ha/total_barrier*100,1) else 0
        tags$tr(
          tags$td(style=paste0("color:",b$color), b$label),
          tags$td(style="font-family:'DM Mono',monospace", format(ha, big.mark=",")),
          tags$td(style="font-family:'DM Mono',monospace;color:#7a9a7a", paste0(pct,"%"))
        )
      })
      
      div(class="stats-card",
          h4("Land Cover Breakdown", span(class="country-tag", country_labels[ctry])),
          tags$table(class="stats-tbl",
                     tags$thead(tags$tr(tags$th("Class"),tags$th("Area (ha)"),tags$th("%"))),
                     tags$tbody(lc_rows)),
          div(class="divider"),
          h4(style="margin-bottom:10px","Barrier Summary",
             span(style="font-size:9px;color:#7a9a7a;font-weight:400;margin-left:6px",
                  "(updates with Tab 1 dropdowns)")),
          tags$table(class="stats-tbl",
                     tags$thead(tags$tr(tags$th("Barrier"),tags$th("Area (ha)"),tags$th("%"))),
                     tags$tbody(barrier_rows)),
          div(class="divider"),
          h4(style="margin-bottom:10px","Mangrove Extent"),
          tags$table(class="stats-tbl",
                     tags$tbody(tags$tr(
                       tags$td(style="color:#166534", "Mangrove (GMW 2020)"),
                       tags$td(style="font-family:'DM Mono',monospace", format(mang_ha, big.mark=",")),
                       tags$td(style="font-family:'DM Mono',monospace;color:#7a9a7a", paste0(mang_pct, "% of region"))
                     )))
      )
    })
    div(class="stats-grid", cards)
  })
}

# ── 7. Run ────────────────────────────────────────────────────────────────────

shinyApp(ui, server)