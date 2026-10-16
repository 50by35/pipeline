/* =====================================================================
03_upload_harmonized.do
50by35 pipeline — Step 3: validate, build the indicator XML, and upload
a harmonized file via PRIMUS (Stata client).

The transaction starts from an indicator XML (uploaded with the xmlbl
flag) that records the 50by35 self-reliance indicator for the reviewer
to approve; the data and harmonization scripts are then attached to the
same transaction.

The primary indicator uses the national poverty line (natpovline) when it
is in the file; the $3.00/day 2021 PPP line is always reported as a
secondary indicator. Both are reported for the whole sample and by camp.
The XML is written by sr_indicator_xml in Stata/utils.do.

CPI and 2021 PPP conversion factors come from the latest version of the
datalibweb Support files (Yearly_CPI_Final.dta, pppdata_allvintages.dta;
see dlw_cpi_ppp in Stata/utils.do) and apply only to the international
line, z = $3.00/day 2021 PPP; natpovline is already in LCU.

Requires: primus Stata package + registered token; datalibweb package with
its token set.
Run from the repository root. Process id 40 (FDP-harmonized-data) is
illustrative — verify with: primus download, meta
===================================================================== */

version 18
clear
set more off

* folder that holds your harmonized _WELF.dta files: edit this line
local outdir "C:/path/to/processed"

* ---- parameters: uncomment ONE survey block ------------------------------
local processid 40                       // FDP-harmonized-data
local zline     3.00                     // placeholder poverty line, $/day 2021 PPP —
                                          // pending confirmation from the 50by35 methodology team

local surveyid  "TCD_2022_EHCVM_V01_M_V01_A_FDP"
local harmscript "Stata/TCD_2022_EHCVM_V01_M_V01_A_FDP_WELF.do"

*local surveyid  "COL_2023_GEIH_V01_M_V01_A_FDP"
*local harmscript "Stata/COL_2023_GEIH_V01_M_V01_A_FDP_WELF.do"

*local surveyid  "UGA_2018_RHS_V01_M_V01_A_FDP"
*local harmscript "Stata/UGA_2018_RHS_V01_M_V01_A_FDP_WELF.do"

local dtafile "`outdir'/`surveyid'_WELF.dta"

* Leave as . to use the latest datalibweb Support CPI and PPP. To override,
* set cpi_override to the ratio CPI(survey year)/CPI(2021) and ppp_override
* to the 2021 PPP conversion factor (LCU per international $).
local cpi_override .
local ppp_override .

* ---- validation: any schema violation stops before upload -----------------
use "`dtafile'", clear
do "Stata/validate_50by35.do"
do "Stata/utils.do"

local ccode = code[1]
local year  = year[1]

* ---- CPI / PPP conversion factors from the datalibweb Support files -------
* CPI: survey-year annual CPI relative to 2021 (1 in 2021).
* PPP: ICP 2021 conversion factor (LCU per 2021 international $), latest vintage.
* Both are the latest version in datalibweb; there is no fallback, so a
* missing country-year stops here (set cpi_override / ppp_override above).
if mi(`cpi_override') | mi(`ppp_override') {
    dlw_cpi_ppp, country(`ccode') year(`year')
    local dlw_cpi = r(cpi)
    local dlw_ppp = r(ppp)
}
if mi(`cpi_override') local cpival = `dlw_cpi'
else                  local cpival = `cpi_override'
if mi(`ppp_override') local pppval = `dlw_ppp'
else                  local pppval = `ppp_override'

di as result "CPI(`ccode',`year') = `cpival'   PPP2021(`ccode') = `pppval'"

* ---- 50by35 indicators + indicator XML (see Stata/utils.do) ---------------
* National line (primary, if natpovline is in the file) and $3.00/day 2021
* PPP line, for the whole sample and by camp status.
local xmlfile "`outdir'/`surveyid'.xml"
sr_indicator_xml using "`xmlfile'", surveyid(`surveyid') cpi(`cpival') ///
    ppp(`pppval') zline(`zline')
di as result "Self-reliance share (`r(primary)' line): " %8.6f r(sr_primary)
di as result "Self-reliance share (z=$`zline'/day 2021 PPP): " %8.6f r(sr_intl)
di as result "Wrote `xmlfile'"

* ---- upload: XML opens the transaction, then attach data + programs --------
primus upload, processid(`processid') surveyid(`surveyid') ///
    type(harmonized) infile("`xmlfile'") xmlbl new
local tranxid = r(prmTransId)
di as result "Opened transaction `tranxid'"

primus upload, processid(`processid') surveyid(`surveyid') ///
    type(harmonized) folderpath(Data/Harmonized) infile("`dtafile'") tranxid(`tranxid')

* harmonization code makes the upload reproducible from source
primus upload, processid(`processid') surveyid(`surveyid') ///
    type(harmonized) folderpath(Programs) infile("`harmscript'") tranxid(`tranxid')

* ---- confirm the draft so it becomes visible to approvers ------------------
primus action, tranxid(`tranxid') processid(`processid') ///
    decision(confirm) comments(harmonized data ready for review)

di as result "Harmonized upload confirmed: `surveyid' (transaction `tranxid')"
