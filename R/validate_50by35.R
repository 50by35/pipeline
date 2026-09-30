# =====================================================================
# validate_50by35.R
# Validate a harmonized data frame against the 50by35 schema
# (see chapters/05-schema.qmd). Stops with an error on any violation,
# preventing upload of a non-conforming file.
#
# Usage:  source("R/validate_50by35.R")
#         df <- haven::read_dta("<harmonized file>.dta")
#         validate_50by35(df)
# =====================================================================

validate_50by35 <- function(df) {
  fail <- function(...) stop("SCHEMA ERROR: ", ..., call. = FALSE)

  mandatory <- c("code", "year", "survname", "hhid", "pid", "welfare",
                 "welfare_type", "welfare_self", "weight", "camp", "urban")
  missing_vars <- setdiff(mandatory, names(df))
  if (length(missing_vars))
    fail("mandatory variable(s) missing: ", paste(missing_vars, collapse = ", "))

  # identifiers: strings, 3-letter country code, unique hhid x pid
  for (v in c("code", "survname", "hhid", "pid"))
    if (!is.character(df[[v]])) fail(v, " must be a string")
  for (v in c("code", "survname", "hhid", "pid"))
    if (anyNA(df[[v]]) || any(df[[v]] == "")) fail(v, " must be non-missing and non-empty")
  if (any(!grepl("^[A-Z]{3}$", df$code))) fail("code must be a 3-letter uppercase code")
  if (anyDuplicated(df[c("hhid", "pid")])) fail("hhid + pid do not uniquely identify rows")

  numeric_vars <- c("year", "welfare", "welfare_type", "welfare_self", "weight", "camp", "urban")
  for (v in numeric_vars)
    if (!is.numeric(df[[v]])) fail(v, " must be numeric")
  integer_vars <- c("year", "welfare_type", "camp", "urban")
  for (v in intersect(integer_vars, names(df)))
    if (!is.integer(df[[v]])) fail(v, " must use an integer storage type")
  double_vars <- c("welfare", "welfare_self", "weight")
  for (v in double_vars)
    if (typeof(df[[v]]) != "double") fail(v, " must use double storage")

  # missing values (camp/urban may be missing)
  for (v in c("year", "welfare", "welfare_type", "welfare_self", "weight"))
    if (anyNA(df[[v]])) fail("missing values in mandatory variable ", v)
  # value ranges
  if (any(df$year < 1990 | df$year > 2035 | df$year != floor(df$year)))
    fail("year must be an integer from 1990-2035")
  if (any(df$welfare <= 0)) fail("welfare must be strictly positive")
  if (any(df$weight <= 0)) fail("weight must be strictly positive")
  if (any(df$welfare_self < 0)) fail("welfare_self must be non-negative")
  if (any(df$welfare_self > df$welfare)) fail("welfare_self greater than welfare")
  if (!all(df$welfare_type %in% 1:3) || any(df$welfare_type != floor(df$welfare_type)))
    fail("welfare_type outside integer codes 1-3")
  for (v in c("camp", "urban"))
    if (!all(df[[v]] %in% c(0, 1, NA))) fail(v, " must be 0/1 or missing")

  expected_labels <- list(
    welfare_type = c("Consumption" = 1, "Income" = 2, "Expenditure" = 3),
    male = c("Female" = 0, "Male" = 1),
    urban = c("Rural" = 0, "Urban" = 1),
    camp = c("Non-camp" = 0, "Camp" = 1),
    educat4 = c("No education" = 1, "Primary" = 2, "Secondary" = 3, "Tertiary" = 4),
    empstat = c("Employed" = 1, "Unemployed" = 2, "Out of labor force" = 3, "Not applicable" = 4)
  )
  for (v in intersect(names(expected_labels), names(df))) {
    actual <- attr(df[[v]], "labels")
    expected <- expected_labels[[v]]
    if (is.null(actual) || !setequal(names(actual), names(expected)) ||
        any(as.numeric(actual[names(expected)]) != as.numeric(expected)))
      fail(v, " must have the schema's exact value labels")
  }

  # optional variables, when present
  if ("hhsize" %in% names(df)) {
    if (!is.integer(df$hhsize)) fail("hhsize must use an integer storage type")
    if (any(df$hhsize < 1 | df$hhsize != floor(df$hhsize), na.rm = TRUE))
      fail("hhsize must be an integer of at least 1")
    # mismatch with the person-record count is a warning: rosters can be
    # incomplete, and refugee-only samples keep a subset of members
    npid <- ave(seq_len(nrow(df)), df$hhid, FUN = length)
    n_bad <- sum(df$hhsize != npid, na.rm = TRUE)
    if (n_bad > 0)
      message("SCHEMA WARNING: hhsize differs from person-record count for ",
              n_bad, " rows (incomplete roster?)")
  }
  if ("age" %in% names(df)) {
    if (typeof(df$age) != "double") fail("age must use double storage")
    if (any(df$age < 0 | df$age > 120 | (df$age >= 5 & df$age != floor(df$age)), na.rm = TRUE))
      fail("age outside 0-120 or non-integer for age 5 and above")
  }
  if ("male" %in% names(df) && !all(df$male %in% c(0, 1, NA)))
    fail("male must be 0/1 or missing")
  if ("educat4" %in% names(df) && !all(df$educat4 %in% c(1:4, NA)))
    fail("educat4 outside 1-4")
  if ("empstat" %in% names(df) && !all(df$empstat %in% c(1:4, NA)))
    fail("empstat outside 1-4")
  for (v in intersect(c("strata", "psu"), names(df))) {
    if (!is.integer(df[[v]])) fail(v, " must use an integer storage type")
    if (any(df[[v]] != floor(df[[v]]), na.rm = TRUE)) fail(v, " must contain integers")
  }
  for (v in intersect(c("male", "educat4", "empstat"), names(df))) {
    if (!is.integer(df[[v]])) fail(v, " must use an integer storage type")
    if (any(df[[v]] != floor(df[[v]]), na.rm = TRUE)) fail(v, " must contain integer codes")
  }
  if ("natpovline" %in% names(df) &&
      (typeof(df$natpovline) != "double" || any(df$natpovline <= 0, na.rm = TRUE)))
    fail("natpovline must use double storage and be positive")
  if ("arrival_year" %in% names(df) &&
      (!is.integer(df$arrival_year) || any(df$arrival_year < 1900 | df$arrival_year > df$year |
            df$arrival_year != floor(df$arrival_year), na.rm = TRUE)))
    fail("arrival_year must use integer storage and be from 1900 through survey year")

  message("50by35 schema validation PASSED (", nrow(df), " observations)")
  invisible(TRUE)
}
