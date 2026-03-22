# Tobit Model Guide In Simple Terms

This note explains the Tobit part of the project in plain language and shows where each part lives in the code.

## 1. What the Tobit model is doing here

In this project, the main outcome is `judgement`, a score from `-9` to `9`.

- `-9` means a very negative moral judgment.
- `9` means a very positive moral judgment.
- Values cannot go below `-9` or above `9`.

That boundary is why the project uses a Tobit-style model instead of a plain linear regression.

Simple idea:

1. A participant may have an underlying opinion that is even lower than `-9` or higher than `9`.
2. But the survey only records values inside the allowed scale.
3. So the observed score is a "censored" version of a hidden continuous score.

In this project:

- Scores at `-9` are treated as left-censored.
- Scores at `9` are treated as right-censored.
- Scores between `-9` and `9` are treated as directly observed.

## 2. The most important Tobit parts

### A. The outcome being modeled

The model uses the raw variable `judgement`.

Why that matters:

- The code does not replace the outcome with a transformed score for the main Tobit analysis.
- It models the original bounded moral-judgment scale directly.

Where in code:

- `prepare_analysis_data()` in `R/pipeline_functions.R:465`
- `build_judgement_summary()` in `R/pipeline_functions.R:658`

### B. The censoring rule

This is the core Tobit logic.

The code says:

- if `judgement <= -9`, treat the lower side as open (`-Inf`)
- if `judgement >= 9`, treat the upper side as open (`Inf`)
- otherwise use the actual observed score

This is how the model tells R:
"I know the response hit the floor or ceiling, so do not treat it as an ordinary exact value."

Where in code:

- `fit_clustered_tobit()` in `R/pipeline_functions.R:972`

### C. The model formula

The project fits three related Tobit models:

1. Main harmful-decision model
2. Same-faculty harm model
3. Full-sample model

The main model includes predictors such as:

- `iri_total_z`: standardized empathy
- `perp_outgroup`: whether the negotiator is from the participant's outgroup
- `perp_control`: hidden-label control condition
- `victim_outgroup`: whether the victim is from the participant's outgroup
- `iri_total_z:perp_outgroup`: empathy-by-outgroup interaction
- `role_observer`, `age`, `sex_man`, `economic_status`
- `factor(stage)` and `factor(negotiator_slot)` as controls

Where in code:

- `fit_models()` in `R/pipeline_functions.R:997`

### D. The sample used for the main model

The main Tobit hypothesis model is not fit on every row.

It is restricted to:

- participants who passed both attention checks
- participants with a non-missing empathy score
- negotiator judgments where `decision_accept == 1` (harmful decisions)

Why:

- the main hypotheses are about condemnation of harmful conduct
- not all decisions are equally relevant to that question

Where in code:

- `prepare_analysis_data()` in `R/pipeline_functions.R:465`
- `fit_models()` in `R/pipeline_functions.R:997`

### E. The actual estimation engine

The code implements Tobit behavior using:

- `survival::Surv(..., type = "interval2")`
- `survival::survreg(..., dist = "gaussian")`

Simple meaning:

- `Surv(..., type = "interval2")` tells R whether each value is exact, left-censored, or right-censored
- `dist = "gaussian"` means the hidden latent score is assumed to follow the usual Tobit normal-error setup

Where in code:

- `fit_clustered_tobit()` in `R/pipeline_functions.R:972`

### F. Clustered robust standard errors

Each participant gives many judgments, so observations from the same person are not independent.

The code handles that by clustering on participant `id`.

Simple meaning:

- the coefficient estimate stays the same model idea
- the uncertainty calculation is adjusted for repeated judgments from the same participant

Where in code:

- `fit_clustered_tobit()` in `R/pipeline_functions.R:972`

Relevant arguments:

- `robust = TRUE`
- `cluster = model_data$id`

### G. Turning coefficients into readable tables

After the model is fit, the project extracts:

- estimates
- robust standard errors
- z values
- p values
- confidence intervals
- human-readable coefficient labels

Where in code:

- `extract_model_table()` in `R/pipeline_functions.R:929`
- `extract_model_stats()` in `R/pipeline_functions.R:948`
- `label_term()` in `R/pipeline_functions.R:893`

### H. Linking the model to the hypotheses

