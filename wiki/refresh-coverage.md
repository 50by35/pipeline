# Refreshing the Data Coverage page

The appendix `chapters/06-tracking.qmd` ("Data Coverage") shows which harmonized
surveys are approved on datalibweb and how complete each schema variable is. It is
drawn from a committed snapshot, `chapters/tracking/coverage.json`, because CI
renders the book without a datalibweb token. The snapshot is refreshed by hand.

## What the page shows

- **Source.** The datalibweb `FDP` collection, read with the `dlw` R package. A
  harmonized file appears there only after regional and global approval. A raw survey
  (master folder `..._V##_M`) with no harmonized file is shown as "raw data only".
- **Non-missing share** is the share of rows (people) with a value. Empty strings count
  as missing. Hatched cells are variables that are not in the file.
- **Core** is the 9 mandatory variables that may not be missing (`code`, `year`,
  `survname`, `hhid`, `pid`, `welfare`, `welfare_self`, `welfare_type`, `weight`). The
  validators enforce this, so the column is complete in every approved file. `camp`
  and `urban` are mandatory but may be missing in every row.
- **Variable availability** counts the harmonized surveys with at least one non-missing
  value for the variable.
- **Not shown:** the share of the refugee population the surveys represent. Survey
  weights are on different scales across files, and the UNHCR totals that would be the
  denominator depend on which populations each survey covers. Deferred for now.

## When to refresh

After new harmonized surveys are approved, or an approved file is replaced by a new
version. The page shows the snapshot date.

## Steps

1. Connect to the World Bank intranet or VPN, and make sure the datalibweb token is set
   in R (`dlw_set_token()`, see the Access chapter).
2. From the repository's main folder, run:

   ```r
   source("R/tracking_snapshot.R")
   ```

   The script reads the `FDP` catalog, downloads every harmonized `WELF` file and
   writes `chapters/tracking/coverage.json`. This takes a few minutes. It writes only
   counts and percentages, never microdata.
3. Review the change: `git diff chapters/tracking/coverage.json`.
4. Preview the page with `quarto preview`, and commit the updated JSON.

## Adding a country

The country names and regions are listed at the top of the page, in the `NAMES` and
`REGION` cells of `chapters/06-tracking.qmd`. A survey from a country that is not
listed there breaks the page, so add the country before committing a snapshot that
includes it. The name must match the World Bank name in
`chapters/tracking/countries.geojson` exactly (for example "West Bank and Gaza",
"Islamic Republic of Iran"), or the country is not shaded on the map.

## Map boundaries

The map uses the World Bank Official Boundaries: country polygons, disputed areas
(such as Western Sahara) and boundary lines, which are dashed or dotted where a
boundary is disputed or undetermined. `R/tracking_boundaries.R` downloads them from
the World Bank's public ArcGIS services (no token), simplifies them for a small map
and writes `countries.geojson`, `disputed.geojson` and `borders.geojson` to
`chapters/tracking/`. Re-run it only when the World Bank updates its boundaries.
Keep the disclaimer under the map.

## Schema changes

The variable list in `R/tracking_snapshot.R` (`schema_vars`) and the groups in
`chapters/06-tracking.qmd` (`CORE`, `CAMPURB`, `OPT`) follow `chapters/05-schema.qmd`.
Update them when a variable is added or removed.
