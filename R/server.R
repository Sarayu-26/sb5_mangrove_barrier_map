server <- function(input, output, session) {
  study_bounds <- study_map_bounds(products,gmw)
  study_gmw_overview <- terra::crop(gmw$overview,terra::ext(study_bounds),snap="in")
  classification <- reactive({
    cls <- DEFAULTS
    for (code in names(LC_CLASSES)) {
      value <- input[[paste0("lc_",code)]]
      if (!is.null(value) && value %in% 1:3) cls[code] <- as.numeric(value)
    }
    cls
  })
  cls <- debounce(classification, 400)
  observeEvent(input$reset_btn, {
    for (code in names(LC_CLASSES)) updateSelectInput(session,paste0("lc_",code),selected=DEFAULTS[code])
  })

  output$map_slope <- renderLeaflet({
    leaflet(options=leafletOptions(zoomControl=TRUE,zoomSnap=0.1,
                                    maxBoundsViscosity=1,worldCopyJump=FALSE)) |>
      addProviderTiles(providers$Esri.WorldGrayCanvas) |>
      fitBounds(study_bounds[1],study_bounds[3],study_bounds[2],study_bounds[4]) |>
      addDrawToolbar(targetGroup="drawn",polylineOptions=FALSE,circleOptions=FALSE,
                     circleMarkerOptions=FALSE,rectangleOptions=FALSE,markerOptions=FALSE,
                     polygonOptions=drawPolygonOptions(shapeOptions=drawShapeOptions(color="#facc15",fillOpacity=0.1)),
                     editOptions=editToolbarOptions()) |>
      addLegend(position="bottomright",colors=c("#166534",unname(BARRIER_COLORS)),
                labels=c(GMW_LABEL,"Low","Medium","High"), title="Migration barriers") |>
      htmlwidgets::onRender(STUDY_VIEW_JS, data=list(
        c(study_bounds[3],study_bounds[1]),c(study_bounds[4],study_bounds[2])))
  })
  viewport <- debounce(reactive(list(bounds=input$map_slope_bounds,zoom=input$map_slope_zoom)),500)
  display <- reactive({
    view <- viewport()
    if (is.null(view$bounds) || is.null(view$zoom) || view$zoom<7) return(products$overview)
    b <- view$bounds
    bounds <- c(b$west,b$east,b$south,b$north)
    if (any(!is.finite(bounds)) || bounds[2]<=bounds[1]) return(products$overview)
    # Clamp latitude to the Web Mercator domain.
    bounds[3:4] <- pmax(-85,pmin(85,bounds[3:4]))
    render_grid(products,bounds)
  })
  observe({
    r <- display()
    mode <- input$map_mode
    layer <- if (identical(mode,"slope")) r[["slope"]] else {
      terra::classify(r[["landcover"]],cbind(as.numeric(names(cls())),as.numeric(cls())),others=NA)
    }
    layer <- terra::ifel(layer==0,NA,layer)
    leafletProxy("map_slope",session) |>
      removeImage("barrier") |>
      addRasterImage(layer,colors=barrier_pal,opacity=0.8,layerId="barrier",method="ngb",maxBytes=4*1024*1024)
  })

  gmw_display <- reactive({
    view <- viewport()
    if (is.null(view$bounds) || is.null(view$zoom) || view$zoom<7) return(study_gmw_overview)
    b <- view$bounds
    bounds <- c(b$west,b$east,max(-85,b$south),min(85,b$north))
    if (any(!is.finite(bounds)) || bounds[2]<=bounds[1] || bounds[4]<=bounds[3]) return(study_gmw_overview)
    bounds <- c(max(bounds[1],study_bounds[1]),min(bounds[2],study_bounds[2]),
                max(bounds[3],study_bounds[3]),min(bounds[4],study_bounds[4]))
    if (bounds[2]<=bounds[1] || bounds[4]<=bounds[3]) return(study_gmw_overview)
    render_gmw(gmw,bounds)
  })
  observe({
    proxy <- leafletProxy("map_slope",session) |> removeImage("gmw")
    if (isTRUE(input$show_gmw)) {
      addRasterImage(proxy,gmw_display(),colors=mangrove_pal,opacity=1,layerId="gmw",
                     method="ngb",maxBytes=4*1024*1024,
                     options=gridOptions(zIndex=450))
    }
  })

  # Session-local features keyed by Leaflet IDs; edits and deletes keep selection consistent.
  polygons <- reactiveVal(list())
  selected <- reactiveVal(NULL)
  feature_id <- function(f) as.character(f$properties$`_leaflet_id`)
  update_feature <- function(f) {
    if (!identical(f$geometry$type,"Polygon")) return()
    id <- feature_id(f)
    if (length(id)!=1L) return()
    geometry <- tryCatch(polygon_geometry(jsonlite::toJSON(f$geometry$coordinates,auto_unbox=TRUE,digits=15)),
                         error=function(e) { showNotification(conditionMessage(e),type="error"); NULL })
    p <- polygons()
    if (is.null(geometry)) {
      p[[id]] <- NULL; polygons(p); selected(NULL); return()
    }
    p[[id]] <- geometry; polygons(p); selected(id)
  }
  observeEvent(input$map_slope_draw_new_feature,update_feature(input$map_slope_draw_new_feature))
  observeEvent(input$map_slope_draw_edited_features, {
    for (f in input$map_slope_draw_edited_features$features) update_feature(f)
  })
  observeEvent(input$map_slope_draw_deleted_features, {
    p <- polygons()
    for (f in input$map_slope_draw_deleted_features$features) p[[feature_id(f)]] <- NULL
    polygons(p)
    if (is.null(selected()) || !selected() %in% names(p)) selected(if(length(p)) tail(names(p),1) else NULL)
  })
  areas <- reactive({
    id <- selected(); if (is.null(id)) return(NULL)
    polygon_areas(products,polygons()[[id]])
  })
  polygon_table <- reactive({
    a <- areas(); if (is.null(a)) return(NULL)
    d <- classify_areas(a,cls())
    mang <- a$area_ha[a$code==95]
    if (length(mang) && mang>0) d <- rbind(d,data.frame(code=95,area_ha=mang,name="Mangrove (WorldCover 2021)",pct=NA_real_,score=0,barrier="Excluded",color="#166534"))
    d
  })
  stats_table <- function(d) {
    tags$table(class="stats-tbl",
      tags$thead(tags$tr(tags$th("Class"),tags$th("Area (ha)"),tags$th("Barrier"))),
      tags$tbody(lapply(seq_len(nrow(d)),function(i) tags$tr(
        tags$td(d$name[i]),tags$td(format(round(d$area_ha[i],2),big.mark=",")),
        tags$td(style=paste0("color:",d$color[i]),d$barrier[i])))))
  }
  output$poly_stats_slope <- renderUI({
    d <- polygon_table()
    if (is.null(d)) return(p("Draw a polygon to calculate land-cover areas."))
    if (!nrow(d)) return(p("No populated cell centers inside this polygon."))
    div(class="poly-stats",p("Land cover only; excludes the slope rule."),stats_table(d))
  })
  output$dl_poly_slope <- downloadHandler(
    filename=function() paste0("polygon_landcover_",Sys.Date(),".csv"),
    content=function(file) {
      d <- polygon_table()
      if (is.null(d) || !nrow(d)) stop("Draw a polygon containing populated cell centers before downloading.")
      d <- d[,c("name","area_ha","pct","barrier")]
      d$area_method <- "Whole cell area; center inside polygon; ~100 m input grid"
      d$barrier_method <- "Land cover only; slope excluded"
      write.csv(d,file,row.names=FALSE)
    })
  output$stats_cards <- renderUI({
    all <- products$countries
    regional_mang <- sum(all$area_ha[all$code==95])
    div(class="stats-grid",lapply(names(COUNTRIES),function(country) {
      a <- all[all$country==country,c("code","area_ha")]
      d <- classify_areas(a,cls())
      mang <- sum(a$area_ha[a$code==95])
      barrier <- if (nrow(d)) aggregate(area_ha~barrier,data=d,FUN=sum) else data.frame(barrier=character(),area_ha=numeric())
      div(class="stats-card",h4(COUNTRIES[[country]]),stats_table(d),
          h4("Land-cover barrier totals"),
          tags$table(class="stats-tbl",tags$tbody(lapply(seq_len(nrow(barrier)),function(i)
            tags$tr(tags$td(barrier$barrier[i]),tags$td(paste(format(round(barrier$area_ha[i],2),big.mark=","),"ha")))))),
          h4("Mangrove extent — WorldCover 2021"),
          p(paste(format(round(mang,2),big.mark=","),"ha ·",if(regional_mang>0) round(100*mang/regional_mang,1) else 0,"% of country-assigned regional mangroves")))
    }))
  })
}
