library(shiny)
library(leaflet)
library(terra)
library(raster)
library(leaflet.extras)
library(dplyr)
library(sf)

# ── 1. Load & prepare rasters ─────────────────────────────────────────────────

countries <- c("costa_rica", "panama", "colombia", "ecuador")
country_labels <- c(
  costa_rica = "Costa Rica",
  panama     = "Panama",
  colombia   = "Colombia (Pacific)",
  ecuador    = "Ecuador"
)

# Load
raw_rasters   <- lapply(setNames(countries, countries), function(c)
  rast(file.path("input", paste0("worldcover_raw_5km_", c, ".tif"))))
slope_rasters <- lapply(setNames(countries, countries), function(c)
  rast(file.path("input", paste0("mangrove_barrier_5km_slope_", c, ".tif"))))
lc_rasters    <- lapply(setNames(countries, countries), function(c)
  rast(file.path("input", paste0("mangrove_barrier_5km_lc_", c, ".tif"))))

# Reproject to WGS84
raw_rasters   <- lapply(raw_rasters,   function(r) project(r, "EPSG:4326"))
slope_rasters <- lapply(slope_rasters, function(r) project(r, "EPSG:4326"))
lc_rasters    <- lapply(lc_rasters,    function(r) project(r, "EPSG:4326"))

# Extract mangrove pixels (WorldCover class 95) from raw rasters
# These show where mangroves actually are
mangrove_rasters <- lapply(raw_rasters, function(r) {
  m <- ifel(r == 95, 1, NA)
  as(m, "Raster")
})

# Convert slope and lc to Raster format for leaflet
slope_rasters_rl <- lapply(slope_rasters, function(r) as(r, "Raster"))
lc_rasters_rl    <- lapply(lc_rasters,    function(r) as(r, "Raster"))

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
PIXEL_AREA_HA  <- (100*100)/10000

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

# ── 3. Helper: reclassify ─────────────────────────────────────────────────────

reclassify_raster <- function(r, cls_map) {
  from <- as.numeric(names(cls_map))
  to   <- as.numeric(cls_map)
  rcl  <- matrix(c(from, to), ncol=2)
  result <- classify(r, rcl, others=NA)
  as(result, "Raster")
}

# ── 4. UI ─────────────────────────────────────────────────────────────────────

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
  "))),
  
  # Header
  div(class="header-bar",
      div(
        h1("Mangrove Migration Barriers — Eastern Tropical Pacific"),
        div(class="subtitle",
            "Costa Rica · Panama · Colombia · Ecuador  |  5km inland buffer · ESA WorldCover 2021 · GMW v3 2020")
      ),
      span(class="wip-badge", "WORK IN PROGRESS")
  ),
  
  tabsetPanel(id="main_tabs",
              
              # ── Tab 1: Land Cover ──────────────────────────────────────────────────────
              tabPanel("5km Land Cover",
                       div(style="position:relative;",
                           div(class="sidebar-panel",
                               div(class="section-label", "Legend"),
                               div(class="legend-item", div(class="legend-dot",style="background:#166534"), "Mangroves (GMW 2020)"),
                               div(class="legend-item", div(class="legend-dot",style="background:#4ade80"), "Low barrier"),
                               div(class="legend-item", div(class="legend-dot",style="background:#facc15"), "Medium barrier"),
                               div(class="legend-item", div(class="legend-dot",style="background:#f87171"), "High barrier"),
                               
                               div(class="section-label",style="margin-top:16px", "Reclassify Land Cover"),
                               p(style="font-size:10px;color:#7a9a7a;margin-bottom:10px;line-height:1.5",
                                 "Adjust barrier scores per class. Map updates on change."),
                               
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
                               
                               actionButton("reset_btn","Reset to defaults",class="reset-btn")
                           ),
                           div(class="map-panel",
                               leafletOutput("map_lc", height="calc(100vh - 90px)")
                           )
                       )
              ),
              
              # ── Tab 2: Slope ───────────────────────────────────────────────────────────
              tabPanel("5km + Slope",
                       div(style="position:relative;",
                           div(class="sidebar-panel",
                               div(class="section-label","Legend"),
                               div(class="legend-item", div(class="legend-dot",style="background:#166534"), "Mangroves (GMW 2020)"),
                               div(class="legend-item", div(class="legend-dot",style="background:#4ade80"), "Low barrier"),
                               div(class="legend-item", div(class="legend-dot",style="background:#facc15"), "Medium barrier"),
                               div(class="legend-item", div(class="legend-dot",style="background:#f87171"), "High barrier (incl. steep terrain)"),
                               
                               div(class="section-label",style="margin-top:16px","Slope Threshold"),
                               p(style="font-size:10px;color:#7a9a7a;line-height:1.5;margin-bottom:6px",
                                 "Baked into tif at 5°. To change, update SLOPE_THRESHOLD in Colab Step 8 and re-export."),
                               div(style="font-family:'DM Mono',monospace;font-size:12px;color:#4ade80;margin-bottom:10px",
                                   "Current: 5°"),
                               
                               div(class="section-label",style="margin-top:16px","Note"),
                               p(style="font-size:10px;color:#7a9a7a;line-height:1.5",
                                 "Pre-computed slope + land cover layer. Use Tab 1 dropdowns to explore land cover reclassification.")
                           ),
                           div(class="map-panel",
                               leafletOutput("map_slope", height="calc(100vh - 90px)")
                           )
                       )
              ),
              
              # ── Tab 3: Statistics ──────────────────────────────────────────────────────
              tabPanel("Statistics",
                       div(class="stats-wrap",
                           h2(style="font-size:16px;font-weight:600;color:#4ade80;margin-bottom:4px",
                              "Land Cover Statistics — 5km Inland Buffer"),
                           p(style="font-size:12px;color:#7a9a7a;font-family:'DM Mono',monospace;margin-bottom:16px",
                             "Pixel counts from raw WorldCover classes · 100m resolution · Pacific coast mangroves only"),
                           
                           div(class="note-box",
                               tags$strong("How to use:"),
                               " Section 1 shows raw land cover in the buffer, which drives the barrier scores.
            Section 2 shows the barrier summary using the current Tab 1 classification.
            Change dropdowns in Tab 1 and return here to see updated totals."
                           ),
                           
                           uiOutput("stats_cards"),
                           
                           div(class="note-box",
                               tags$strong("Known limitation:"),
                               " Grassland (#30) classified as Medium barrier — may include cleared cattle pasture (High barrier).
            Need to incorporate Human Modification Index."
                           )
                       )
              )
  )
)

