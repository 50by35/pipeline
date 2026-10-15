# Shared R utility functions
# Add helper functions used across multiple chapters here.

# ---- CPI and PPP from the datalibweb (DLW) Support files -----------------------
# Used by the upload scripts (and the Access chapter). The latest version of
#   Support/Yearly_CPI_Final.dta     (annual CPI by country)
#   Support/pppdata_allvintages.dta  (PPP by country, all ICP vintages)
# is downloaded with dlw::dlw_get_gmd_support(filename = ) (needs a DLW token;
# it reports the version it used). PIP is not used. There is no fallback: a
# missing country-year stops with an error, and cpi_override / ppp_override can
# be set in the upload script instead.

# Download the latest CPI and PPP Support tables once.
dlw_support_tables <- function() {
  list(cpi = as.data.frame(dlw::dlw_get_gmd_support(filename = "Yearly_CPI_Final.dta")),
       ppp = as.data.frame(dlw::dlw_get_gmd_support(filename = "pppdata_allvintages.dta")))
}

# CPI (survey year relative to ppp_year, so 1 in ppp_year) and PPP (LCU per
# international $, latest vintage of ppp_year) for one country and year.
dlw_cpi_ppp <- function(tables, ccode, year, ppp_year = 2021) {
  cpi <- tables$cpi[tables$cpi$code == ccode & tables$cpi$CoverageType == "National", ]
  cpi_at <- function(y) {
    v <- cpi$yearly_cpi[cpi$year == y]
    if (length(v) != 1 || is.na(v))
      stop("DLW Support CPI has no national value for ", ccode, " ", y,
           " - set cpi_override")
    v
  }

  ppp <- tables$ppp[tables$ppp$code == ccode & tables$ppp$CoverageType == "National", ]
  cols <- grep(sprintf("^ppp_%d_v[0-9]+_v[0-9]+$", ppp_year), names(ppp), value = TRUE)
  if (!length(cols)) stop("DLW Support PPP has no ppp_", ppp_year, "_* column")
  parts <- do.call(rbind, regmatches(cols, regexec("_v([0-9]+)_v([0-9]+)$", cols)))
  col <- cols[order(as.integer(parts[, 2]), as.integer(parts[, 3]))][length(cols)]
  ppp_value <- ppp[[col]]
  if (length(ppp_value) != 1 || is.na(ppp_value))
    stop("DLW Support PPP (", col, ") has no national value for ", ccode,
         " - set ppp_override")

  list(cpi = cpi_at(year) / cpi_at(ppp_year), ppp = ppp_value)
}

# ---- 50by35 indicators and PRIMUS indicator XML ------------------------------
# Used by R/03_upload_harmonized.R and R/03_upload_harmonized_batch.R; the
# Stata equivalent is sr_indicator_xml in Stata/utils.do.
#
# Two poverty lines:
#   - National (primary, when natpovline is in the file): welfare_self and
#     welfare are compared row by row with natpovline. All three are annual
#     per capita LCU, so no CPI/PPP conversion is needed.
#   - International (secondary): welfare_self and welfare are converted to
#     $/day 2021 PPP and compared with zline.
# Each indicator is reported for the whole sample and by camp status.

# Self-reliance share and poverty headcount at each line for one subgroup.
sr_indicators <- function(df, cpi_value, icp_value, zline) {
  to_ppp <- function(x) x / 365 / cpi_value / icp_value
  out <- list(
    sr_intl = weighted.mean(to_ppp(df$welfare_self) >= zline, df$weight),
    hc_intl = weighted.mean(to_ppp(df$welfare) < zline, df$weight)
  )
  if ("natpovline" %in% names(df)) {
    out$sr_nat <- weighted.mean(df$welfare_self >= df$natpovline, df$weight)
    out$hc_nat <- weighted.mean(df$welfare < df$natpovline, df$weight)
  }
  out
}

