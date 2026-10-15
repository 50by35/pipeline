/* =====================================================================
validate_50by35.do
Validate the dataset in memory against the 50by35 schema
(see chapters/05-schema.qmd). Any violation stops with an error,
preventing upload of a non-conforming file.

Usage:  use "<harmonized file>.dta", clear
        do "Stata/validate_50by35.do"
===================================================================== */

* ---- mandatory variables present -----------------------------------------
foreach v in code year survname hhid pid welfare welfare_type welfare_self ///
             weight camp urban {
    capture confirm variable `v'
    if _rc {
        di as error "SCHEMA ERROR: mandatory variable `v' is missing"
        exit 459
    }
}

* ---- identifier types and uniqueness --------------------------------------
capture confirm string variable code survname hhid pid
if _rc {
    di as error "SCHEMA ERROR: code, survname, hhid and pid must be strings"
    exit 459
}
local code_type : type code
if "`code_type'" != "str3" {
    di as error "SCHEMA ERROR: code must be str3"
    exit 459
}
capture assert strlen(code)==3 & regexm(code, "^[A-Z][A-Z][A-Z]$")
if _rc {
	di as error "SCHEMA ERROR: code must be a 3-letter uppercase code"
	exit 459
}
capture isid hhid pid
if _rc {
    di as error "SCHEMA ERROR: hhid + pid do not uniquely identify observations"
    exit 459
}

* ---- numeric variable types -------------------------------------------------
foreach v in year welfare welfare_type welfare_self weight camp urban {
    capture confirm numeric variable `v'
    if _rc {
        di as error "SCHEMA ERROR: `v' must be numeric"
        exit 459
    }
}
* Storage: integer variables may use any integer type (byte/int/long), since
* -compress- picks the smallest exact type. Real-valued variables must not be
* float, which keeps only ~7 significant digits; -compress- never demotes
* double to float (it may demote integer-valued doubles to byte/int/long,
* which is exact), so a float was created as float in the harmonization.
foreach v in year welfare_type camp urban {
    local vtype : type `v'
    if !inlist("`vtype'", "byte", "int", "long") {
        di as error "SCHEMA ERROR: `v' must use an integer storage type (byte/int/long)"
        exit 459
    }
}
foreach v in welfare welfare_self weight {
    local vtype : type `v'
    if "`vtype'" == "float" {
        di as error "SCHEMA ERROR: `v' must not use float storage (use double)"
        exit 459
    }
}

* ---- missing values in mandatory variables (camp/urban may be missing) ----
foreach v in year welfare welfare_type welfare_self weight {
    capture assert !missing(`v')
    if _rc {
        di as error "SCHEMA ERROR: missing values in mandatory variable `v'"
        exit 459
    }
}
capture assert hhid != "" & pid != ""
if _rc {
    di as error "SCHEMA ERROR: empty hhid or pid"
    exit 459
}
capture assert survname != ""
if _rc {
    di as error "SCHEMA ERROR: empty survname"
    exit 459
}

