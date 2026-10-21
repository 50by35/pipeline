# =====================================================================
# tracking_snapshot.R
# Refresh the data behind the Data Coverage appendix
# (chapters/06-tracking.qmd). Reads the datalibweb FDP catalog, downloads
# every harmonized WELF file and records, per survey, the share of rows with
# a non-missing value for each schema variable.
#
# Needs the datalibweb token set once (dlw_set_token) and the World Bank
# intranet or VPN. Run it from the repository's main folder, then review and
# commit the changed chapters/tracking/coverage.json. CI cannot run it: it has
# no token. No microdata is written, only counts and percentages.
# =====================================================================

library(dlw)
library(jsonlite)
library(cli)

# ---- parameters -------------------------------------------------------------
out_file <- "chapters/tracking/coverage.json"

# Variables of chapters/05-schema.qmd, in schema order
schema_vars <- c(
  "code", "year", "survname", "hhid", "pid", "welfare", "welfare_self",
  "welfare_type", "weight", "camp", "urban", "natpovline", "hhsize", "age",
  "male", "educat4", "empstat", "arrival_year", "camp_pcode", "camp_name",
  "camp_lat", "camp_lon", "strata", "psu"
)

# ---- catalog ----------------------------------------------------------------
catalog <- as.data.frame(dlw_server_catalog("FDP"))
# survey folder inside the file path, e.g. UGA_2018_RHS_V01_M_V01_A_FDP
catalog$folder <- sub("^[^/]+/[^/]+/([^/]+)/.*$", "\\1", catalog$FilePath)

welf <- catalog[!is.na(catalog$Module) & catalog$Module == "WELF" &
                  catalog$Ext == "dta", ]
if (!nrow(welf)) cli_abort("No harmonized WELF files found in the FDP catalog.")

# raw surveys (master folder, e.g. PER_2024_ENAHOPV_V01_M) with no harmonized file
masters <- unique(catalog[grepl("_V[0-9]+_M$", catalog$folder),
                          c("Country", "Year", "Survey", "folder")])
harm_masters <- sub("_V[0-9]+_A_FDP$", "", welf$folder)
raw_only <- masters[!masters$folder %in% harm_masters, ]

# share of rows missing; the empty string counts as missing
pct_missing <- function(x) {
  if (is.character(x)) x[x == ""] <- NA
  round(100 * mean(is.na(x)), 1)
}

# ---- one record per harmonized survey ---------------------------------------
surveys <- lapply(seq_len(nrow(welf)), function(i) {
  r <- welf[i, ]
  cli_alert_info("Reading {r$FileName}")
  d <- as.data.frame(dlw_get_data(
    country_code = r$Country, filename = r$FileName, server = "FDP", year = r$Year
  ))
  miss <- vapply(schema_vars, function(v)
    if (v %in% names(d)) pct_missing(d[[v]]) else NA_real_, numeric(1))
  list(
    surveyid = sub("_WELF\\.dta$", "", r$FileName),
    code = r$Country, year = r$Year, survey = r$Survey,
    vermast = r$Vermast, veralt = r$Veralt, uploaded = r$Timestamp,
    n_ind = nrow(d), n_hh = length(unique(d$hhid)),
    camp_share = if (all(is.na(d$camp))) NA else
      round(100 * weighted.mean(d$camp == 1, d$weight, na.rm = TRUE), 1),
    welfare_type = as.integer(d$welfare_type[1]),
    missing = as.list(miss)
  )
})

# ---- write ------------------------------------------------------------------
dir.create(dirname(out_file), showWarnings = FALSE, recursive = TRUE)
write_json(
  list(
    generated = format(Sys.Date()),
    schema_vars = schema_vars,
    surveys = surveys,
    raw_only = data.frame(code = raw_only$Country, year = raw_only$Year,
                          survey = raw_only$Survey, surveyid = raw_only$folder)
  ),
  out_file, auto_unbox = TRUE, na = "null", pretty = TRUE
)
cli_alert_success(
  "Wrote {out_file}: {length(surveys)} harmonized and {nrow(raw_only)} raw-only surveys."
)
