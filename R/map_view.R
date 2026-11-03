# Fit the supplied study cells plus GMW's offshore Galapagos coverage.
study_map_bounds <- function(products, gmw, padding=0.35) {
  bounds <- products$index$bounds
  r <- gmw$overview
  cells <- which(terra::values(r,mat=FALSE)==1)
  xy <- terra::xyFromCell(r,cells)
  islands <- xy[xy[,1] < -88,,drop=FALSE]
  if (nrow(islands)) {
    half <- terra::res(r)/2
    bounds <- c(min(bounds[1],min(islands[,1])-half[1]),
                max(bounds[2],max(islands[,1])+half[1]),
                min(bounds[3],min(islands[,2])-half[2]),
                max(bounds[4],max(islands[,2])+half[2]))
  }
  bounds + c(-padding,padding,-padding,padding)
}

# Recalculate the fitted minimum zoom when the map becomes visible or resizes.
# Fractional zoom avoids exposing an extra whole zoom level around the study.
STUDY_VIEW_JS <- "function(el, x, data) {
  var map = this;
  var bounds = L.latLngBounds(data);
  var initialized = false;
  var resizing = false;
  function lockOverview() {
    if (!initialized || resizing) return;
    var overview = map.getZoom() <= map.getMinZoom() + 0.001;
    if (overview) {
      map.dragging.disable();
      var zoom = map.getMinZoom();
      var center = map.unproject(map.project(bounds.getSouthWest(), zoom)
        .add(map.project(bounds.getNorthEast(), zoom)).divideBy(2), zoom);
      // Also constrain keyboard/touch panning and zoom-around-pointer offsets.
      if (map.getCenter().distanceTo(center) > 1) {
        map.setView(center, zoom, {animate:false});
      }
    } else {
      map.dragging.enable();
    }
  }
  function constrain() {
    var size = map.getSize();
    if (!size.x || !size.y) return;
    resizing = true;
    map.setMinZoom(0);
    var zoom = map.getBoundsZoom(bounds, false);
    map.setMinZoom(zoom);
    if (!initialized) {
      map.fitBounds(bounds, {animate:false});
      initialized = true;
    }
    map.panInsideBounds(bounds, {animate:false});
    resizing = false;
    lockOverview();
  }
  map.setMaxBounds(bounds);
  map.on('resize', constrain);
  map.on('zoomend moveend', lockOverview);
  constrain();
}"
