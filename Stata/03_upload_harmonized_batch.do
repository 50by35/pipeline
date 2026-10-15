/* =====================================================================
03_upload_harmonized_batch.do
50by35 pipeline — Step 3 (batch): validate, build indicator XML, and
upload harmonized files for multiple surveys via PRIMUS (Stata client).

Workflow:
  1. Scans data/processed/ for *_WELF.dta files and matches each to
     a Stata/*_WELF.do harmonization script.
  2. Writes batch/03_harmonized_uploads.csv with the discovered
     surveys. Edit the CSV to remove rows, add cpi/ppp overrides,
     etc. before the script proceeds.
  3. Reads the CSV back and processes each row.

Failures are logged and skipped; a summary is printed at the end.
===================================================================== */

version 18
clear
set more off

local outdir : env FIFTYBY35_PROCESSED
if `"`outdir'"' == "" local outdir "~/Github/50by35-data/data/processed"

local processid 40                       // FDP-harmonized-data
local zline     3.00                     // placeholder poverty line, $/day 2021 PPP
local manifest  "batch/03_harmonized_uploads.csv"

* ---- auto-generate manifest from processed .dta files ------------------------
local dtafiles : dir "`outdir'" files "*_WELF.dta"
local nsurv : word count `dtafiles'

if `nsurv' == 0 {
    di as error "No *_WELF.dta files found in `outdir'"
    exit 601
}

clear
set obs `nsurv'
gen str200 survey_id    = ""
gen str200 harm_script  = ""
gen str20  cpi_override = ""
gen str20  ppp_override = ""

local i = 0
foreach f of local dtafiles {
    local ++i
    * strip _WELF.dta to get survey_id
    local sid = subinstr("`f'", "_WELF.dta", "", 1)
    replace survey_id   = "`sid'"                              in `i'
    replace harm_script = "Stata/`sid'_WELF.do"                in `i'

    * warn if harmonization script doesn't exist
    capture confirm file "Stata/`sid'_WELF.do"
    if _rc {
        di as error "  WARNING: harmonization script not found for `sid'"
    }
}

export delimited using "`manifest'", replace
di as result "Wrote `manifest' with `nsurv' survey(s) found in `outdir'."
di as result "  Edit the CSV now to remove surveys, add overrides, etc."
di as result "  Press any key to continue (or break to abort)."
pause on
pause
pause off

* ---- read manifest back (user may have edited it) ----------------------------
import delimited using "`manifest'", clear stringcols(_all)
local nsurv = _N

forvalues i = 1/`nsurv' {
    local sid_`i'     = survey_id[`i']
    local hs_`i'      = harm_script[`i']
    local cpiov_`i'   = cpi_override[`i']
    local pppov_`i'   = ppp_override[`i']
}
clear

* ---- batch loop --------------------------------------------------------------
do "Stata/utils.do"
local nok   = 0
local nfail = 0

forvalues i = 1/`nsurv' {
    local sid        "`sid_`i''"
    local harmscript "`hs_`i''"
    local cpi_override "`cpiov_`i''"
    local ppp_override "`pppov_`i''"

    * treat blank overrides as missing
    if `"`cpi_override'"' == "" local cpi_override .
    if `"`ppp_override'"' == "" local ppp_override .

    local dtafile "`outdir'/`sid'_WELF.dta"

    di as result _n "=== [`i'/`nsurv'] `sid' ==="

    capture noisily {
        * ---- validation -------------------------------------------------------
        use "`dtafile'", clear
        do "Stata/validate_50by35.do"

        local ccode = code[1]
        local year  = year[1]

        * ---- CPI / PPP (latest datalibweb Support files; no fallback) ---------
        if mi(`cpi_override') | mi(`ppp_override') {
            dlw_cpi_ppp, country(`ccode') year(`year')
            local dlw_cpi = r(cpi)
            local dlw_ppp = r(ppp)
        }
        if mi(`cpi_override') local cpival = `dlw_cpi'
        else                  local cpival = `cpi_override'
        if mi(`ppp_override') local pppval = `dlw_ppp'
        else                  local pppval = `ppp_override'

        di as result "  CPI(`ccode',`year') = `cpival'   PPP2021(`ccode') = `pppval'"

        * ---- indicators + indicator XML (see Stata/utils.do) ------------------
        local xmlfile "`outdir'/`sid'.xml"
        sr_indicator_xml using "`xmlfile'", surveyid(`sid') cpi(`cpival') ///
            ppp(`pppval') zline(`zline')
        local primary "`r(primary)'"
        local sr     = string(r(sr_primary), "%8.6f")
        local hc     = string(r(hc_primary), "%8.6f")
        local srintl = string(r(sr_intl), "%8.6f")
        di as result "  Self-reliance share (`primary' line): `sr'"
        di as result "  Self-reliance share (z=$`zline'/day 2021 PPP): `srintl'"
        di as result "  Wrote `xmlfile'"

        * ---- upload -----------------------------------------------------------
        primus upload, processid(`processid') surveyid(`sid') ///
            type(harmonized) infile("`xmlfile'") xmlbl new
        local tranxid = r(prmTransId)
        di as result "  Opened transaction `tranxid'"

        primus upload, processid(`processid') surveyid(`sid') ///
            type(harmonized) folderpath(Data/Harmonized) infile("`dtafile'") tranxid(`tranxid')

        primus upload, processid(`processid') surveyid(`sid') ///
            type(harmonized) folderpath(Programs) infile("`harmscript'") tranxid(`tranxid')

        primus action, tranxid(`tranxid') processid(`processid') ///
            decision(confirm) comments(harmonized data ready for review)

        di as result "  Confirmed: `sid'"
    }

    if _rc == 0 {
        local ++nok
        local ok_`nok' "`sid' (transaction `tranxid') primary=`primary' SR=`sr' HC=`hc' SR_intl=`srintl'"
    }
    else {
        local ++nfail
        local fail_`nfail' "`sid' — rc = `=_rc'"
    }
}

* ---- summary -----------------------------------------------------------------
di as result _n "=== Batch summary (03_upload_harmonized) ==="
forvalues j = 1/`nok' {
    di as result "  OK:     `ok_`j''"
}
forvalues j = 1/`nfail' {
    di as error  "  FAILED: `fail_`j''"
}
if `nfail' > 0 {
    di as error "`nfail' of `nsurv' uploads failed"
}
