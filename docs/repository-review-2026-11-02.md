# Repository and Posit publishing review — 2026-11-02

Verdict: **not ready to publish**. This is an inspection, not a completed repair or deployment. Application code and data were left unchanged.

## Verified checks

- `app.R` parses successfully with R.
- All 16 GeoTIFFs open through terra; their SHA-256 hashes match the committed Git LFS pointers. These are real downloaded rasters, not unresolved pointers.
- Eight tiles per layer, 600,406,896 cells per complete layer. Resolution is 0.000898315284119522 degrees (approximately 100 m), not native 10 m WorldCover. Compressed input totals approximately 9.1 MB.
- Full application source stops at missing `leaflet.extras`. `rnaturalearth` and `rnaturalearthdata` are also absent locally. No browser or complete startup validation was possible in this environment without installing dependencies. No full raster-processing benchmark was attempted.
- Manifest JSON is valid but stale: 12 listed data files do not exist; none of the 16 current tiles are listed; app and README checksums differ. Neither `rnaturalearth` nor `rnaturalearthdata` is included.
- Isolated evaluation of the actual `poly_to_vect()` function with a valid closed GeoJSON polygon returns NULL.
- `terra::cellSize()` on a cell with the input resolution at the equator gives 0.9933056 ha. The app assigns 25 ha to each high-resolution mangrove cell.
- Standard Git status triggers an LFS temporary-file write prohibited by the local sandbox. A filter-disabled status makes hydrated LFS files appear modified; hash verification confirms their contents match HEAD. This is not evidence of data edits.

## Findings, highest priority first

### P1 — Publishing manifest cannot reproduce the current app

`manifest.json` references the former country-specific input layout and omits newly required boundary packages. `app.R:10` loads rnaturalearth and `app.R:26` requests medium-scale country data. A clean deployment cannot rely on an interactive data-package installation. Install and explicitly declare all runtime dependencies, including rnaturalearthdata, then regenerate the manifest from the final deployment file set. README's installation command is also incomplete.

### P1 — Drawn polygon statistics and CSV exports fail

At `app.R:185`, the nesting loop descends through the polygon rings all the way to the first coordinate pair. The following length check rejects this two-number pair. A valid polygon therefore produces NULL; sidebar and export report no pixels instead of computing statistics. Parse the GeoJSON geometry without discarding its ring structure, preserving holes and checking validity. Add a known-polygon regression test.

Reproducer (after loading this function alone from the parsed app):

```r
poly_to_vect('[[[-81,0],[-80,0],[-80,1],[-81,1],[-81,0]]]')
# NULL, unexpectedly
```

### P1 — Mangrove areas are about 25 times too large

`PIXEL_AREA_HA` is 25 ha, appropriate only as a rough estimate for aggregated 500 m pixels. `mangrove_mosaic` retains the original approximately 100 m grid, but `app.R:201`, `app.R:627`, and `app.R:637` use the same multiplier. Longitude/latitude cells also vary in area with latitude. Use actual cell areas separately for each grid, with appropriate polygon overlap weighting. Validate a known region against the source processing outputs.

### P1 — Classification controls do not update the barrier map

`app.R:521-550` always renders the static `slope_rl`. It does not depend on `current_cls_d()` and no map-update observer is present. `cls_key()` and `reclassify_raster()` are unused. Dropdown changes affect table labels but leave map colors unchanged despite the UI promise.

Retain a separate steep-slope mask when implementing dynamic classification. The existing final barrier composite cannot uniquely identify steep pixels: score 3 can also mean cropland or built-up land. An independently generated slope mask or underlying slope raster is needed to honor “slope >5° is always High” under arbitrary reclassification.

### P1 — Runtime design is unsuitable for a small hosting instance without revision

`app.R:41-56` mosaics and processes full regional rasters at every worker startup. `app.R:627` materializes all mangrove values inside a reactive output; a single numeric vector for this grid is approximately 4.47 GiB, excluding logical masks, copies, other layers, and rendering. Country crops and counts repeat after classification changes. The full-resolution mangrove layer is sent through Leaflet raster rendering (`app.R:543`); raising maxBytes does not bound projection or encoding memory.

Follow Ocean Downscaling Viewer's prepared-product approach: preprocess display layers, cache country class/area summaries once, and read only spatial subsets for polygon analysis. Preserve full-resolution data for statistics; use separate compact display products. Measure startup, first-map time, peak memory, and simultaneous sessions before selecting the hosting instance. Out-of-memory failure is a strong risk, not a measured cloud result.