* ---- value ranges ----------------------------------------------------------
capture assert inrange(year, 1990, 2035) & year==floor(year)
if _rc {
	di as error "SCHEMA ERROR: year must be an integer from 1990-2035"
    exit 459
}
capture assert welfare > 0
if _rc {
    di as error "SCHEMA ERROR: welfare must be strictly positive"
    exit 459
}
capture assert weight > 0
if _rc {
    di as error "SCHEMA ERROR: weight must be strictly positive"
    exit 459
}
capture assert welfare_self >= 0
if _rc {
    di as error "SCHEMA ERROR: welfare_self must be non-negative"
    exit 459
}
capture assert welfare_self <= welfare
if _rc {
    di as error "SCHEMA ERROR: welfare_self greater than welfare"
    exit 459
}
capture assert inrange(welfare_type, 1, 3) & welfare_type==floor(welfare_type)
if _rc {
	di as error "SCHEMA ERROR: welfare_type outside integer codes 1-3"
    exit 459
}
foreach v in camp urban {
    capture assert inlist(`v', 0, 1) | missing(`v')
    if _rc {
        di as error "SCHEMA ERROR: `v' must be 0/1 or missing"
        exit 459
    }
}

* ---- categorical value labels ----------------------------------------------
local cats "welfare_type male urban camp educat4 empstat"
foreach v of local cats {
    capture confirm variable `v'
    if !_rc {
        local vl : value label `v'
        if "`vl'" == "" {
            di as error "SCHEMA ERROR: `v' has no value label"
            exit 459
        }
        if "`v'" == "welfare_type" {
            local l1 : label `vl' 1
            local l2 : label `vl' 2
            local l3 : label `vl' 3
            if `"`l1'"' != "Consumption" | `"`l2'"' != "Income" | `"`l3'"' != "Expenditure" {
                di as error "SCHEMA ERROR: welfare_type value labels do not match schema"
                exit 459
            }
        }
        if "`v'" == "male" {
            local l0 : label `vl' 0
            local l1 : label `vl' 1
            if `"`l0'"' != "Female" | `"`l1'"' != "Male" {
                di as error "SCHEMA ERROR: male value labels do not match schema"
                exit 459
            }
        }
        if "`v'" == "urban" {
            local l0 : label `vl' 0
            local l1 : label `vl' 1
            if `"`l0'"' != "Rural" | `"`l1'"' != "Urban" {
                di as error "SCHEMA ERROR: urban value labels do not match schema"
                exit 459
            }
        }
        if "`v'" == "camp" {
            local l0 : label `vl' 0
            local l1 : label `vl' 1
            if `"`l0'"' != "Non-camp" | `"`l1'"' != "Camp" {
                di as error "SCHEMA ERROR: camp value labels do not match schema"
                exit 459
            }
        }
        if "`v'" == "educat4" {
            local l1 : label `vl' 1
            local l2 : label `vl' 2
            local l3 : label `vl' 3
            local l4 : label `vl' 4
            if `"`l1'"' != "No education" | `"`l2'"' != "Primary" | `"`l3'"' != "Secondary" | `"`l4'"' != "Tertiary" {
                di as error "SCHEMA ERROR: educat4 value labels do not match schema"
                exit 459
            }
        }
        if "`v'" == "empstat" {
            local l1 : label `vl' 1
            local l2 : label `vl' 2
            local l3 : label `vl' 3
            local l4 : label `vl' 4
            if `"`l1'"' != "Employed" | `"`l2'"' != "Unemployed" | `"`l3'"' != "Out of labor force" | `"`l4'"' != "Not applicable" {
                di as error "SCHEMA ERROR: empstat value labels do not match schema"
                exit 459
            }
        }
    }
}

