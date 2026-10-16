/* =====================================================================
get_poc_camps.do
Download the refugee formal and informal settlements from the UNHCR
Population of Concern (PoC) layer. Use it to look up the camp location
variables of the harmonized file (camp_pcode, camp_name, camp_lat,
camp_lon; see chapters/05-schema.qmd). Needs internet access, no token.

Stata cannot parse the JSON the layer returns, so the download runs in
Stata's Python integration (Stata 16+ with Python set up: see -help python-
and -python query-). Only the Python standard library is used.

Result: the dataset in memory, one observation per camp, with variables
iso3 camp_pcode camp_name camp_type camp_lat camp_lon
===================================================================== */

version 18
clear
set more off

* ---- parameters -----------------------------------------------------------
local layer_url "https://gis.unhcr.org/arcgis/rest/services/core_v2/wrl_prp_p_unhcr_PoC/FeatureServer/0/query"

* Scope of the schema: refugees (pop_type 52) living in formal (loc_subtype
* 38) or informal (39) settlements
local where "pop_type = 52 AND loc_subtype IN ('38', '39')"

* ---- query the layer ---------------------------------------------------------
* returnGeometry=false: the coordinates are the plain fields latitude_d and
* longitude_d (decimal degrees), so no geometry is needed.
python:
import json
import urllib.parse
import urllib.request
from sfi import Data, Macro, Missing

params = urllib.parse.urlencode({
    "where": Macro.getLocal("where"),
    "outFields": "iso3,pcode,gis_name,loc_subtype,latitude_d,longitude_d",
    "returnGeometry": "false",
    "f": "json",
})
url = Macro.getLocal("layer_url") + "?" + params

body = None
for attempt in range(3):
    try:
        with urllib.request.urlopen(url, timeout=60) as resp:
            body = json.load(resp)
        break
    except OSError as err:
        print("Request failed (try " + str(attempt + 1) + " of 3): " + str(err))
if body is None:
    raise SystemExit("Could not reach the UNHCR GIS server")
if "error" in body:
    raise SystemExit("UNHCR GIS returned an error: " + str(body["error"].get("message")))
# The server returns at most maxRecordCount (20,000) rows per request
if body.get("exceededTransferLimit"):
    raise SystemExit("More rows than one request returns: page the query with resultOffset")

rows = [f["attributes"] for f in body["features"]]

def text(key, fn=lambda v: v):
    return [fn(r[key]) if r[key] is not None else "" for r in rows]

cols = {
    "iso3":       text("iso3"),
    "camp_pcode": text("pcode"),
    "camp_name":  text("gis_name"),
    "camp_type":  text("loc_subtype", lambda v: "Formal" if v == "38" else "Informal"),
}
Data.setObsTotal(len(rows))
for name, values in cols.items():
    # width in bytes: names can hold accented characters (UTF-8)
    width = max([len(v.encode("utf-8")) for v in values] + [1])
    Data.addVarStr(name, width)
    Data.store(name, None, values)
for name, key in (("camp_lat", "latitude_d"), ("camp_lon", "longitude_d")):
    Data.addVarDouble(name)
    Data.store(name, None, [r[key] if r[key] is not None else Missing.getValue() for r in rows])
end

* ---- labels and check -------------------------------------------------------
label variable iso3       "Country code"
label variable camp_pcode "UNHCR camp location code (pcode)"
label variable camp_name  "Camp name"
label variable camp_type  "Camp type (formal or informal settlement)"
label variable camp_lat   "Camp latitude (decimal degrees)"
label variable camp_lon   "Camp longitude (decimal degrees)"

isid camp_pcode
di as result _N " camps downloaded"
describe
list iso3 camp_pcode camp_name camp_type camp_lat camp_lon in 1/10, noobs

* Example: add the layer's name and coordinates to a harmonized file by pcode
* use "<harmonized file>.dta", clear
* capture drop camp_name camp_lat camp_lon
* merge m:1 camp_pcode using "<poc camps file>.dta", ///
*     keepusing(camp_name camp_lat camp_lon) keep(master match) nogenerate
