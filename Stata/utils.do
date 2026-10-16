/* =====================================================================
utils.do
Shared Stata helpers. Run once to define the programs:
    do "Stata/utils.do"
===================================================================== */

/* ---- CPI and PPP from the datalibweb (DLW) Support files -------------------
Used by the upload scripts (and the Access chapter); the R equivalents are
dlw_support_tables() and dlw_cpi_ppp() in R/utils.R. The latest version of
    Support/Yearly_CPI_Final.dta     (annual CPI by country)
    Support/pppdata_allvintages.dta  (PPP by country, all ICP vintages)
is loaded from datalibweb (needs the datalibweb token to be set in Stata).
PIP is not used. There is no fallback: a missing country-year stops with an
error, and cpi_override / ppp_override can be set in the upload script.
------------------------------------------------------------------------- */

* Load the latest version of one Support file into memory (replaces the data
* in memory). Without a survey ID, datalibweb loads the latest version. Uses
* the datalibweb token already set in the package.
capture program drop dlw_support_load
program define dlw_support_load
    syntax , file(string)

    datalibweb, country(Support) years(2005) type(GMDRAW) filename(`file') clear
    if _N == 0 {
        di as error "Support/`file' could not be loaded from datalibweb"
        exit 601
    }
end

* CPI (survey year relative to pppyear, so 1 in pppyear) and PPP (LCU per
* international $, latest vintage of pppyear) for one country and year.
* Returns r(cpi) and r(ppp). Data in memory is kept.
capture program drop dlw_cpi_ppp
program define dlw_cpi_ppp, rclass
    syntax , country(string) year(integer) [pppyear(integer 2021)]

    preserve

    * ---- CPI -------------------------------------------------------------
    dlw_support_load, file(Yearly_CPI_Final.dta)
    keep if code == "`country'" & CoverageType == "National"
    foreach y in `year' `pppyear' {
        qui count if year == `y' & !missing(yearly_cpi)
        if r(N) != 1 {
            di as error "DLW Support CPI has no national value for `country' `y' - set cpi_override"
            exit 498
        }
    }
    qui sum yearly_cpi if year == `year'
    local cpi_y = r(mean)
    qui sum yearly_cpi if year == `pppyear'
    local cpi_base = r(mean)

    * ---- PPP: latest vintage of the ppp_`pppyear'_vX_vY columns ------------
    dlw_support_load, file(pppdata_allvintages.dta)
    keep if code == "`country'" & CoverageType == "National"
    qui ds ppp_`pppyear'_v*_v*
    local pppcol ""
    local bestkey = -1
    foreach c in `r(varlist)' {
        if regexm("`c'", "_v([0-9]+)_v([0-9]+)$") {
            local key = 1000 * real(regexs(1)) + real(regexs(2))
            if `key' > `bestkey' {
                local bestkey = `key'
                local pppcol "`c'"
            }
        }
    }
    if "`pppcol'" == "" {
        di as error "DLW Support PPP has no ppp_`pppyear'_* column"
        exit 111
    }
    if _N != 1 {
        di as error "DLW Support PPP has no national row for `country' - set ppp_override"
        exit 498
    }
    if missing(`pppcol'[1]) {
        di as error "DLW Support PPP (`pppcol') has no value for `country' - set ppp_override"
        exit 498
    }
    local ppp_value = `pppcol'[1]

    restore
    return scalar cpi = `cpi_y' / `cpi_base'
    return scalar ppp = `ppp_value'
end

/* ---- sr_indicator_xml ---------------------------------------------------
50by35 indicators and PRIMUS indicator XML for the harmonized file in
memory. Used by Stata/03_upload_harmonized.do and
Stata/03_upload_harmonized_batch.do; the R equivalent is
write_indicator_xml() in R/utils.R.

Two poverty lines:
  - National (primary, when natpovline is in the file): welfare_self and
    welfare are compared row by row with natpovline. All three are annual
    per capita LCU, so no CPI/PPP conversion is needed.
  - International (secondary): welfare_self and welfare are converted to
    $/day 2021 PPP and compared with zline.
Each indicator is reported for the whole sample and by camp status.

XML sections: Request (RequestKey, welfare, weight, By, N_By_Group,
nParamSets, plus a key;value CDATA block of run metadata), Result (one
<Welfare> per welfare variable, containing one <ByGroup> per N_By_Group
with a <DATASUMMARY> and one <CALCULATION> per nParamSets, each a
key;value CDATA block), and LOG_DETAIL (free-text CDATA, not shown in the
approval table).

One <Welfare> block (welfare_self); each CALCULATION names the welfare
variable it uses in its Variable key (welfare_self for the self-reliance
rate, welfare for the poverty rate).

The camp breakdown is NOT written as <ByGroup> elements: the PRIMUS
approval page shows no tables when <By> is set (tested with camp groups),
and shows only the "none" group when <By> is empty. Instead there is a
single "none" group, and every CALCULATION carries a Subgroup key (All,
Non-camp, Camp) so the breakdown appears as a column. nParamSets is the
number of CALCULATIONs: indicators x poverty lines x subgroups. Rows with
missing camp count in the "All" subgroup only. Values are written as
percentages with 2 decimals (e.g. 25.62%) to be readable in the approval
table. No CDATA block has a "key;value" header line, which the page would
show as a constant "Key" column. Key order is the column order in the
approval table.

Syntax:
    sr_indicator_xml using <xmlfile>, surveyid() cpi() ppp() zline()
Returns r(primary) (National or International) and the whole-sample
r(sr_primary), r(hc_primary), r(sr_intl), r(hc_intl) [, r(sr_nat), r(hc_nat)].
------------------------------------------------------------------------- */
capture program drop sr_indicator_xml
program define sr_indicator_xml, rclass
    syntax using/, surveyid(string) cpi(string) ppp(string) zline(string)

    capture confirm variable natpovline
    local hasnat  = !_rc
    local primary = cond(`hasnat', "National", "International")
    local nlines  = cond(`hasnat', 2, 1)
    local ccode   = code[1]
    local year    = year[1]
    local cpifmt  = strtrim(string(`cpi', "%12.6f"))
    local pppfmt  = strtrim(string(`ppp', "%12.6f"))
    local zfmt    = strtrim(string(`zline', "%9.2f"))

    * ---- indicator flags per row ----------------------------------------
    tempvar sri hci srn hcn
    qui gen byte `sri' = (welfare_self/365/`cpi'/`ppp') >= `zline'
    qui gen byte `hci' = (welfare/365/`cpi'/`ppp') < `zline'
    local calcs "sri hci"
    if `hasnat' {
        qui gen byte `srn' = welfare_self >= natpovline
        qui gen byte `hcn' = welfare < natpovline
        local calcs "sri hci srn hcn"
    }

    * ---- subgroups: All, then each non-missing camp value ----------------
    local sname_1 "All"
    local skey_1  ""
    local sif_1   "1"
    qui levelsof camp, local(camplevels)
    local nsub = 1
    foreach g of local camplevels {
        local ++nsub
        local sname_`nsub' = cond(`g' == 0, "Non-camp", "Camp")
        local skey_`nsub'  = cond(`g' == 0, "Noncamp", "Camp")
        local sif_`nsub'   "camp==`g'"
    }
    qui count if missing(camp)
    local nmisscamp = r(N)

    forvalues j = 1/`nsub' {
        local sublist = cond(`j' == 1, "`sname_`j''", "`sublist', `sname_`j''")
        qui count if `sif_`j''
        local n_`j' = r(N)
        qui sum weight if `sif_`j''
        local pop_`j' = strtrim(string(r(sum), "%20.0f"))
        foreach v in welfare welfare_self {
            qui sum `v' if `sif_`j'' [aw=weight]
            local m_`v'_`j' = strtrim(string(r(mean), "%20.2f"))
        }
        if `hasnat' {
            qui sum natpovline if `sif_`j'' [aw=weight]
            local m_natpovline_`j' = strtrim(string(r(mean), "%20.2f"))
        }
        foreach c of local calcs {
            qui sum ``c'' if `sif_`j'' [aw=weight]
            local raw_`c'_`j' = r(mean)
            local `c'_`j' = strtrim(string(100 * r(mean), "%9.2f")) + "%"
        }
    }

    * ---- write the XML ---------------------------------------------------
    tempname fh
    file open `fh' using `"`using'"', write replace

    file write `fh' `"<PRIMUS_ANALYSIS>"' _n
    file write `fh' `"  <Request>"' _n
    file write `fh' `"    <RequestKey><![CDATA[]]></RequestKey>"' _n
    file write `fh' `"    <welfare>welfare_self</welfare>"' _n
    file write `fh' `"    <weight>weight</weight>"' _n
    file write `fh' `"    <By></By>"' _n
    file write `fh' `"    <N_By_Group>1</N_By_Group>"' _n
    file write `fh' `"    <nParamSets>`=2 * `nlines' * `nsub''</nParamSets>"' _n
    file write `fh' `"    <![CDATA["' _n
    file write `fh' `"APP_ID;Stata"' _n
    file write `fh' `"DATETIME;`c(current_date)' `c(current_time)'"' _n
    file write `fh' `"COUNTRY_CODE;`ccode'"' _n
    file write `fh' `"FILENAME;`surveyid'_WELF.dta"' _n
    file write `fh' `"DATA_YEAR;`year'"' _n
    file write `fh' `"REF_YEAR;`year'"' _n
    file write `fh' `"PPP_YEAR;2021"' _n
    file write `fh' `"PRIMARY_LINE;`primary'"' _n
    file write `fh' `"    ]]>"' _n
    file write `fh' `"  </Request>"' _n
    file write `fh' `"  <Result>"' _n
    file write `fh' `"    <Welfare var="welfare_self" weight="weight">"' _n
    file write `fh' `"      <ByGroup byCondition="none">"' _n
    file write `fh' `"        <DATASUMMARY>"' _n
    file write `fh' `"          <![CDATA["' _n
    file write `fh' `"nRecs;`n_1'"' _n
    file write `fh' `"Population;`pop_1'"' _n
    forvalues j = 2/`nsub' {
        file write `fh' `"nRecs_`skey_`j'';`n_`j''"' _n
        file write `fh' `"Population_`skey_`j'';`pop_`j''"' _n
    }
    file write `fh' `"Mean_LCU_welfare;`m_welfare_1'"' _n
    file write `fh' `"Mean_LCU_welfare_self;`m_welfare_self_1'"' _n
    if `hasnat' file write `fh' `"Mean_LCU_natpovline;`m_natpovline_1'"' _n
    file write `fh' `"          ]]>"' _n
    file write `fh' `"        </DATASUMMARY>"' _n
    * self-reliance rate rows first, then poverty rate rows; within each, the
    * subgroups in order, national line before international line
    foreach ind in SelfRelianceRate PovertyRate {
        local sr = ("`ind'" == "SelfRelianceRate")
        local variable = cond(`sr', "welfare_self", "welfare")
        forvalues j = 1/`nsub' {
            foreach line in National International {
                if "`line'" == "National" & !`hasnat' continue
                local isnat = ("`line'" == "National")
                local c = cond(`sr', cond(`isnat', "srn", "sri"), cond(`isnat', "hcn", "hci"))
                local pline  = cond(`isnat', "National (natpovline)", "$`zfmt'/day (2021 PPP)")
                local cpiout = cond(`isnat', "NA", "`cpifmt'")
                local pppout = cond(`isnat', "NA", "`pppfmt'")
                file write `fh' `"        <CALCULATION>"' _n
                file write `fh' `"          <![CDATA["' _n
                file write `fh' `"Subgroup;`sname_`j''"' _n
                file write `fh' `"Indicator;`ind'"' _n
                file write `fh' `"Value;``c'_`j''"' _n
                file write `fh' `"Variable;`variable'"' _n
                file write `fh' `"PovertyLine;`pline'"' _n
                file write `fh' `"CPIValue;`cpiout'"' _n
                file write `fh' `"PPPValue;`pppout'"' _n
                file write `fh' `"          ]]>"' _n
                file write `fh' `"        </CALCULATION>"' _n
            }
        }
    }
    file write `fh' `"      </ByGroup>"' _n
    file write `fh' `"    </Welfare>"' _n
    file write `fh' `"  </Result>"' _n
    file write `fh' `"  <LOG_DETAIL>"' _n
    file write `fh' `"    <![CDATA["' _n
    file write `fh' `"50by35 self-reliance indicator for `surveyid'."' _n
    if `hasnat' file write `fh' `"Primary line: national poverty line, welfare_self >= natpovline (annual per capita LCU, row by row)."' _n
    else        file write `fh' `"Primary line: international (natpovline not in the file)."' _n
    file write `fh' `"International line: welfare_self / 365 / CPI(`ccode',`year')=`cpifmt' / PPP2021(`ccode')=`pppfmt' >= z=`zfmt' (placeholder, pending confirmation from the 50by35 methodology team)."' _n
    file write `fh' `"Subgroups: `sublist'. Rows with missing camp (counted in All only): `nmisscamp'."' _n
    forvalues j = 1/`nsub' {
        local nat = cond(`hasnat', "SelfReliance_national=`srn_`j'' Poverty_national=`hcn_`j'' ", "")
        file write `fh' `"`sname_`j'': `nat'SelfReliance_intl=`sri_`j'' Poverty_intl=`hci_`j''"' _n
    }
    file write `fh' `"    ]]>"' _n
    file write `fh' `"  </LOG_DETAIL>"' _n
    file write `fh' `"</PRIMUS_ANALYSIS>"' _n
    file close `fh'

    * ---- whole-sample results --------------------------------------------
    return scalar sr_intl = `raw_sri_1'
    return scalar hc_intl = `raw_hci_1'
    if `hasnat' {
        return scalar sr_nat     = `raw_srn_1'
        return scalar hc_nat     = `raw_hcn_1'
        return scalar sr_primary = `raw_srn_1'
        return scalar hc_primary = `raw_hcn_1'
    }
    else {
        return scalar sr_primary = `raw_sri_1'
        return scalar hc_primary = `raw_hci_1'
    }
    return local  primary "`primary'"
end