# ── 5. Server ─────────────────────────────────────────────────────────────────

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
  
  # Reset button
  observeEvent(input$reset_btn, {
    for (code in names(LC_CLASSES)) {
      updateSelectInput(session, paste0("lc_",code), selected=DEFAULTS[code])
    }
  })
  
  # ── Map 1: Land Cover ──
  output$map_lc <- renderLeaflet({
    leaflet(options=leafletOptions(zoomControl=TRUE)) %>%
      addProviderTiles("CartoDB.DarkMatter") %>%
      setView(lng=-80, lat=4, zoom=5)
  })
  
  observe({
    cls   <- current_cls()
    proxy <- leafletProxy("map_lc")
    proxy %>% clearImages() %>% clearControls()
    
    # Barrier layer
    for (country in countries) {
      r_cls <- reclassify_raster(raw_rasters[[country]], cls)
      proxy %>% addRasterImage(
        x       = r_cls,
        colors  = barrier_pal,
        opacity = 0.8,
        layerId = paste0("lc_",country)
      )
    }
    
    # Mangrove layer on top
    for (country in countries) {
      proxy %>% addRasterImage(
        x       = mangrove_rasters[[country]],
        colors  = mangrove_pal,
        opacity = 1,
        layerId = paste0("mang_",country)
      )
    }
    
    proxy %>% addLegend(
      position = "bottomright",
      colors   = c("#166534","#4ade80","#facc15","#f87171"),
      labels   = c("Mangroves","Low barrier","Medium barrier","High barrier"),
      title    = "Migration Barrier",
      opacity  = 0.9
    )
  })
  
  # ── Map 2: Slope ──
  output$map_slope <- renderLeaflet({
    m <- leaflet(options=leafletOptions(zoomControl=TRUE)) %>%
      addProviderTiles("CartoDB.DarkMatter") %>%
      setView(lng=-80, lat=4, zoom=5)
    
    # Barrier layer
    for (country in countries) {
      m <- m %>% addRasterImage(
        x       = slope_rasters_rl[[country]],
        colors  = barrier_pal,
        opacity = 0.8,
        layerId = paste0("slope_",country)
      )
    }
    
    # Mangrove layer on top
    for (country in countries) {
      m <- m %>% addRasterImage(
        x       = mangrove_rasters[[country]],
        colors  = mangrove_pal,
        opacity = 1,
        layerId = paste0("mang_slope_",country)
      )
    }
    
    m %>% addLegend(
      position = "bottomright",
      colors   = c("#166534","#4ade80","#facc15","#f87171"),
      labels   = c("Mangroves","Low barrier","Medium barrier","High barrier (incl. slope)"),
      title    = "Migration Barrier",
      opacity  = 0.9
    )
  })
  
  # ── Stats ──
  output$stats_cards <- renderUI({
    cls <- current_cls()
    
    cards <- lapply(countries, function(country) {
      r    <- raw_rasters[[country]]
      vals <- as.vector(values(r))
      vals <- vals[!is.na(vals) & vals != 0]
      
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
          h4("Land Cover Breakdown",
             span(class="country-tag", country_labels[country])),
          tags$table(class="stats-tbl",
                     tags$thead(tags$tr(tags$th("Class"),tags$th("Area (ha)"),tags$th("%"))),
                     tags$tbody(lc_rows)
          ),
          div(class="divider"),
          h4(style="margin-bottom:10px","Barrier Summary",
             span(style="font-size:9px;color:#7a9a7a;font-weight:400;margin-left:6px",
                  "(updates with Tab 1 dropdowns)")),
          tags$table(class="stats-tbl",
                     tags$thead(tags$tr(tags$th("Barrier"),tags$th("Area (ha)"),tags$th("%"))),
                     tags$tbody(barrier_rows)
          )
      )
    })
    
    div(class="stats-grid", cards)
  })
}

# ── 6. Run ────────────────────────────────────────────────────────────────────

shinyApp(ui, server)

