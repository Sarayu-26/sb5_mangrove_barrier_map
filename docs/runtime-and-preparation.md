# Runtime and preparation

The Shiny app reads a small overview raster, cached country totals, and spatially indexed blocks of populated source cells. It never creates the 600,406,896-cell regional mosaic at runtime. The prepared dataset contains 3,532,878 populated cells in 161 blocks (approximately 3.5 MB compressed).

## Rebuild when source data changes

1. Obtain the original tiles with Git LFS. Install `rnaturalearth` and `rnaturalearthdata` in addition to the runtime packages.
2. Move `data/prepared` to a backup outside the repository. The builder refuses to overwrite a completed dataset.
3. Run `Rscript --vanilla scripts/prepare_data.R` from the project root. It validates supported classes and matching grids, calculates geographic cell areas, assigns country membership using Natural Earth medium-scale boundaries, and writes the completion index last.
4. Run `Rscript --vanilla tests/spatial.R` and `Rscript --vanilla tests/server.R`.
5. With `rsconnect` installed, run `Rscript --vanilla scripts/write_manifest.R` to refresh deployment metadata. Commit the prepared products together with the matching code and manifest.

The index stores source checksums. Prepared products are ordinary Git files, including an explicit Git LFS exemption for the small overview TIFF. Source tiles remain unchanged and LFS-managed. Deployment excludes original input tiles and local annotations. Local rsconnect deployment records are ignored.

## Interpretation and limitations

- Adjustable scores and statistics describe land cover only. The supplied slope composite is an independent fixed reference; the available data cannot reconstruct a separate steep-slope mask reliably.
- Areas use the supplied approximately 100 m cells, not native 10 m WorldCover. Polygon and country membership use cell centers, including polygon holes; partial-cell overlap is not weighted. Tiny polygons may contain no cell centers.
- Country assignment uses generalized boundaries; coastal cells outside those boundaries do not enter country totals. Pacific-only upstream clipping has not been independently established.
- Display layers use modal land cover/slope and any-presence mangrove aggregation. Overview mangrove footprints exaggerate narrow features; numerical summaries always use source-cell areas.
- Original source provenance and upstream scientific assumptions still require project-owner review.

## Validation completed locally

Spatial tests cover valid polygons, holes, invalid geometry, known-area sums, percentage denominators, classification, empty selections, bounded display grids, and source-cell area magnitude. Shiny tests cover class changes, drawing/editing/deletion, selection fallback, country output, and map rendering. Browser inspection confirmed map rendering, dynamic class colors, and switching to the slope reference. The final browser polygon/CSV export check remains unfinished.

Measured on the development Mac: application source/startup approximately 1.2 seconds; startup plus one overview encoding approximately 315 MiB peak child RSS; a 2-degree Costa Rica-area render approximately 0.52 seconds; polygon statistics for that region approximately 0.93 seconds. These are local observations, not cloud capacity or concurrency guarantees.

The dated repository review records the original findings before these changes; use this document for the current implementation status.

## Independent GMW overlay experiment

The green map overlay now uses official GMW v3.0 **2020** extent, credited to Bunting et al. (2022), CC BY 4.0: https://zenodo.org/records/6894273. This intentionally matches the documented study vintage; it is not the newer v4.1 product or a live feed from the GMW website.

Download `gmw_v3_2020_gtiff.zip` from that record, then run `Rscript --vanilla scripts/prepare_gmw.R /path/to/gmw_v3_2020_gtiff.zip`. The builder verifies the published archive MD5 and retains complete tiles intersecting 96°W–68°W, 20°S–12°N, including the entire Galápagos archipelago. Coverage is independent of the uploaded land-cover TIFFs. Neighboring coastlines and Caribbean mangroves inside those tiles may also appear; the overlay is not a country mask or proof of Pacific-only analysis coverage. Source rasters and an overview are bundled under `data/gmw` for offline runtime use. The original land-cover products do not need rebuilding.

The GMW checkbox controls only the display overlay. It is rendered above both barrier modes, with any-presence aggregation to preserve narrow features at small scales. This can exaggerate their displayed width. All polygon/country statistics and CSV exports still use WorldCover and remain labeled accordingly. GMW coverage beyond the supplied rasters does not add land cover, slope data, or a new migration buffer.

Run `Rscript --vanilla tests/gmw.R`, the existing spatial/server tests, and then regenerate the deployment manifest. Changes are isolated on `codex/prepare-posit-raster-performance`; revert the overlay changes to discard this experiment without deleting earlier branch work.

Validation of this experiment: spatial, GMW and Shiny test suites passed. Browser checks confirmed the overlay at Galápagos zoom, toggle-off revealing the land-cover footprint, and persistence when switching barrier modes. The prepared land-cover footprint starts at approximately 91°W; GMW includes mangroves west of that boundary. Bundled GMW rasters total approximately 13 MB. Local testing used a project-local `leaflet.extras` installation: `Rscript --vanilla -e '.libPaths(c(".Rlibrary",.libPaths())); shiny::runApp()'`.

The full manifest generator encountered unavailable CRAN metadata in this environment. Since this change adds no package dependencies, the existing package records were retained and the manifest file list/checksums refreshed directly. Cloud deployment was not performed.