### P2 — Statistics and map have different scientific meanings

Country and polygon summaries classify raw land cover without the slope override (`app.R:572`, `app.R:640` onward). The displayed map is a slope composite. Label these clearly as land-cover-only statistics or calculate slope-inclusive summaries from the same data used for the map. Modal aggregation changes class areas and may eliminate small habitats; do not present display-grid counts as source-resolution area estimates.

Country percentage denominators include mangrove code 95 before its row is filtered out (`app.R:633` and subsequent mutate/filter). Visible class percentages consequently need not sum to 100%. Choose and disclose a denominator, excluding unsupported classes before calculating percentages if the intent is composition of displayed classes.

### P2 — Polygon lifecycle and persistence are inconsistent

The toolbar allows editing, but there is no edited-features observer, so edited shapes retain old statistics. Deleting any feature clears the last polygon even when other polygons remain. New annotations append to a shared `input/annotations.csv`; there is no locking, session isolation, or error handling. Saved annotations are never restored because `draw_saved_annotations()` is never called. Either keep polygons explicitly session-local or provide deliberate shared persistence with stable IDs, updates, deletion, and concurrency control.

### P2 — Provenance and instructions do not match the app

The mangrove raster is computed from WorldCover class 95 (`app.R:117`), but UI labels call it GMW 2020. Upstream GMW may define the buffer, but the displayed mask here is WorldCover-derived. Confirm the intended source and correct labels or supply the actual GMW layer.

README lists four countries, missing filenames, and obsolete tabs; app includes Peru and has About, Barrier Map, and Statistics. In-app instructions also refer to removed tabs/country selection. The upstream notebook is not in this checkout, so Pacific-only clipping, slope derivation, and source-data provenance were not independently verified. Country boundary masking alone cannot enforce Pacific-only scope. Narrow-screen layout also needs browser testing: a fixed 260 px sidebar leaves little map width on phones.

## Comparison with the requested templates

Inspected local sibling repositories at `/Users/ibrito/Developer/megafauna-data-viewer` and `/Users/ibrito/Developer/ocean-downscaling-viewer`.

- **Megafauna:** has DESCRIPTION, modular R helpers, regression tests, `.rscignore`, and a deployment file allowlist. Its `docs/source_grouping_verification.md` records a Connect Cloud URL. However, `scripts/deploy_shinyapps.R` explicitly targets shinyapps.io and a specific account; do not copy that destination as the Connect Cloud configuration. Its manifest also predates more recent edits, so regenerate rather than treating a template manifest as authoritative.
- **Ocean:** has DESCRIPTION, a dependency checker, configurable data profiles, prepared previews/indexes, and external-data access. Its README explicitly keeps heavy preprocessing upstream. Reuse those design principles; a remote COG service may be unnecessary for this app if prepared products and spatial subsets can meet measured memory limits. Its README lists several hosting options, not evidence of one currently verified production destination.

## Path to Connect Cloud

1. Repair polygon parsing, area calculations, reactive map updates, and scientific labels; obtain a separate slope mask if adjustable slope-inclusive classification is required.
2. Build compact display products and reusable area summaries outside app startup. Define a clear session-only polygon lifecycle or an intentional durable store.
3. Add DESCRIPTION with complete dependencies, dependency/data validation, meaningful regression tests, and an explicit deployment bundle list or `.rscignore`. Exclude runtime annotations and local artifacts.
4. Install dependencies in a clean compatible R environment. Start with `shiny::runApp()` and verify map loading, class changes/reset, drawing/editing/deletion, CSV accuracy, country statistics, multiple sessions, and memory use.
5. Regenerate `manifest.json` using `rsconnect::writeManifest()` from the finalized project. Verify every bundled file and package. Verify the chosen publishing route supplies actual TIFF bytes rather than Git LFS pointer text; local hydration alone does not prove remote hydration.
6. For GitHub publishing, commit the tested app/data/dependency file, select this repository and intended branch in Connect Cloud, and use root `app.R` as the primary file. Match the desired account and visibility to the existing deployment. Push/publish only after the repaired result is reviewed.
7. Check clean deployment logs and exercise the hosted app, including a cold restart. Record the URL, revision, memory measurements, and validation results.

Current official guidance supports GitHub publishing with a dependency manifest or lockfile alongside app.R, as well as IDE and command-line publishing:

- https://docs.posit.co/connect-cloud/how-to/r/shiny-r.html
- https://docs.posit.co/connect-cloud/user/support/01-known-issues.html

No source repair, package installation, push, or deployment was performed as part of this inspection.
