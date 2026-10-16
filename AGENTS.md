# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, and others) working in this repository.

## What this repo is

A Quarto **book** plus the **R and Stata scripts** it documents. Together they describe and run
the pipeline used to harmonize, upload, review and publish microdata for monitoring the UNHCR
**50by35 vision** (50% of refugees in protracted crises self-reliant by 2035). The book is
published to GitHub Pages; the scripts are meant to be copied or run by uploaders and approvers
on their own machines. No data lives in this repository.

## Commands

```bash
quarto preview     # live-reload local preview while editing chapters
quarto render      # full render to docs/ (gitignored)
```

- There are no automated tests or linters. Verify changes by running the relevant script or
  validator (see Testing below) and by rendering the book.
- `docs/` and `.quarto/` are build output and are gitignored. CI
  (`.github/workflows/publish.yml`) renders the book and deploys it to GitHub Pages on every push
  to `main`. Do not commit rendered output.
- The only executed chunk in the book is a Mermaid diagram in `index.qmd`. All R and Stata code
  in the chapters is in plain fenced blocks and is **not** executed at render time, so CI needs no
  Stata license and there is no `_freeze/` cache to maintain.

## Repository layout

| Path | Purpose |
|---|---|
| `index.qmd`, `chapters/` | The book. Order and parts are set in `_quarto.yml`, not by the filesystem |
| `R/`, `Stata/` | Pipeline scripts, shared helpers and schema validators (parallel implementations) |
| `Stata/*_WELF.do` | Example harmonization scripts, one per survey (15 today) |
| `wiki/` | Contributor setup docs (Quarto, R/Stata, renv). Not part of the book |

Book structure: `index.qmd`, then Part "Pipeline" (`01-raw-upload`, `02-harmonization`,
`03-harmonized-upload`), Part "Access" (`04-access`), Part "Reference" (`05-schema`). When adding,
removing or reordering chapters, edit `book.chapters` in `_quarto.yml`.

## The pipeline the book documents

1. **Upload raw data** (`01-raw-upload.qmd`): PRIMUS process `FDPRaw-data` (id 39), unless the
   data is already on datalibweb. An approver reviews it before it is available for harmonization.
2. **Harmonize data** (`02-harmonization.qmd`): guidelines and 15 example scripts, not a recipe.
   Harmonization is survey specific.
3. **Upload harmonized data** (`03-harmonized-upload.qmd`): PRIMUS process `FDP-harmonized-data`
   (id 40). The file is validated against the schema, an indicator XML is built, and the data,
   script and XML are uploaded. Regional and global approvers then review it.
4. **Access data** (`04-access.qmd`): datalibweb collections `FDPRAW` (raw) and `FDP` (harmonized,
   module `WELF`), via the `datalibweb` Stata package or the `dlw` R package.
5. **Schema** (`05-schema.qmd`): the contract for the harmonized `.dta` file.

## Conventions for the book

- Chapters 01, 03 and 04 follow one pattern: steps at a glance, numbered step by step, an "If
  something goes wrong" table, then a reference section ("How it works"). Keep it.
- R and Stata examples sit side by side in `::: {.panel-tabset group="language"}` blocks. **When
  you change one language, check the other tab and the matching step in the other upload
  chapter.** Keep chapter code consistent with the scripts in `R/` and `Stata/`.
- Chapters 01 to 03 tell users to run scripts from the repository's main folder, because scripts
  load helpers and validators by relative path.
- Do not state something about a tool, server or API in the docs unless you have run it. Several
  earlier assumptions were wrong (see Gotchas).

## Scripts (`R/` and `Stata/`)

- Steps are numbered: `01_upload_raw`, `02_review_raw`, `03_upload_harmonized`,
  `04_review_harmonized`, each with a `_batch` variant. R and Stata versions must stay equivalent.
- **Folders are plain editable lines**, not environment variables: `outdir` is a local **staging
  folder** outside the repository (harmonized `.dta`, generated XML, and batch manifests in
  `<outdir>/manifests/`), and `rawroot` is the raw data folder. Placeholders (`C:/path/to/...`)
  fail until edited, on purpose.
- **Tokens** are set once in the client packages (`primus_set_token`, `primus register`,
  `dlw_set_token`, `datalibweb, token(...)`). Never put a token in a script, a doc or a commit.
- **Shared helpers**: `R/utils.R` and `Stata/utils.do` hold the CPI/PPP lookup and the indicator
  XML writer. Put cross-script logic there. The R and Stata XML output must be identical.
- **CPI and PPP** come from the latest datalibweb Support files (`Yearly_CPI_Final.dta`,
  `pppdata_allvintages.dta`), 2021 framework, with **no fallback**: a missing value stops the
  script and the user sets `cpi_override`/`ppp_override`. The World Bank PIP is not used.
- **Indicators**: the primary self-reliance line is `natpovline` (national line, annual per
  capita LCU, no CPI/PPP) when the file has it; the $3.00/day 2021 PPP line is always reported
  and is a **placeholder** pending the 50by35 methodology team. Rates are reported for the whole
  sample and by camp status.
- **Indicator XML** must keep the layout the PRIMUS approval page can display: one `<Welfare>`,
  one `<ByGroup byCondition="none">` with `<By>` empty, camp breakdown as a `Subgroup` key, and
  the documented key order. Other group names and by-groups were tested and render no tables.

## Schema and validators

`chapters/05-schema.qmd` is authoritative. The validators `Stata/validate_50by35.do` and
`R/validate_50by35.R` enforce it and must agree with each other and with the chapter. Two checks
are Stata only: storage types (haven reads every Stata numeric as double) and leftover notes or
characteristics. When you change a rule, update **both** validators, the validation table in
`05-schema.qmd`, and any description in `02-harmonization.qmd` and `03-harmonized-upload.qmd`.
The schema is a **working draft** pending sign-off from the methodology team.

## Testing

- Validators: run both on real files, and on deliberately broken copies for any new check. Stata
  is run in batch mode, for example `stata-mp -b do file.do`, when installed locally.
- Uploads: test only as **drafts**. Omit the confirm step (`primus_confirm`, or
  `primus action ... decision(confirm)`) so approvers never see the test. The `primus` clients
  cannot delete a draft; the user deletes it in the PRIMUS web interface. Only one open
  transaction is allowed per survey, and a `V02` survey ID needs `V01` approved.
- Never upload or confirm real submissions without being asked, and never delete or overwrite
  the user's data files.

## Gotchas

- Stata: a `/*` anywhere inside a `/* ... */` header comment (for example `Stata/*_WELF.do`)
  opens a nested comment and silently comments out the rest of the script.
- Stata: `compress` only changes storage types. It does not remove notes, characteristics or
  the dataset label; the harmonization scripts clear those explicitly before saving.
- `dlw` in R: the `FDP` server holds both harmonized and raw files. `FDPRAW` cannot be queried
  from R (HTTP 500). Stata uses `type(FDPRAW)` for raw files.
- Standard errors in the chapter 04 example need the survey design: clusters are `psu` (or
  `hhid` when there is no complete `psu`), plus `strata` if present. Estimate subgroups as
  subpopulations of the whole design.
- The `data/` and `batch/` folders no longer exist in the repository, and `*.dta` is gitignored.
  Never commit microdata.

## Wiki vs chapters

`wiki/` holds contributor-facing setup docs. Keep contributor documentation there, not in
`chapters/`. Pages link to each other by relative path, and Quarto does not check those links, so
check them when renaming or removing a file.

## Commits

Use ASCII quotes and hyphens in code, comments and commit messages. Do not add co-author or
"generated with" lines. Commit only when asked.
