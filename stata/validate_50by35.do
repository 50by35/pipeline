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
foreach v in year {
    local vtype : type `v'
    if "`vtype'" != "int" {
        di as error "SCHEMA ERROR: `v' must use int storage"
        exit 459
    }
}
foreach v in welfare welfare_self weight {
    local vtype : type `v'
    if "`vtype'" != "double" {
        di as error "SCHEMA ERROR: `v' must use double storage"
        exit 459
    }
}
foreach v in welfare_type camp urban {
    local vtype : type `v'
    if "`vtype'" != "byte" {
        di as error "SCHEMA ERROR: `v' must use byte storage"
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
    if "`vtype'" != "int" {
        di as error "SCHEMA ERROR: hhsize must use int storage"
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
    if "`vtype'" != "double" {
        di as error "SCHEMA ERROR: age must use double storage"
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
    if "`vtype'" != "byte" {
        di as error "SCHEMA ERROR: male must use byte storage"
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
    if "`vtype'" != "byte" {
        di as error "SCHEMA ERROR: educat4 must use byte storage"
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
    if "`vtype'" != "byte" {
        di as error "SCHEMA ERROR: empstat must use byte storage"
        exit 459
    }
    capture assert (inrange(empstat, 1, 4) & empstat==floor(empstat)) | missing(empstat)
    if _rc {
        di as error "SCHEMA ERROR: empstat outside 1-4"
        exit 459
    }
}
capture confirm variable natpovline
if !_rc {
    local vtype : type natpovline
    if "`vtype'" != "double" {
        di as error "SCHEMA ERROR: natpovline must use double storage"
        exit 459
    }
    capture assert natpovline > 0 | missing(natpovline)
    if _rc {
        di as error "SCHEMA ERROR: natpovline must be positive or missing"
        exit 459
    }
}
capture confirm variable arrival_year
if !_rc {
    local vtype : type arrival_year
    if "`vtype'" != "int" {
        di as error "SCHEMA ERROR: arrival_year must use int storage"
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
        local expected_type "int"
        if "`v'" == "psu" local expected_type "long"
        local vtype : type `v'
        if "`vtype'" != "`expected_type'" {
            di as error "SCHEMA ERROR: `v' must use `expected_type' storage"
            exit 459
        }
        capture assert `v'==floor(`v') | missing(`v')
        if _rc {
            di as error "SCHEMA ERROR: `v' must contain integers"
            exit 459
        }
    }
}

di as result "50by35 schema validation PASSED (`=_N' observations)"
