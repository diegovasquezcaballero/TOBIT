# Tobit Analysis Pipeline

This repository now includes a reproducible R pipeline for:

- reshaping the experiment from wide to negotiator-level long format,
- scoring the IRI empathy variables,
- running QC and EDA,
- fitting clustered Tobit regression models in R,
- generating automated prose interpretations of model results and hypothesis tests,
- exporting summary tables and 300 dpi figures, and
- rendering a Markdown report to Word.

## Inputs

The pipeline expects these project files in the repository root:

- `data_final_FLORIDA.xlsx`
- `datacard.md`
- `hypotheses.md` or `hypotheses`

If both hypothesis files exist, `hypotheses.md` is used first.

## Analysis Design

The pipeline follows the codebook and the hypothesis file and uses these operational choices:

- Unit of analysis: negotiator-level moral judgments.
- Outcome: the raw bounded judgment score from `-9` to `9`.
- Interpretation of the outcome: lower values mean harsher condemnation; higher values mean more favorable evaluations.
- Tobit bounds: `-9` and `9`.
- Main hypothesis sample: harmful decisions only (`decision_accept = 1`).
- Repeated judgments: handled with participant-clustered robust standard errors in `survival::survreg()`.
- H1: a negative empathy effect on the raw judgment scale.
- H2a: same-faculty harm (`same_group_harm = 1` when negotiator and victim share the same labeled faculty) should lower judgments.
- H2b: outgroup perpetrator effect relative to the evaluator (`perp_outgroup = 1`) should lower judgments.
- H3: the empathy slope should become more negative in outgroup cases.

## Dependencies

The pipeline is intentionally dependency-light.

- Required R package: `survival` (bundled with standard R installations).
- Preferred reader: `readxl`.
- Fallback reader: Python with `pandas` if `readxl` is not installed.
- Word export: `pandoc`.
- Other Tobit packages considered: `AER`, `VGAM`, and `censReg`.

On startup, the pipeline now attempts to install missing required R packages from CRAN automatically:

- `survival` is treated as mandatory.
- `readxl` is attempted automatically, but the pipeline can still proceed if Python with both `pandas` and `openpyxl` is available.

In the current local environment, `survival` and `pandoc` are available and the code can use Python as the Excel fallback. The main implementation stays with `survival::survreg()` because it supports clustered robust inference cleanly for this project. `AER`, `VGAM`, and `censReg` are reported as optional alternatives when available.

## Run

From the project root:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' run_pipeline.R
```

If this is the first run on a new machine, the script may spend extra time installing missing R packages before the analysis starts.

If `Rscript` is already on your PATH, this also works:

```powershell
Rscript run_pipeline.R
```

To point at a different project root:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' run_pipeline.R .
```

## Outputs

The pipeline writes all generated artifacts under `outputs/`:

- `outputs/data/`
  - scored participant data
  - long-format judgment data
  - harmful-decision analysis sample
- `outputs/tables/`
  - sample summary tables
  - empathy scale summary
  - descriptive summaries
  - hypothesis validation table
- `outputs/models/`
  - fitted Tobit models as `.rds`
  - coefficient tables
  - model fit summaries
- `outputs/figures/`
  - 300 dpi minimalist PNG figures
  - single blue high-contrast palette for low-vision readability
- `outputs/report/`
  - `tobit_pipeline_report.md`
  - `tobit_pipeline_report.docx`
  - `tobit_pipeline_report.tex`
  - `tobit_pipeline_report.pdf`
  - `session_info.txt`

## File Overview

- `run_pipeline.R`: entry point.
- `R/pipeline_functions.R`: data preparation, EDA, Tobit models, automated interpretation, report writing, and Word export.

## Notes

- Participants who fail either attention check are excluded from the primary analysis sample but remain in the raw reshaped outputs.
- The report is generated automatically in prose from the fitted models, including hypothesis verdicts for H1, H2a, H2b, and H3 on the raw `-9` to `9` judgment scale.
- The reporting pipeline now emits synchronized Markdown, Word, LaTeX, and PDF outputs from the same fitted results.
- Figures are exported as 300 dpi PNG files with a minimalist high-contrast style.
