# jmvplus

A [jamovi](https://www.jamovi.org) module that extends the built-in **Descriptives** and **Scatter Plot** analyses:

- **Descriptives**: adds the coefficient of variation (CV), reported as a percentage when `Std. deviation` is selected.
- **Scatter Plot**: adds a pink 95% prediction interval when `Show line` and `Confidence interval` are selected.

Requires jamovi >= 1.0.8.

## Installation (sideload)

Prebuilt `.jmo` files are attached to the [Releases](../../releases) page, one release per jamovi/R version:

- **R 4.5.3** — jamovi builds bundling R 4.5.3
- **R 4.6.0** — jamovi builds bundling R 4.6.0

Each release has assets for macOS (arm64/x64), Windows (x64), and Linux (arm64/x64). Pick the file matching your OS and jamovi's bundled R version, then in jamovi: **Modules -> jamovi library -> Sideload** and select the downloaded `.jmo`.

Not sure which R version your jamovi bundles? Check **Help -> About** in jamovi.

## Repository layout

- `jmvplus/` — R package source (analysis definitions, R code, jamovi UI yaml)
- `tools/` — build and install helper scripts
- `dist/` — packaged `.jmo` build output per R version/OS/arch (not tracked in git; attached to releases)
