library(shiny)
library(leaflet)
library(leaflet.extras)
source("R/spatial.R", local=TRUE)
products <- load_products()
country_labels <- COUNTRIES
countries <- names(COUNTRIES)
barrier_pal <- colorFactor(c("#4ade80", "#facc15", "#f87171"), domain=c(1,2,3), na.color="transparent")
mangrove_pal <- colorFactor("#166534", domain=1, na.color="transparent")
source("R/server.R", local=TRUE)

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
    @media (max-width: 700px) { .sidebar-panel { width:100%; float:none; height:auto; max-height:40vh; } .map-panel { margin-left:0; } .stats-grid { grid-template-columns:1fr; } .about-wrap { padding:20px; } }
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
                           p("The fixed slope reference includes the upstream terrain rule (>5°). Adjustable scores and statistics describe land cover only; changing scores does not alter the slope reference."),
                           
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
           on the Barrier Map tab. Reclassify grassland as High barrier if cattle ranching is the
           dominant land use in your area of interest."),
                           
                           tags$h3("How to use it"),
                           div(class="step-row",
                               div(class="step-num", "01"),
                               div(class="step-text", tags$strong("Explore the coast"), " — the maps show all five countries
              simultaneously at zoom 5; pan and zoom into your region of interest.")
                           ),
                           div(class="step-row",
                               div(class="step-num", "02"),
                               div(class="step-text", tags$strong("Adjust barrier scores"), " — use the dropdowns in the
              Barrier Map sidebar to reclassify land cover types for your context. The map updates live.")
                           ),
                           div(class="step-row",
                               div(class="step-num", "03"),
                               div(class="step-text", tags$strong("Draw a polygon"), " — use the draw tool (pentagon icon)
              on the map to outline your area of interest. Summary statistics appear in the sidebar.")
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
                               div("Coastal buffer and slope composite processed in Google Earth Engine · supplied grid approximately 100 m · display detail adapts to zoom")
                           ),
                           
                           tags$h3("Known limitations"),
                           p("Grassland (ESA class 30) is classified as Medium barrier by default but may include cleared
          cattle pasture, which is a de-facto High barrier. A Human Modification Index overlay to
          distinguish natural grassland from agricultural conversion is planned."),
                           p("The 5km buffer is a conservative inland distance. Mangrove migration potential also depends
          on elevation gradients, soil salinity and freshwater inflow, which are not yet included."),
                           p("Drawings stay in your browser session. The most recently drawn or edited polygon supplies the statistics. Areas include whole cells whose centers lie inside the polygon; tiny polygons may contain no cell centers."),
                           
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
                               
                               radioButtons("map_mode", "Map layer", choices=c("Adjustable land cover"="landcover", "Fixed slope reference"="slope"), selected="landcover"),
                               div(class="section-label", "Legend"),
                               div(class="legend-item", div(class="legend-dot",style="background:#166534"), "Mangroves (WorldCover 2021)"),
                               div(class="legend-item", div(class="legend-dot",style="background:#4ade80"), "Low barrier"),
                               div(class="legend-item", div(class="legend-dot",style="background:#facc15"), "Medium barrier"),
                               div(class="legend-item", div(class="legend-dot",style="background:#f87171"), "High barrier"),
                               
                               div(class="section-label", style="margin-top:16px", "Reclassify land cover"),
                               p(style="font-size:10px;color:#7a9a7a;margin-bottom:10px;line-height:1.5",
                                 "Scores update the land-cover map and statistics. Switch to the fixed slope reference to compare terrain barriers."),
                               
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
                             "Cell-area totals from the supplied ~100 m grid · land cover only · cell centers determine inclusion"),
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


shinyApp(ui, server)
