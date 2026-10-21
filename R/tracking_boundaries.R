# =====================================================================
# tracking_boundaries.R
# Download the World Bank official boundaries for the Data Coverage map
# (chapters/06-tracking.qmd) and write simplified GeoJSON files to
# chapters/tracking/. Needs internet access, no token. Run it from the
# repository's main folder; it only needs re-running when the World Bank
# updates its boundaries.
#
# Source: World Bank Official Boundaries, public ArcGIS feature services.
#   countries.geojson  country polygons (WB_ADM0_NA renamed to name)
#   disputed.geojson   disputed areas (e.g. Western Sahara), drawn as land
#                      with no country, so the map has no holes
#   borders.geojson    international boundary lines; style is "" (solid),
#                      "Dashed", "Tightly Dashed" or "Dotted"
# =====================================================================

library(sf)
library(dplyr)
library(httr2)
library(cli)

# ---- parameters -------------------------------------------------------------
base_url <- "https://services.arcgis.com/iQ1dY19aHwbSDYIF/arcgis/rest/services"
out_dir <- "chapters/tracking"
# The map is about 800 px wide, so 0.25 degrees is about 1.5 px
tolerance <- 0.25  # simplification tolerance, degrees
min_area <- 0.05   # polygon parts smaller than this (square degrees) are dropped,
                   # except the largest part of each country
# Coordinates are written with 2 decimals; GDAL turns shapes smaller than that
# into points, which d3 draws as circles. Drop them before writing.
min_part <- 0.001  # square degrees; no polygon part is kept below this
min_length <- 0.03 # degrees; boundary lines shorter than this are dropped

# The polygons are invalid under s2 ("Edge 0 crosses edge 4"); use planar GEOS
sf_use_s2(FALSE)

# ---- download one layer, paging through the server's record cap --------------
fetch_layer <- function(service, layer, fields) {
  pages <- list()
  offset <- 0
  repeat {
    resp <- request(sprintf("%s/%s/FeatureServer/%d/query", base_url, service, layer)) |>
      req_url_query(where = "1=1", outFields = paste(fields, collapse = ","),
                    outSR = 4326, f = "geojson",
                    resultOffset = offset, resultRecordCount = 1000) |>
      req_retry(max_tries = 3) |>
      req_perform()
    page <- st_read(resp_body_string(resp), quiet = TRUE)
    if (!nrow(page)) break
    pages[[length(pages) + 1]] <- page
    offset <- offset + nrow(page)
  }
  if (!length(pages)) cli_abort("No features returned from {service} layer {layer}.")
  cli_alert_info("{service}: {offset} features")
  do.call(rbind, pages)
}

simplify <- function(x) suppressWarnings(st_simplify(x, preserveTopology = TRUE, dTolerance = tolerance))

# Valid, simplified polygons; small islands are dropped, but every feature keeps
# its largest part so small countries stay on the map
simplify_polygons <- function(x, name_col) {
  x <- suppressWarnings(st_cast(st_collection_extract(st_make_valid(x), "POLYGON"), "POLYGON"))
  # planar area in square degrees (st_area on lon/lat would return square metres)
  x$area <- as.numeric(st_area(st_set_crs(x, NA)))
  largest <- ave(x$area, x[[name_col]], FUN = max) == x$area
  x <- simplify(x[x$area >= min_area | largest, ])
  x <- suppressWarnings(st_cast(st_collection_extract(st_make_valid(x), "POLYGON"), "POLYGON"))
  # drop parts too small to survive rounding (see min_part)
  x <- x[as.numeric(st_area(st_set_crs(x, NA))) >= min_part, ]
  x$name <- x[[name_col]]
  # one MULTIPOLYGON per name; do_union = FALSE keeps the parts as they are
  x <- x |> group_by(name) |> summarise(do_union = FALSE, .groups = "drop")
  st_cast(x, "MULTIPOLYGON")
}

write_geojson <- function(x, file) {
  path <- file.path(out_dir, file)
  if (file.exists(path)) file.remove(path)
  st_write(x, path, quiet = TRUE,
           layer_options = c("COORDINATE_PRECISION=2", "RFC7946=YES"))
  cli_alert_success("Wrote {path} ({round(file.size(path) / 1024)} KB)")
}

# ---- countries --------------------------------------------------------------
countries <- fetch_layer("Admin_LVL0_WBG_generalized_S", 0, "WB_ADM0_NA")
countries <- countries[countries$WB_ADM0_NA != "Antarctica", ]
write_geojson(simplify_polygons(countries, "WB_ADM0_NA"), "countries.geojson")

# ---- disputed areas ---------------------------------------------------------
disputed <- fetch_layer("World_Bank_Official_Boundaries_World_Disputed_Areas", 0, "WB_NAME")
disputed <- disputed[trimws(disputed$WB_NAME) != "", ]
write_geojson(simplify_polygons(disputed, "WB_NAME"), "disputed.geojson")

# ---- boundary lines ---------------------------------------------------------
borders <- fetch_layer("WB_GAD_Boundaries", 10, "Style")
borders <- suppressWarnings(st_crop(borders, xmin = -180, xmax = 180, ymin = -60, ymax = 90))
# cropping leaves some points; keep lines only
borders <- st_collection_extract(simplify(borders), "LINESTRING")
borders <- suppressWarnings(st_cast(st_cast(borders, "MULTILINESTRING"), "LINESTRING"))
# drop small closed loops (outlines of small islands and enclaves), which show as
# rings at map scale; open boundary lines are kept whatever their length
closed <- vapply(st_geometry(borders), function(g) {
  xy <- st_coordinates(g)
  isTRUE(all.equal(xy[1, 1:2], xy[nrow(xy), 1:2], check.attributes = FALSE))
}, logical(1))
size <- vapply(st_geometry(borders), function(g) {
  b <- st_bbox(g)
  max(b$xmax - b$xmin, b$ymax - b$ymin)
}, numeric(1))
borders <- borders[!(closed & size < 1.5), ]
borders <- borders[as.numeric(st_length(st_set_crs(borders, NA))) >= min_length, ]
borders$Style <- trimws(borders$Style)
borders$Style[is.na(borders$Style)] <- ""
names(borders)[names(borders) == "Style"] <- "style"
write_geojson(borders[, "style"], "borders.geojson")
