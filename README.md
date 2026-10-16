# 50by35 Microdata Pipeline

This repository contains the Quarto book documenting the pipeline to **harmonize and publish** microdata used to monitor the  self-reliance component of  UNHCR's **50by35 vision**: that 50 percent of refugees in protracted crises are self-reliant by 2035.

## Live Book

The rendered book is available at:
**https://50by35.github.io/pipeline/**

## Repository Structure

| Folder/File | Purpose |
|---|---|
| `chapters/` | Book chapters as `.qmd` files |
| `R/` | R scripts and functions |
| `Stata/` | Stata do-files |
| `wiki/` | Contributor guides and documentation |
| `.github/workflows/` | CI/CD pipeline for GitHub Pages |

Data is not stored in this repository. The upload scripts read and write harmonized files, indicator XML and batch manifests in a local **staging folder** that you set in each script (the `outdir` line), outside the repository.

## Quick Start for Contributors

See the **[`wiki/contributing.md`](wiki/contributing.md)** file for full setup instructions, including how to install Quarto, R, Stata, and how to write and preview chapters.

## Prerequisites

- [Quarto](https://quarto.org/docs/get-started/) ≥ 1.4
- R ≥ 4.4 and the packages in `renv.lock` (install via `renv::restore()`)
- Stata (any recent version) — required only if you are authoring or modifying Stata chunks
- Git

## Local Preview

```bash
# Clone the repo
git clone https://github.com/50by35/pipeline.git
cd pipeline

# Install R packages
Rscript -e "renv::restore()"

# Preview the book (live reload)
quarto preview

# Full render
quarto render
```

The rendered book will appear in `docs/`.
