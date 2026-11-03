# SB5 Mangrove Migration Barrier Map

An R Shiny application for exploring potential land-cover barriers to inland mangrove migration in the Eastern Tropical Pacific. Developed for Conservation International’s Save the Blue Five (SB5) project with UCSB Bren School collaborators.

**Status:** work in progress. The app supports exploratory classification scenarios; it does not predict future mangrove extent or establish that migration is feasible at a particular site.

The study focuses on **Costa Rica, Panama, Colombia, Ecuador, and Peru**. An independent mangrove overlay includes the **Galápagos Islands**. Analysis is limited to the supplied land-cover and slope rasters; visible mangroves outside that footprint do not have corresponding barrier statistics.

## What the app provides

| Component | What it shows | What changes with the classification controls |
|---|---|---|
| Adjustable land-cover map | Low, Medium, or High barrier scores assigned to WorldCover classes | Map colors and land-cover summaries |
| Fixed slope reference | The supplied, precomputed land-cover and terrain barrier composite | Nothing; this is a comparison layer |
| GMW mangrove overlay | Global Mangrove Watch v3.0 extent for 2020, independently prepared for the region | Visibility only, using the GMW checkbox |
| Polygon statistics and CSV | WorldCover class areas and assigned land-cover barrier scores inside a drawn polygon | Barrier assignments; measured class areas stay the same |
| Country statistics | Prepared WorldCover area totals for the five study countries | Land-cover barrier totals |

**The green GMW overlay and the reported mangrove areas are different datasets.** Mangrove area in country tables, polygon tables, and CSV exports comes from **WorldCover 2021 class 95**, not from GMW. Neither the GMW overlay nor the fixed slope reference changes these statistics.

## Run locally

### 1. Get the project

Clone the repository, or open your existing checkout. Use the branch containing the version you want to run; an unmerged development branch may differ from `main`.

```bash
git clone https://github.com/Sarayu-26/sb5_mangrove_barrier_map.git
cd sb5_mangrove_barrier_map
```

The committed `data/prepared/` and `data/gmw/` products are sufficient to run the app. The original `input/` TIFFs use Git LFS and are needed only when rebuilding the land-cover products. Prepared products are stored as ordinary Git files.

### 2. Install R dependencies

In an R console:

```r
install.packages(
  c("shiny", "leaflet", "leaflet.extras", "terra", "sf", "jsonlite"),
  repos = "https://cloud.r-project.org"
)
```

Use an R version compatible with these packages. The app uses R’s native pipe (`|>`), so R older than 4.1 cannot parse it. `DESCRIPTION` records runtime dependencies; `manifest.json` records the deployment environment. Installing `sf` or `terra` from source may require the spatial libraries reported by their installation errors.

### 3. Start Shiny

From the project root in Terminal:

```bash
Rscript --vanilla -e 'shiny::runApp(".", host="127.0.0.1", port=3838, launch.browser=TRUE)'
```