The project does not stop at fitting the model.
It also maps specific coefficients to hypotheses:

- H1 uses `iri_total_z`
- H2a uses `same_group_harm`
- H2b uses `perp_outgroup`
- H3 uses `iri_total_z:perp_outgroup`

Where in code:

- `get_term_row()` in `R/pipeline_functions.R:1073`
- `validate_hypotheses()` in `R/pipeline_functions.R:1168`

## 3. The simple mathematical idea

The project is assuming:

- there is a hidden continuous score, often written as `y*`
- we only observe the bounded score `y`

Simple form:

- if `y*` is below `-9`, we observe `-9`
- if `y*` is between `-9` and `9`, we observe `y*`
- if `y*` is above `9`, we observe `9`

The report writes this out in a Word-friendly way.

Where in code:

- `word_equation_lines()` in `R/pipeline_functions.R:1411`
- `build_report()` in `R/pipeline_functions.R:1622`
- `build_latex_report()` in `R/pipeline_functions.R:1499`

## 4. Function map

| Function | Simple role | Location |
| --- | --- | --- |
| `prepare_analysis_data()` | Builds the long analysis dataset and creates key Tobit variables such as `judgement`, `perp_outgroup`, `same_group_harm`, and filtered samples | `R/pipeline_functions.R:465` |
| `build_judgement_summary()` | Summarizes the outcome and the amount of censoring at `-9` and `9` | `R/pipeline_functions.R:658` |
| `build_harmful_descriptives()` | Produces descriptive subgroup summaries used before modeling | `R/pipeline_functions.R:686` |
| `summarise_group()` | Computes mean, SD, SE, and 95% intervals for grouped descriptive results | `R/pipeline_functions.R:637` |
| `fit_clustered_tobit()` | Core Tobit implementation: creates censoring endpoints and fits the interval-censored Gaussian model | `R/pipeline_functions.R:972` |
| `fit_models()` | Defines the main, betrayal, and full-sample Tobit formulas and fits them | `R/pipeline_functions.R:997` |
| `label_term()` | Converts raw model term names into readable labels for tables | `R/pipeline_functions.R:893` |
| `extract_model_table()` | Pulls coefficient estimates, robust SEs, p values, and confidence intervals | `R/pipeline_functions.R:929` |
| `extract_model_stats()` | Pulls model-level fit information like log-likelihood, AIC, and censoring counts | `R/pipeline_functions.R:948` |
| `get_term_row()` | Pulls one coefficient row from a model table for a specific hypothesis | `R/pipeline_functions.R:1073` |
| `validate_hypotheses()` | Maps coefficients to H1, H2a, H2b, and H3 | `R/pipeline_functions.R:1168` |
| `compose_assumptions_narrative()` | Explains in words why Tobit is appropriate for this bounded outcome | `R/pipeline_functions.R:1312` |
| `word_equation_lines()` | Writes the simple bounded-outcome equations used in the reports | `R/pipeline_functions.R:1411` |
| `build_latex_report()` | Inserts the Tobit explanation and results into the LaTeX report | `R/pipeline_functions.R:1499` |
| `build_report()` | Inserts the Tobit explanation and results into the Markdown report | `R/pipeline_functions.R:1622` |
| `run_full_pipeline()` | Runs the full workflow from data import to fitted Tobit models and reports | `R/pipeline_functions.R:1725` |
| `run_pipeline.R` | Entry script that loads the functions and starts the full pipeline | `run_pipeline.R:1` |

## 5. If you want to read the Tobit logic in order

Read the code in this order:

1. `run_pipeline.R:1`
2. `run_full_pipeline()` in `R/pipeline_functions.R:1725`
3. `prepare_analysis_data()` in `R/pipeline_functions.R:465`
4. `fit_models()` in `R/pipeline_functions.R:997`
5. `fit_clustered_tobit()` in `R/pipeline_functions.R:972`
6. `extract_model_table()` in `R/pipeline_functions.R:929`
7. `validate_hypotheses()` in `R/pipeline_functions.R:1168`
8. `build_report()` in `R/pipeline_functions.R:1622`

## 6. One-sentence summary

The Tobit part of this project models a bounded moral-judgment score by assuming an underlying continuous judgment, treating `-9` and `9` as censored limits, and estimating how empathy, group membership, and controls relate to that hidden score.
