# =====================================================================
# 03_upload_harmonized_batch.R
# 50by35 pipeline — Step 3 (batch): validate, build indicator XML, and
# upload harmonized files for multiple surveys via PRIMUS (R client).
#
# Workflow:
#   1. Scans the staging folder (outdir) for *_WELF.dta files and matches
#      each to a Stata/*_WELF.do harmonization script.
#   2. Writes <outdir>/manifests/03_harmonized_uploads.csv with the discovered
#      surveys. Edit the CSV to remove rows, add cpi/ppp overrides,
#      etc. before the script proceeds.
#   3. Reads the CSV back and processes each row.
#
# Failures are logged and skipped; a summary is printed at the end.
# =====================================================================

library(primus)
library(dlw)
library(haven)

source("R/validate_50by35.R")
source("R/utils.R")

# staging folder with the harmonized _WELF.dta files: edit this line
outdir        <- "C:/path/to/staging"
process_name  <- "FDP-harmonized-data"
zline         <- 3.00  # placeholder poverty line, $/day 2021 PPP
manifest_file <- file.path(outdir, "manifests", "03_harmonized_uploads.csv")
dir.create(dirname(manifest_file), recursive = TRUE, showWarnings = FALSE)

# ---- auto-generate manifest from processed .dta files ------------------------
dta_files <- list.files(outdir, pattern = "_WELF\\.dta$", full.names = FALSE)

if (length(dta_files) == 0) {
  stop("No *_WELF.dta files found in ", outdir)
}

# derive survey_id by stripping _WELF.dta suffix
survey_ids  <- sub("_WELF\\.dta$", "", dta_files)

# match to harmonization scripts
harm_scripts <- file.path("Stata", paste0(survey_ids, "_WELF.do"))
script_exists <- file.exists(harm_scripts)

manifest <- data.frame(
  survey_id    = survey_ids,
  harm_script  = harm_scripts,
  cpi_override = "",
  ppp_override = "",
  stringsAsFactors = FALSE
)

write.csv(manifest, manifest_file, row.names = FALSE)

message("Wrote ", manifest_file, " with ", nrow(manifest), " survey(s) found in ", outdir, ".")
if (any(!script_exists)) {
  message("  WARNING: harmonization script not found for:")
  for (s in survey_ids[!script_exists]) message("    ", s)
}
message("  Edit the CSV now to remove surveys you don't want to upload,")
message("  add cpi/ppp overrides, etc. Then press ENTER to continue (or Ctrl-C to abort).")
readline()

# ---- read manifest back (user may have edited it) ----------------------------
manifest <- read.csv(manifest_file, stringsAsFactors = FALSE)

# ---- fetch the latest datalibweb Support CPI and PPP once for all surveys -----
dlw_tables <- dlw_support_tables()

# ---- batch loop --------------------------------------------------------------
results <- data.frame(
  survey_id      = character(),
  status         = character(),
  transaction_id = character(),
  primary_line   = character(),
  sr_primary     = numeric(),
  hc_primary     = numeric(),
  sr_intl        = numeric(),
  message        = character(),
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, ]
  sid         <- trimws(row$survey_id)
  harm_script <- trimws(row$harm_script)
  cpi_ov      <- if (!is.na(row$cpi_override) && nzchar(trimws(as.character(row$cpi_override))))
                   as.numeric(row$cpi_override) else NA
  ppp_ov      <- if (!is.na(row$ppp_override) && nzchar(trimws(as.character(row$ppp_override))))
                   as.numeric(row$ppp_override) else NA

  message("\n=== [", i, "/", nrow(manifest), "] ", sid, " ===")

  tryCatch({
    dta_file <- file.path(outdir, paste0(sid, "_WELF.dta"))

    # ---- validation -----------------------------------------------------------
    df <- read_dta(dta_file)
    validate_50by35(df)

    ccode <- df$code[1]
    yr    <- df$year[1]

    # ---- CPI / PPP (latest datalibweb Support files; no fallback) -------------
    if (is.na(cpi_ov) || is.na(ppp_ov)) {
      dlw_factors <- dlw_cpi_ppp(dlw_tables, ccode, yr)
    }
    cpi_value <- if (is.na(cpi_ov)) dlw_factors$cpi else cpi_ov
    icp_value <- if (is.na(ppp_ov)) dlw_factors$ppp else ppp_ov

    message("  CPI(", ccode, ",", yr, ") = ", cpi_value,
            "   PPP2021(", ccode, ") = ", icp_value)

    # ---- indicators + indicator XML (see R/utils.R) ----------------------------
    xml_file <- file.path(outdir, paste0(sid, ".xml"))
    ind <- write_indicator_xml(df, xml_file, sid, cpi_value, icp_value, zline)
    message(sprintf("  Self-reliance share (%s line): %.4f", ind$primary, ind$sr_primary))
    message(sprintf("  Self-reliance share (z=$%.2f/day 2021 PPP): %.4f", zline, ind$sr_intl))
    message("  Wrote ", xml_file)

    # ---- upload ---------------------------------------------------------------
    up <- primus_upload(
      process_name = process_name,
      survey_id    = sid,
      type         = "harmonized",
      infile       = xml_file,
      xml          = xml_file
    )
    tid <- up$transaction_id
    message("  Opened transaction ", tid)

    primus_upload(
      process_name   = process_name,
      survey_id      = sid,
      type           = "harmonized",
      infile         = dta_file,
      folder_name    = "Data/Harmonized",
      transaction_id = tid
    )

    primus_upload(
      process_name   = process_name,
      survey_id      = sid,
      type           = "harmonized",
      infile         = harm_script,
      folder_name    = "Programs",
      transaction_id = tid
    )

    primus_confirm(tid, comments = "harmonized data ready for review")
    message("  Confirmed: ", sid)

    results <- rbind(results, data.frame(
      survey_id = sid, status = "ok", transaction_id = tid,
      primary_line = ind$primary, sr_primary = ind$sr_primary,
      hc_primary = ind$hc_primary, sr_intl = ind$sr_intl, message = "",
      stringsAsFactors = FALSE
    ))

  }, error = function(e) {
    message("  FAILED: ", conditionMessage(e))
    results <<- rbind(results, data.frame(
      survey_id = sid, status = "FAILED", transaction_id = NA,
      primary_line = NA, sr_primary = NA, hc_primary = NA, sr_intl = NA,
      message = conditionMessage(e),
      stringsAsFactors = FALSE
    ))
  })
}

# ---- summary -----------------------------------------------------------------
message("\n=== Batch summary (03_upload_harmonized) ===")
for (j in seq_len(nrow(results))) {
  r <- results[j, ]
  if (r$status == "ok") {
    message(sprintf("  OK:     %s (transaction %s) primary=%s SR=%.4f HC=%.4f SR_intl=%.4f",
                    r$survey_id, r$transaction_id, r$primary_line, r$sr_primary,
                    r$hc_primary, r$sr_intl))
  } else {
    message("  FAILED: ", r$survey_id, " — ", r$message)
  }
}

n_fail <- sum(results$status != "ok")
if (n_fail > 0) warning(n_fail, " of ", nrow(results), " uploads failed")