# Write the indicator XML (PRIMUS XML schema for harmonized data) and return
# the whole-sample indicators plus the primary line used.
#
# Sections: Request (RequestKey, welfare, weight, By, N_By_Group, nParamSets,
# plus a key;value CDATA block of run metadata), Result (one <Welfare> per
# welfare variable, containing one <ByGroup> per N_By_Group with a
# <DATASUMMARY> and one <CALCULATION> per nParamSets, each a key;value CDATA
# block), and LOG_DETAIL (free-text CDATA, not shown in the approval table).
#
# One <Welfare> block (welfare_self); each CALCULATION names the welfare
# variable it uses in its Variable key (welfare_self for the self-reliance
# rate, welfare for the poverty rate).
#
# The camp breakdown is NOT written as <ByGroup> elements: the PRIMUS
# approval page shows no tables when <By> is set (tested with camp groups),
# and shows only the "none" group when <By> is empty. Instead there is a
# single "none" group, and every CALCULATION carries a Subgroup key (All,
# Non-camp, Camp) so the breakdown appears as a column. nParamSets is the
# number of CALCULATIONs: indicators x poverty lines x subgroups. Rows with
# missing camp count in the "All" subgroup only. Values are written as
# percentages with 2 decimals (e.g. 25.62%) to be readable in the approval table.
write_indicator_xml <- function(df, xml_file, survey_id, cpi_value, icp_value,
                                zline) {
  kv <- function(...) {
    vals <- c(...)
    paste(names(vals), vals, sep = ";")
  }
  # No "key;value" header line in any CDATA block: the approval page would
  # show it as a constant "Key" column.
  cdata_rows <- function(lines) c("<![CDATA[", lines, "]]>")

  has_nat <- "natpovline" %in% names(df)
  primary <- if (has_nat) "National" else "International"
  ccode   <- df$code[1]
  yr      <- df$year[1]

  camp        <- as.integer(df$camp)
  camp_levels <- sort(unique(camp[!is.na(camp)]))
  camp_labels <- c("0" = "Non-camp", "1" = "Camp")[as.character(camp_levels)]
  by_camp     <- lapply(camp_levels, function(l) df[camp %in% l, ])
  names(by_camp) <- camp_labels
  subgroups <- c(list(All = df), by_camp)
  inds <- lapply(subgroups, sr_indicators, cpi_value, icp_value, zline)

  calc <- function(indicator, variable, line_type, subgroup, value) {
    intl <- line_type == "International"
    # Key order is the column order in the approval table (CPIValue and
    # PPPValue are placed by PRIMUS next to the welfare set).
    cdata_rows(kv(
      Subgroup    = subgroup,
      Indicator   = indicator,
      Value       = sprintf("%.2f%%", 100 * value),
      Variable    = variable,
      PovertyLine = if (intl) sprintf("$%.2f/day (2021 PPP)", zline) else "National (natpovline)",
      CPIValue    = if (intl) sprintf("%.6f", cpi_value) else "NA",
      PPPValue    = if (intl) sprintf("%.6f", icp_value) else "NA"
    ))
  }
  wrap_calc <- function(x)
    c("        <CALCULATION>", paste0("          ", x), "        </CALCULATION>")

  # Counts first (all, then by camp), then the means.
  summary <- c(
    kv(nRecs      = nrow(df),
       Population = sprintf("%.0f", sum(df$weight))),
    unlist(lapply(names(by_camp), function(s) {
      key <- sub("-", "", s)   # "Non-camp" -> "Noncamp"
      kv(setNames(nrow(by_camp[[s]]), paste0("nRecs_", key)),
         setNames(sprintf("%.0f", sum(by_camp[[s]]$weight)), paste0("Population_", key)))
    })),
    kv(Mean_LCU_welfare      = sprintf("%.2f", weighted.mean(df$welfare, df$weight)),
       Mean_LCU_welfare_self = sprintf("%.2f", weighted.mean(df$welfare_self, df$weight))),
    if (has_nat) kv(Mean_LCU_natpovline =
                      sprintf("%.2f", weighted.mean(df$natpovline, df$weight)))
  )

  # Self-reliance rate rows first, then poverty rate rows; within each, the
  # subgroups in order, national line before international line.
  indicator_calcs <- function(indicator, wvar, nat_key, intl_key)
    unlist(lapply(names(subgroups), function(s) {
      ind <- inds[[s]]
      c(if (has_nat) wrap_calc(calc(indicator, wvar, "National", s, ind[[nat_key]])),
        wrap_calc(calc(indicator, wvar, "International", s, ind[[intl_key]])))
    }))
  all_calcs <- c(
    indicator_calcs("SelfRelianceRate", "welfare_self", "sr_nat", "sr_intl"),
    indicator_calcs("PovertyRate",      "welfare",      "hc_nat", "hc_intl")
  )

  request_cdata <- cdata_rows(kv(
    APP_ID       = "R",
    DATETIME     = format(Sys.time(), "%d %b %Y %H:%M:%S"),
    COUNTRY_CODE = ccode,
    FILENAME     = paste0(survey_id, "_WELF.dta"),
    DATA_YEAR    = yr,
    REF_YEAR     = yr,
    PPP_YEAR     = "2021",
    PRIMARY_LINE = primary
  ))

  fmt_ind <- function(s, ind) {
    nat <- if (has_nat) sprintf("SelfReliance_national=%.2f%% Poverty_national=%.2f%% ",
                                100 * ind$sr_nat, 100 * ind$hc_nat) else ""
    sprintf("%s: %sSelfReliance_intl=%.2f%% Poverty_intl=%.2f%%", s, nat,
            100 * ind$sr_intl, 100 * ind$hc_intl)
  }
  log_detail_cdata <- c(
    "<![CDATA[",
    sprintf("50by35 self-reliance indicator for %s.", survey_id),
    if (has_nat)
      "Primary line: national poverty line, welfare_self >= natpovline (annual per capita LCU, row by row)."
    else
      "Primary line: international (natpovline not in the file).",
    sprintf(paste0("International line: welfare_self / 365 / CPI(%s,%s)=%.6f / PPP2021(%s)=%.6f >= z=%.2f",
                   " (placeholder, pending confirmation from the 50by35 methodology team)."),
            ccode, yr, cpi_value, ccode, icp_value, zline),
    sprintf("Subgroups: %s. Rows with missing camp (counted in All only): %d.",
            paste(names(subgroups), collapse = ", "), sum(is.na(camp))),
    unlist(Map(fmt_ind, names(subgroups), inds)),
    "]]>"
  )

  n_lines <- if (has_nat) 2L else 1L
  writeLines(c(
    "<PRIMUS_ANALYSIS>",
    "  <Request>",
    "    <RequestKey><![CDATA[]]></RequestKey>",
    "    <welfare>welfare_self</welfare>",
    "    <weight>weight</weight>",
    "    <By></By>",
    "    <N_By_Group>1</N_By_Group>",
    sprintf("    <nParamSets>%d</nParamSets>", 2L * n_lines * length(subgroups)),
    paste0("    ", request_cdata),
    "  </Request>",
    "  <Result>",
    '    <Welfare var="welfare_self" weight="weight">',
    '      <ByGroup byCondition="none">',
    "        <DATASUMMARY>",
    paste0("          ", cdata_rows(summary)),
    "        </DATASUMMARY>",
    all_calcs,
    "      </ByGroup>",
    "    </Welfare>",
    "  </Result>",
    "  <LOG_DETAIL>",
    paste0("    ", log_detail_cdata),
    "  </LOG_DETAIL>",
    "</PRIMUS_ANALYSIS>"
  ), xml_file)

  total <- inds$All
  total$primary    <- primary
  total$sr_primary <- if (has_nat) total$sr_nat else total$sr_intl
  total$hc_primary <- if (has_nat) total$hc_nat else total$hc_intl
  invisible(total)
}