Open [http://127.0.0.1:3838](http://127.0.0.1:3838). Keep the terminal running; press **Ctrl+C** to stop. This runs on your computer and does not publish anything to Posit.

Alternatively, open `sb5_mangrove_barrier_map.Rproj` in RStudio and run `shiny::runApp()` in its console.

If you deliberately installed packages into the project’s ignored `.Rlibrary/` folder, add that library before starting:

```r
.libPaths(c(".Rlibrary", .libPaths()))
shiny::runApp()
```

## Use the app

1. Read **About** for the study context and limitations.
2. Open **Barrier Map**, pan or zoom to your area, and choose **Adjustable land cover** or **Fixed slope reference**.
3. Change a land-cover score to explore a scenario. **Reset to defaults** restores the original assignments. The slope reference remains fixed.
4. Toggle **Show GMW extent (2020)** to compare mapped mangroves with the available barrier footprint.
5. Draw a polygon. The most recently drawn or edited valid polygon supplies the sidebar statistics and CSV download. Drawings belong to the current session and are not saved as shared annotations.
6. Open **Statistics** for country-level land-cover and barrier summaries.

### Default classification

| WorldCover class | Code | Default barrier |
|---|---:|---|
| Tree cover | 10 | Low (1) |
| Shrubland | 20 | Low (1) |
| Grassland | 30 | Medium (2) |
| Cropland | 40 | High (3) |
| Built-up | 50 | High (3) |
| Bare / sparse vegetation | 60 | Low (1) |
| Permanent water | 80 | Medium (2) |
| Herbaceous wetland | 90 | Low (1) |
| Mangroves | 95 | Excluded from barrier scoring (0) |
| Moss / lichen | 100 | Low (1) |

These are scenario assumptions, not calibrated migration probabilities. The upstream slope reference is documented as treating slopes above 5° as High barrier. The repository does not contain a separate slope mask that would allow that rule to be recomputed reliably for arbitrary land-cover classifications.

### Interpret areas and exports

- Statistics use the **supplied approximately 100 m grid**, not WorldCover’s native 10 m resolution and not the coarser display grid.
- Cell areas are calculated in hectares for the geographic raster grid. A polygon includes the **whole area of each cell whose center is inside it**, respecting holes. Partial-cell overlaps are not weighted; a very small polygon may contain no cell centers.
- CSV columns are `name`, `area_ha`, `pct`, `barrier`, `area_method`, and `barrier_method`. `pct` describes the share of included, supported non-mangrove land-cover area. Mangrove rows are excluded from that denominator and have no percentage value.
- Country membership uses Natural Earth medium-scale boundaries. Coastal cells outside these generalized polygons are omitted from country totals. The country mangrove percentage uses the sum of country-assigned WorldCover mangrove areas.
- GMW is aggregated using any-presence rendering to keep narrow stands visible. This can exaggerate their displayed width. Map appearance should not be used to estimate area.

## Data and provenance

| Product | Role in this repository | Source or status |
|---|---|---|
| WorldCover 2021 v200 | Land-cover classes and class-95 mangrove statistics | Supplied regional exports at approximately 100 m; source dataset is 10 m |
| Land-cover + slope composite | Fixed barrier reference | Supplied exports; upstream project documentation identifies SRTM and a >5° rule |
| GMW v3.0, 2020 | Independent display overlay, including Galápagos | Official 2020 GeoTIFF archive; checksum verified during preparation |
| Natural Earth country boundaries | Offline assignment of cells to countries | Medium-scale boundaries obtained through `rnaturalearth` |
| Human Modification Index | Potential future refinement of grassland/pasture interpretation | Not integrated into the app |

The original project describes a Google Earth Engine/Colab workflow that buffers mangrove extent by 5 km, samples land cover, and incorporates terrain. The upstream notebook is **not included in this checkout**. Buffer construction, slope derivation, and Pacific-only clipping therefore remain upstream provenance questions rather than verified guarantees of this viewer.

GMW preparation retains complete tiles intersecting 96°W–68°W and 20°S–12°N. Neighboring coastlines and Caribbean mangroves may appear. The broader GMW footprint does not create new land-cover data, a new inland buffer, or additional country statistics. The app deliberately uses the 2020 v3.0 study vintage, not a live feed or a claim to use the latest GMW release. See the [official GMW dataset record](https://zenodo.org/records/6894273).

## How the raster workflow works

Heavy preparation is performed **before deployment**, rather than at Shiny startup:

- `scripts/prepare_data.R` reads source rasters in blocks, stores populated cells with their areas and spatial bounds, and builds country summaries and an overview.
- `scripts/prepare_gmw.R` verifies the official archive, selects regional GMW tiles, and builds an independent overview.
- Shiny loads the summaries and overviews at startup. At closer zoom levels it reads data intersecting the viewport and renders a bounded grid, with a default maximum dimension of 768 cells.
- Polygon queries visit intersecting prepared blocks. Changing a classification reuses the measured areas rather than repeating the spatial query.

The prepared land-cover dataset contains **3,532,878 populated cells in 161 blocks**, replacing runtime processing of a 600,406,896-cell regional grid. Local benchmark results and their limitations are recorded in [runtime and preparation notes](docs/runtime-and-preparation.md); those measurements are not hosted-service performance guarantees.

### Rebuild prepared products

Routine users do not need to rebuild the committed products. Rebuild when source inputs or preparation logic change.

Install preparation dependencies in R:

```r
install.packages(c("rnaturalearth", "rnaturalearthdata", "rsconnect"))
```

For land cover, retrieve the original files with Git LFS, move the existing `data/prepared/` directory to a backup outside the repository, and run from the project root:

```bash
git lfs install
git lfs pull
Rscript --vanilla scripts/prepare_data.R
```

The builder refuses to overwrite a completed dataset and expects eight WorldCover tiles with eight matching slope-composite tiles. Source checksums are recorded in the prepared index.

For GMW, download **`gmw_v3_2020_gtiff.zip`** from the [official archive](https://zenodo.org/records/6894273), move `data/gmw/` to a backup outside the repository, then run:

```bash
Rscript --vanilla scripts/prepare_gmw.R /absolute/path/to/gmw_v3_2020_gtiff.zip
```

Both preparation steps run locally. Commit the matching prepared products, code, and refreshed manifest together after validation. See [the detailed preparation notes](docs/runtime-and-preparation.md).

## Checks before sharing changes

From the project root:

```bash
Rscript --vanilla scripts/check_dependencies.R
Rscript --vanilla tests/spatial.R
Rscript --vanilla tests/gmw.R
Rscript --vanilla tests/server.R
```

Use `scripts/check_dependencies.R --prepare` to include the boundary-data dependencies. Test coverage includes polygon geometry and holes, cell areas, classification, bounded rendering, GMW source checksums and geographic coverage, and Shiny feature creation/editing/deletion.

Also check the app in a browser: change and reset scores, switch map modes, toggle GMW, zoom into the coast and Galápagos, draw/edit/delete a polygon, download its CSV, and compare its contents with the sidebar. Automated tests do not establish scientific validity or replace hosted-app verification.

## Publish to Posit Connect Cloud

Running locally, uploading a local bundle, and publishing from GitHub are separate workflows. For a **GitHub-linked deployment**:

1. Install `rsconnect`, run the checks above, then regenerate deployment metadata:
   ```bash
   Rscript --vanilla scripts/write_manifest.R
   ```
2. Review and commit the code, prepared data, and manifest. Push the branch you intend to deploy.
3. In Connect Cloud, choose **Publish from GitHub**, select `Sarayu-26/sb5_mangrove_barrier_map`, select that branch, and choose root **`app.R`** as the primary file. Use `main` only after the desired changes are merged there.
4. Enable automatic publishing only if the Connect Cloud GitHub App has access to the repository. Otherwise publish and republish manually.
5. Verify the hosted map, statistics, polygon export, and deployment logs before replacing an existing working deployment.

The manifest script includes `app.R`, `DESCRIPTION`, `R/`, `data/prepared/`, and `data/gmw/`. It excludes original input rasters. Local deployment records and package libraries are ignored by Git. Direct uploads with `rsconnect::deployApp()` do not establish a GitHub source connection. See [Posit’s GitHub publishing guide](https://docs.posit.co/connect-cloud/user/publish/github.html).

## Repository layout

```text
app.R                          Shiny UI and application entry point
R/spatial.R                    Sparse land-cover queries and area summaries
R/gmw.R                        Independent GMW loading and display
R/server.R                     Reactive map, polygon, table, and CSV behavior
data/prepared/                 Committed land-cover products and country totals
data/gmw/                      Committed regional GMW tiles and overview
input/                         Original WorldCover and slope tiles (Git LFS)
scripts/                       Preparation, dependency, and manifest tools
tests/                         Spatial, GMW, and Shiny regression checks
docs/                          Review history and implementation notes
DESCRIPTION                    R dependency declarations
manifest.json                  Posit deployment files and package metadata
sb5_mangrove_barrier_map.Rproj  RStudio project
```

## Limitations and next steps

- **Land cover is a proxy:** grassland may represent natural vegetation or cleared pasture. Human-modification information is not yet integrated.
- **Terrain scenarios are limited:** interactive scores do not recompute slope-inclusive barriers. A separate validated slope mask is needed for that capability.
- **Coverage requires confirmation:** independent GMW coverage, supplied barrier coverage, and country assignment are different boundaries. Pacific-only scope has not been independently verified.
- **Migration depends on additional processes:** elevation, inundation, sediment, salinity, freshwater availability, and other constraints are not modeled here.
- **Resolution and boundary choices matter:** input resampling, whole-cell polygon inclusion, generalized country boundaries, and coarser map rendering affect interpretation.
- **Validation remains ongoing:** review the upstream processing notebook and data provenance, validate area totals against reference outputs, and complete browser/export and hosted-capacity checks for the version being released.

## References and contact

- **GMW:** Bunting et al. (2022), *Global Mangrove Extent Change 1996–2020: Global Mangrove Watch Version 3.0*. [Paper](https://doi.org/10.3390/rs14153657) · [Dataset and CC BY 4.0 attribution](https://zenodo.org/records/6894273).
- **WorldCover:** Zanaga et al. (2022), *ESA WorldCover 10 m 2021 v200*. [Dataset](https://doi.org/10.5281/zenodo.7254221).
- **SRTM:** Farr et al. (2007), *The Shuttle Radar Topography Mission*. [Paper](https://doi.org/10.1029/2005RG000183).

Project contact: **Sarayu Ramnath**, UCSB Bren School of Environmental Science and Management / Conservation International SB5 — [sramnath@bren.ucsb.edu](mailto:sramnath@bren.ucsb.edu).
