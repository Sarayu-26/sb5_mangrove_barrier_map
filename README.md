# SB5 Mangrove Migration Barrier Map

**Status: Work in Progress**  
**Target: Prelim WIP June 2026 Workshop
**Team: Conservation International SB5 / UCSB Bren School**

---

## Research Question

Where can mangroves migrate inland in response to sea level rise along the Eastern Tropical Pacific coast, and where are they blocked by land use or terrain barriers?

Loss of mangrove migration potential represents permanent loss of sea turtle feeding habitat.

---

## Study Region

Pacific coast mangroves across four countries:
- Costa Rica
- Panama
- Colombia (Pacific coast only)
- Ecuador

Chile excluded — no Pacific mangroves due to cold Humboldt Current.

---

## Methods

### Data Sources

| Layer | Dataset | Resolution | Citation |
|---|---|---|---|
| Mangrove extent | Global Mangrove Watch v3 2020 | ~25m | Bunting et al. (2022) |
| Land cover | ESA WorldCover v200 2021 | 10m | Zanaga et al. (2022) |
| Terrain / slope | SRTM DEM | 30m | Farr et al. (2007) |
| Human modification | Human Modification Index | ~1km | Kennedy et al. (2025) — pending |

### Pipeline

1. Load GMW v3 2020 mangrove extent, clip to study region
2. Create 5km inland raster buffer from mangrove edge
3. Sample ESA WorldCover within buffer
4. Reclassify land cover → High / Medium / Low migration barrier
5. Add slope barrier from SRTM DEM (threshold: >5°)
6. Export GeoTIFFs and build interactive visualization

All processing done in Google Earth Engine via Google Colab.  
Colab notebook: `sb5_mangrove_migration_barrier.ipynb` (see `Sarayu-26/sb5_mangrove_barrier_map`)

### Land Cover Reclassification

| WorldCover Class | Code | Default Barrier Score |
|---|---|---|
| Tree cover | 10 | Low (1) |
| Shrubland | 20 | Low (1) |
| Grassland | 30 | Medium (2) |
| Cropland | 40 | High (3) |
| Built-up / Urban | 50 | High (3) |
| Bare / sparse vegetation | 60 | Low (1) |
| Permanent water | 80 | Medium (2) |
| Herbaceous wetland | 90 | Low (1) |
| Mangroves | 95 | Excluded (0) |
| Moss / lichen | 100 | Low (1) |

Slopes >5° classified as High barrier regardless of land cover.

---

## Repository Contents

```
sb5_mangrove_barrier_map/
├── app.R                              # R Shiny interactive map application
├── sb5_mangrove_barrier_map.Rproj     # RStudio project file
├── README.md
└── input/
    ├── worldcover_raw_5km_costa_rica.tif
    ├── worldcover_raw_5km_panama.tif
    ├── worldcover_raw_5km_colombia.tif
    ├── worldcover_raw_5km_ecuador.tif
    ├── mangrove_barrier_5km_lc_costa_rica.tif
    ├── mangrove_barrier_5km_lc_panama.tif
    ├── mangrove_barrier_5km_lc_colombia.tif
    ├── mangrove_barrier_5km_lc_ecuador.tif
    ├── mangrove_barrier_5km_slope_costa_rica.tif
    ├── mangrove_barrier_5km_slope_panama.tif
    ├── mangrove_barrier_5km_slope_colombia.tif
    └── mangrove_barrier_5km_slope_ecuador.tif
```

### Tif File Naming Convention

- `worldcover_raw_5km_[country].tif` — raw WorldCover class codes clipped to 5km buffer (feeds interactive reclassification in app)
- `mangrove_barrier_5km_lc_[country].tif` — pre-classified barrier scores, land cover only
- `mangrove_barrier_5km_slope_[country].tif` — pre-classified barrier scores, land cover + slope

---

## Running the Shiny App

### Requirements

```r
install.packages(c("shiny", "leaflet", "terra", "raster", "leaflet.extras", "dplyr", "sf"))
```

### Run locally

1. Clone this repo
2. Open `sb5_mangrove_barrier_map.Rproj` in RStudio
3. Open `app.R`
4. Click **Run App**

### App features

- **Tab 1 — 5km Land Cover:** Interactive reclassification — change barrier scores per land cover class and map updates live
- **Tab 2 — 5km + Slope:** Pre-computed barrier layer including steep terrain (>5°)
- **Tab 3 — Statistics:** Raw land cover breakdown and barrier summary per country, updates with Tab 1 dropdowns

---

## Known Limitations

1. **Grassland ambiguity:** WorldCover classifies cleared cattle pasture and natural grassland identically. Both currently coded as Medium barrier (conservative). Human Modification Index integration will resolve this.

2. **Slope threshold:** Pixels >5° classified as High barrier. Threshold is adjustable in Colab notebook Step 8.

3. **Pacific scope:** Colombia and Ecuador have mangroves on both coasts. Analysis clipped to Pacific side only.

4. **Mangrove layer:** Using GMW v3 2020 as proxy. Will swap in custom layer if provided by team.

---

## Pending Next Steps

- [ ] Small amount of mangroves in Peru, need to add
- [ ] Integrate Human Modification Index (Kennedy et al. 2025) to resolve grassland ambiguity
- [ ] Confirm Pacific-only scope for Colombia/Ecuador/ Costa Rica/Panama 
- [ ] Summary statistics table per country for workshop 
- [ ] Scope final deliverable 

---

## Data Citations

- Bunting, P. et al. (2022). Global Mangrove Watch Version 3.0. *Remote Sensing*, 14(15), 3657. https://doi.org/10.3390/rs14153657
- Zanaga, D. et al. (2022). ESA WorldCover 10m 2021 v200. https://doi.org/10.5281/zenodo.7254221
- Farr, T.G. et al. (2007). The shuttle radar topography mission. *Reviews of Geophysics*, 45(2). https://doi.org/10.1029/2005RG000183
- Kennedy, C.M. et al. (2025). Human Modification Index. *Scientific Data*. https://doi.org/10.1038/s41597-025-04892-2

---

## Contact
sramnath@bren.ucsb.edu
Sarayu Ramnath — UCSB Bren School of Environmental Science and Management  
Moore Center for Science | Conservation International (SB5)
