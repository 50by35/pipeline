# =====================================================================
# 03_upload_harmonized.R
# 50by35 pipeline — Step 3: validate, build the indicator XML, and
# upload a harmonized file via PRIMUS (R client).
#
# The transaction starts from an indicator XML that records the 50by35
# self-reliance indicator for the reviewer to approve; the data and
# harmonization scripts are then attached to the same transaction.
#
# The primary indicator uses the national poverty line (natpovline) when it
# is in the file; the $3.00/day 2021 PPP line is always reported as a
# secondary indicator. Both are reported for the whole sample and by camp.
#
# The XML is written by write_indicator_xml() in R/utils.R. PRIMUS accepts a
# team-defined XML as long as it follows the main heading format
# (<PRIMUS_ANALYSIS><Request>...<Result>); the same structure is written
# by sr_indicator_xml in Stata/utils.do. For the full standard GMD indicator
# document (Gini, deciles, FGT at the fixed $3.00/$4.20/$8.30 lines),
# primus::create_xml() is an alternative, but it has no self-reliance
# field and its poverty-line set cannot be customized.
#
# CPI and 2021 PPP conversion factors come from the latest version of the
# datalibweb Support files (Yearly_CPI_Final.dta, pppdata_allvintages.dta;
# see dlw_support_tables() in R/utils.R) and apply only to the international
# line, z = $3.00/day 2021 PPP; natpovline is already in LCU.
#
# Requires: primus and dlw R packages + stored tokens; haven.
# Run from the repository root. The process name (FDP-harmonized-data)
# is illustrative — verify with primus_list_processes().
# =====================================================================

library(primus)
library(dlw)
library(haven)

source("R/validate_50by35.R")
source("R/utils.R")

# staging folder with the harmonized _WELF.dta files (the XML is written here too): edit this line
outdir <- "C:/path/to/staging"

# ---- parameters: pick ONE survey block --------------------------------------
process_name <- "FDP-harmonized-data"
zline        <- 3.00                    # placeholder poverty line, $/day 2021 PPP —
                                         # pending confirmation from the 50by35 methodology team

# survey_id   <- "TCD_2022_EHCVM_V01_M_V01_A_FDP"
# harm_script <- "Stata/TCD_2022_EHCVM_V01_M_V01_A_FDP_WELF.do"

survey_id   <- "COL_2023_GEIH_V01_M_V01_A_FDP"
harm_script <- "Stata/COL_2023_GEIH_V01_M_V01_A_FDP_WELF.do"

# survey_id   <- "UGA_2018_RHS_V01_M_V01_A_FDP"
# harm_script <- "Stata/UGA_2018_RHS_V01_M_V01_A_FDP_WELF.do"

dta_file <- file.path(outdir, paste0(survey_id, "_WELF.dta"))

# Leave NA to use the latest datalibweb Support CPI and PPP. To override,
# set cpi_override to the ratio CPI(survey year)/CPI(2021) and ppp_override
# to the 2021 PPP conversion factor (LCU per international $).
cpi_override <- NA
ppp_override <- NA

# ---- validation: any schema violation stops before upload --------------------
df <- read_dta(dta_file)
validate_50by35(df)

ccode <- df$code[1]
year  <- df$year[1]

# ---- CPI / PPP conversion factors from the datalibweb Support files ------------
# CPI: survey-year annual CPI relative to 2021 (1 in 2021).
# PPP: ICP 2021 conversion factor (LCU per 2021 international $), latest vintage.
# Both are the latest version in datalibweb; there is no fallback, so a missing
# country-year stops here (set cpi_override / ppp_override above instead).
if (is.na(cpi_override) || is.na(ppp_override)) {
  dlw_factors <- dlw_cpi_ppp(dlw_support_tables(), ccode, year)
}
cpi_value <- if (is.na(cpi_override)) dlw_factors$cpi else cpi_override
icp_value <- if (is.na(ppp_override)) dlw_factors$ppp else ppp_override

message("CPI(", ccode, ",", year, ") = ", cpi_value,
        "   PPP2021(", ccode, ") = ", icp_value)

# ---- 50by35 indicators + indicator XML (see R/utils.R) -------------------------
# National line (primary, if natpovline is in the file) and $3.00/day 2021 PPP
# line, for the whole sample and by camp status.
xml_file <- file.path(outdir, paste0(survey_id, ".xml"))
ind <- write_indicator_xml(df, xml_file, survey_id, cpi_value, icp_value, zline)
message(sprintf("Self-reliance share (%s line): %.4f", ind$primary, ind$sr_primary))
message(sprintf("Self-reliance share (z=$%.2f/day 2021 PPP): %.4f", zline, ind$sr_intl))
message("Wrote ", xml_file)

# ---- upload: XML opens the transaction, then attach data + programs -----------
up <- primus_upload(
  process_name = process_name,
  survey_id    = survey_id,
  type         = "harmonized",
  infile       = xml_file,
  xml          = xml_file
)
message("Opened transaction ", up$transaction_id)

primus_upload(
  process_name   = process_name,
  survey_id      = survey_id,
  type           = "harmonized",
  infile         = dta_file,
  folder_name    = "Data/Harmonized",
  transaction_id = up$transaction_id
)

# harmonization code makes the upload reproducible from source
primus_upload(
  process_name   = process_name,
  survey_id      = survey_id,
  type           = "harmonized",
  infile         = harm_script,
  folder_name    = "Programs",
  transaction_id = up$transaction_id
)

# ---- confirm the draft so it becomes visible to approvers ---------------------
primus_confirm(up$transaction_id, comments = "harmonized data ready for review")
message("Harmonized upload confirmed: ", survey_id,
        " (transaction ", up$transaction_id, ")")
