# =====================================================================
# get_poc_camps.R
# Download the refugee formal and informal settlements from the UNHCR
# Population of Concern (PoC) layer. Use it to look up the camp location
# variables of the harmonized file (camp_pcode, camp_name, camp_lat,
# camp_lon; see chapters/05-schema.qmd). Needs internet access, no token.
#
# Result: a data frame `poc_camps`, one row per camp, with columns
#   iso3, camp_pcode, camp_name, camp_type, camp_lat, camp_lon
# =====================================================================

library(httr2)
library(dplyr)
library(cli)

# ---- parameters -------------------------------------------------------------
layer_url <- "https://gis.unhcr.org/arcgis/rest/services/core_v2/wrl_prp_p_unhcr_PoC/FeatureServer/0/query"

# Scope of the schema: refugees (pop_type 52) living in formal (loc_subtype
# 38) or informal (39) settlements
where <- "pop_type = 52 AND loc_subtype IN ('38', '39')"

# ---- query the layer ---------------------------------------------------------
# returnGeometry = false: the coordinates are the plain fields latitude_d and
# longitude_d (decimal degrees), so no geometry is needed.
resp <- request(layer_url) |>
  req_url_query(
    where = where,
    outFields = "iso3,pcode,gis_name,loc_subtype,latitude_d,longitude_d",
    returnGeometry = "false",
    f = "json"
  ) |>
  req_retry(max_tries = 3) |>
  req_perform()

body <- resp_body_json(resp, simplifyVector = TRUE)

if (!is.null(body$error))
  cli_abort("UNHCR GIS returned an error: {body$error$message}")
# The server returns at most `maxRecordCount` (20,000) rows per request
if (isTRUE(body$exceededTransferLimit))
  cli_abort("More rows than one request returns: page the query with resultOffset")

# ---- tidy ----------------------------------------------------------------------
poc_camps <- body$features$attributes |>
  as_tibble() |>
  transmute(
    iso3,
    camp_pcode = pcode,
    camp_name  = gis_name,
    camp_type  = if_else(loc_subtype == "38", "Formal", "Informal"),
    camp_lat   = latitude_d,
    camp_lon   = longitude_d
  )

cli_alert_success("{nrow(poc_camps)} camps downloaded")
glimpse(poc_camps)

# Example: add the layer's name and coordinates to a harmonized file by pcode
# df <- haven::read_dta("<harmonized file>.dta")
# df <- left_join(select(df, -any_of(c("camp_name", "camp_lat", "camp_lon"))),
#                 select(poc_camps, camp_pcode, camp_name, camp_lat, camp_lon),
#                 by = "camp_pcode")