* ---- optional variables, when present --------------------------------------
capture confirm variable hhsize
if !_rc {
    local vtype : type hhsize
    if !inlist("`vtype'", "byte", "int", "long") {
        di as error "SCHEMA ERROR: hhsize must use an integer storage type (byte/int/long)"
        exit 459
    }
    capture assert (hhsize >= 1 & hhsize==floor(hhsize)) | missing(hhsize)
    if _rc {
		di as error "SCHEMA ERROR: hhsize must be an integer of at least 1"
        exit 459
    }
    * hhsize vs. the number of person records per hhid: a mismatch is
    * common when the individual roster is incomplete (members without
    * person records), so this is a WARNING, not an error. hhsize keeps
    * the survey's household size — the welfare denominator.
    tempvar npid
    bysort hhid: gen `npid' = _N
    qui count if hhsize != `npid' & !missing(hhsize)
    if r(N) > 0 {
        di as txt "SCHEMA WARNING: hhsize differs from person-record count per hhid for " r(N) " obs (incomplete roster?)"
    }
    drop `npid'
}
capture confirm variable age
if !_rc {
    local vtype : type age
    if "`vtype'" == "float" {
        di as error "SCHEMA ERROR: age must not use float storage (use double)"
        exit 459
    }
    capture assert (inrange(age, 0, 120) & (age < 5 | age==floor(age))) | missing(age)
    if _rc {
		di as error "SCHEMA ERROR: age outside 0-120 or non-integer for age 5 and above"
        exit 459
    }
}
capture confirm variable male
if !_rc {
    local vtype : type male
    if !inlist("`vtype'", "byte", "int", "long") {
        di as error "SCHEMA ERROR: male must use an integer storage type (byte/int/long)"
        exit 459
    }
    capture assert inlist(male, 0, 1) | missing(male)
    if _rc {
        di as error "SCHEMA ERROR: male must be 0/1 or missing"
        exit 459
    }
}
capture confirm variable educat4
if !_rc {
    local vtype : type educat4
    if !inlist("`vtype'", "byte", "int", "long") {
        di as error "SCHEMA ERROR: educat4 must use an integer storage type (byte/int/long)"
        exit 459
    }
    capture assert (inrange(educat4, 1, 4) & educat4==floor(educat4)) | missing(educat4)
    if _rc {
        di as error "SCHEMA ERROR: educat4 outside 1-4"
        exit 459
    }
}
capture confirm variable empstat
if !_rc {
    local vtype : type empstat
    if !inlist("`vtype'", "byte", "int", "long") {
        di as error "SCHEMA ERROR: empstat must use an integer storage type (byte/int/long)"
        exit 459
    }
    capture assert (inrange(empstat, 1, 4) & empstat==floor(empstat)) | missing(empstat)
    if _rc {
        di as error "SCHEMA ERROR: empstat outside 1-4"
        exit 459
    }
}
* natpovline is optional, but when present it drives the primary
* self-reliance indicator, so every row must have a value
capture confirm variable natpovline
if !_rc {
    local vtype : type natpovline
    if "`vtype'" == "float" {
        di as error "SCHEMA ERROR: natpovline must not use float storage (use double)"
        exit 459
    }
    capture assert natpovline > 0 & !missing(natpovline)
    if _rc {
        di as error "SCHEMA ERROR: natpovline must be positive and non-missing in every row"
        exit 459
    }
}
capture confirm variable arrival_year
if !_rc {
    local vtype : type arrival_year
    if !inlist("`vtype'", "byte", "int", "long") {
        di as error "SCHEMA ERROR: arrival_year must use an integer storage type (byte/int/long)"
        exit 459
    }
    capture assert (inrange(arrival_year, 1900, year) & arrival_year==floor(arrival_year)) | missing(arrival_year)
    if _rc {
        di as error "SCHEMA ERROR: arrival_year outside 1900-survey year"
        exit 459
    }
}
foreach v in strata psu {
    capture confirm variable `v'
    if !_rc {
        local vtype : type `v'
        if !inlist("`vtype'", "byte", "int", "long") {
            di as error "SCHEMA ERROR: `v' must use an integer storage type (byte/int/long)"
            exit 459
        }
        capture assert `v'==floor(`v') | missing(`v')
        if _rc {
            di as error "SCHEMA ERROR: `v' must contain integers"
            exit 459
        }
    }
}

* ---- variable labels (warning only) -----------------------------------------
* Expected text is the Label column of chapters/05-schema.qmd. Labels
* document the file and do not affect the indicators, so a mismatch is a
* warning, not an error.
local lab_code         "Country code"
local lab_year         "Survey year"
local lab_survname     "Survey name"
local lab_hhid         "Household identifier"
local lab_pid          "Person identifier"
local lab_welfare      "Welfare aggregate (LCU, annual per capita)"
local lab_welfare_self "Self-reliance-adjusted welfare (LCU, annual per capita)"
local lab_welfare_type "Welfare measure type"
local lab_weight       "Sampling weight"
local lab_camp         "Camp/non-camp"
local lab_urban        "Urban/rural"
local lab_hhsize       "Household size"
local lab_age          "Age (years)"
local lab_male         "Sex"
local lab_educat4      "Highest education (4 cat.)"
local lab_empstat      "Employment status"
local lab_strata       "Sampling strata"
local lab_psu          "Primary sampling unit"
local lab_natpovline   "National poverty line (LCU, annual per capita)"
local lab_arrival_year "Year of arrival"
foreach v in code year survname hhid pid welfare welfare_self welfare_type ///
             weight camp urban hhsize age male educat4 empstat strata psu ///
             natpovline arrival_year {
    capture confirm variable `v'
    if !_rc {
        local actual : variable label `v'
        if `"`actual'"' != `"`lab_`v''"' {
            di as txt `"SCHEMA WARNING: `v' variable label is "`actual'", expected "`lab_`v''""'
        }
    }
}

di as result "50by35 schema validation PASSED (`=_N' observations)"
