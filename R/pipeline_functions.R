# Path and environment helpers -------------------------------------------------
# These helpers make every input/output path explicit so the pipeline stays
# reproducible across machines and working directories.

get_project_paths <- function(project_root = ".") {
  root <- normalizePath(project_root, winslash = "/", mustWork = TRUE) # Resolve the project folder once so all later file references are absolute and stable.
  hypotheses_candidates <- c("hypotheses.md", "hypotheses") # Accept either a markdown or plain-text hypotheses file.
  hypotheses_path <- "" # Keep this empty unless a hypotheses file is actually present.

  for (candidate in hypotheses_candidates) {
    candidate_path <- file.path(root, candidate) # Build the candidate path inside the project root.
    if (file.exists(candidate_path)) {
      hypotheses_path <- candidate_path # Store the first match so downstream reports can cite the theoretical source.
      break # Stop after the first match because only one hypotheses source is needed.
    }
  }

  # Collect every file path in one list so the rest of the pipeline can pass
  # around a single object instead of recomputing locations.
  list(
    root = root,
    input_file = file.path(root, "data_final_FLORIDA.xlsx"),
    datacard_file = file.path(root, "datacard.md"),
    hypotheses_file = hypotheses_path,
    output_dir = file.path(root, "outputs"),
    data_dir = file.path(root, "outputs", "data"),
    tables_dir = file.path(root, "outputs", "tables"),
    figures_dir = file.path(root, "outputs", "figures"),
    models_dir = file.path(root, "outputs", "models"),
    report_dir = file.path(root, "outputs", "report"),
    report_md = file.path(root, "outputs", "report", "tobit_pipeline_report.md"),
    report_docx = file.path(root, "outputs", "report", "tobit_pipeline_report.docx"),
    report_tex = file.path(root, "outputs", "report", "tobit_pipeline_report.tex"),
    report_pdf = file.path(root, "outputs", "report", "tobit_pipeline_report.pdf"),
    session_info = file.path(root, "outputs", "report", "session_info.txt")
  )
}

# Create the output folders before any tables, figures, or reports are written.
ensure_output_dirs <- function(paths) {
  dirs <- c(
    paths$output_dir,
    paths$data_dir,
    paths$tables_dir,
    paths$figures_dir,
    paths$models_dir,
    paths$report_dir
  )

  for (dir_path in dirs) {
    if (!dir.exists(dir_path)) {
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE) # Recursive creation avoids failures when parent folders do not yet exist.
    }
  }
}

# Python is only needed as a fallback reader when readxl is unavailable.
find_python_command <- function() {
  candidates <- c(Sys.which("python"), Sys.which("py")) # Check both common Windows entry points.
  candidates <- candidates[nzchar(candidates)] # Drop empty strings returned when an executable is missing.
  if (length(candidates) == 0L) {
    return("") # An empty string signals "no fallback available" to the caller.
  }
  candidates[[1]]
}

# Pandoc is optional and is only used to convert the Markdown report into Word.
find_pandoc_path <- function() {
  local_appdata <- Sys.getenv("LOCALAPPDATA") # On Windows, RStudio's bundled Pandoc often lives under LOCALAPPDATA.
  candidates <- c(
    Sys.which("pandoc"),
    file.path(local_appdata, "Pandoc", "pandoc.exe")
  )
  candidates <- unique(candidates[nzchar(candidates)]) # Remove duplicates and blank entries before checking the filesystem.
  matches <- candidates[file.exists(candidates)] # Keep only paths that truly exist on disk.
  if (length(matches) == 0L) {
    return("")
  }
  matches[[1]]
}

# pdflatex is also optional; it compiles the LaTeX report into a PDF article.
find_pdflatex_path <- function() {
  candidates <- c(
    Sys.which("pdflatex"),
    file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "MiKTeX", "miktex", "bin", "x64", "pdflatex.exe")
  )
  candidates <- unique(candidates[nzchar(candidates)])
  matches <- candidates[file.exists(candidates)]
  if (length(matches) == 0L) {
    return("")
  }
  matches[[1]]
}

# Record which Tobit-related packages are available so the report can document
# the computational environment transparently.
get_package_availability <- function() {
  data.frame(
    Package = c("survival", "AER", "VGAM", "censReg"),
    Available = c(
      requireNamespace("survival", quietly = TRUE),
      requireNamespace("AER", quietly = TRUE),
      requireNamespace("VGAM", quietly = TRUE),
      requireNamespace("censReg", quietly = TRUE)
    ),
    stringsAsFactors = FALSE
  )
}

# Dependency bootstrap ---------------------------------------------------------
# These helpers make the pipeline more self-contained by installing the minimum
# R packages it needs before any modeling or report generation starts.

get_cran_repo <- function() {
  repos <- getOption("repos")

  if (length(repos) == 0L) {
    repos <- c(CRAN = "https://cloud.r-project.org")
  }

  cran_repo <- unname(repos["CRAN"])
  if (length(cran_repo) == 0L || is.na(cran_repo) || !nzchar(cran_repo) || identical(cran_repo, "@CRAN@")) {
    repos["CRAN"] <- "https://cloud.r-project.org"
  }

  repos
}

install_r_package_if_missing <- function(package_name, required = TRUE) {
  if (requireNamespace(package_name, quietly = TRUE)) {
    return(TRUE)
  }

  message("Installing missing R package '", package_name, "' from CRAN...")
  old_repos <- getOption("repos")
  on.exit(options(repos = old_repos), add = TRUE)
  options(repos = get_cran_repo())

  install_attempt <- tryCatch(
    {
      utils::install.packages(
        package_name,
        dependencies = c("Depends", "Imports")
      )
      TRUE
    },
    error = function(e) {
      message("Installation failed for package '", package_name, "': ", conditionMessage(e))
      FALSE
    }
  )

  installed <- install_attempt && requireNamespace(package_name, quietly = TRUE)
  if (!installed && required) {
    stop(
      "Required R package '", package_name, "' is not available and could not be installed automatically.",
      call. = FALSE
    )
  }

  installed
}

python_excel_fallback_available <- function() {
  python_cmd <- find_python_command()
  if (!nzchar(python_cmd)) {
    return(FALSE)
  }

  check_output <- system2(
    command = python_cmd,
    args = c("-c", shQuote("import pandas, openpyxl")),
    stdout = TRUE,
    stderr = TRUE
  )

  status <- attr(check_output, "status")
  is.null(status) || identical(status, 0L)
}

ensure_pipeline_dependencies <- function() {
  install_r_package_if_missing("survival", required = TRUE)

  readxl_available <- install_r_package_if_missing("readxl", required = FALSE)
  if (!readxl_available && !python_excel_fallback_available()) {
    stop(
      "The pipeline needs either the R package 'readxl' or a Python fallback with both 'pandas' and 'openpyxl'.",
      call. = FALSE
    )
  }

  invisible(
    list(
      survival = TRUE,
      readxl = readxl_available,
      python_excel_fallback = python_excel_fallback_available(),
      pandoc = nzchar(find_pandoc_path()),
      pdflatex = nzchar(find_pdflatex_path())
    )
  )
}

# Basic statistical helper functions -------------------------------------------
# These wrappers standardize missing-data handling so tables do not break when
# a subgroup has no usable observations.

safe_mean <- function(x) {
  if (all(is.na(x))) {
    return(NA_real_) # Preserve missingness instead of returning NaN for all-missing inputs.
  }
  mean(x, na.rm = TRUE) # Descriptive means ignore sporadic missing values.
}

safe_sd <- function(x) {
  x <- x[!is.na(x)] # Standard deviation requires the observed values only.
  if (length(x) <= 1L) {
    return(NA_real_) # SD is undefined for 0 or 1 observation.
  }
  stats::sd(x)
}

safe_se <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) <= 1L) {
    return(NA_real_) # A standard error needs at least two observations to estimate spread.
  }
  stats::sd(x) / sqrt(length(x)) # SE quantifies sampling uncertainty around the mean.
}

# Formatting and export helpers ------------------------------------------------
# These functions turn model outputs and summaries into publication-ready text.

format_number <- function(x, digits = 2) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f")) # Fixed-point formatting keeps tables aligned across outputs.
}

format_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "NA", paste0(formatC(100 * x, digits = digits, format = "f"), "%")) # Convert proportions to percentages for easier interpretation.
}

format_p_value <- function(p) {
  if (is.na(p)) {
    return("NA")
  }
  if (p < 0.001) {
    return("<0.001")
  }
  formatC(p, digits = 3, format = "f")
}

format_ci <- function(low, high, digits = 2) {
  paste0("[", format_number(low, digits), ", ", format_number(high, digits), "]") # Confidence intervals are printed in the conventional lower-to-upper format.
}

write_text_file <- function(lines, file_path) {
  con <- file(file_path, open = "wb") # Open a binary connection so encoding is controlled explicitly.
  on.exit(close(con), add = TRUE) # Guarantee the file handle closes even if writing fails midway.
  writeLines(enc2utf8(lines), con = con, useBytes = TRUE) # Force UTF-8 output so special characters survive across report formats.
}

# Convert a data frame into simple GitHub-flavored Markdown.
to_markdown_table <- function(df, digits = 3) {
  if (!is.data.frame(df) || ncol(df) == 0L) {
    return("")
  }

  format_cell <- function(x) {
    if (is.numeric(x)) {
      if (all(is.na(x) | abs(x - round(x)) < .Machine$double.eps^0.5)) {
        return(formatC(x, digits = 0, format = "f")) # Print near-integers without decimals to avoid visual clutter.
      }
      return(formatC(x, digits = digits, format = "f"))
    }
    if (is.logical(x)) {
      return(ifelse(is.na(x), "NA", ifelse(x, "TRUE", "FALSE")))
    }
    x <- as.character(x)
    x[is.na(x)] <- "NA"
    x
  }

  formatted <- lapply(df, format_cell) # Format column-by-column so numeric precision stays consistent.
  formatted_df <- as.data.frame(formatted, stringsAsFactors = FALSE, check.names = FALSE)
  header <- paste0("| ", paste(names(formatted_df), collapse = " | "), " |")
  separator <- paste0("| ", paste(rep("---", ncol(formatted_df)), collapse = " | "), " |")
  rows <- apply(formatted_df, 1, function(row) {
    paste0("| ", paste(row, collapse = " | "), " |")
  })

  c(header, separator, rows)
}

# Escape LaTeX-sensitive characters so text content does not break compilation.
escape_latex <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- "NA"
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("([#$%&_{}])", "\\\\\\1", x, perl = TRUE)
  x <- gsub("~", "\\\\textasciitilde{}", x, fixed = TRUE)
  x <- gsub("\\^", "\\\\textasciicircum{}", x, perl = TRUE)
  x
}

# Build a LaTeX table, optionally using longtable for multi-page model output.
to_latex_table <- function(df, caption, label, digits = 3, longtable = FALSE) {
  if (!is.data.frame(df) || ncol(df) == 0L) {
    return("")
  }

  format_cell <- function(x) {
    if (is.numeric(x)) {
      if (all(is.na(x) | abs(x - round(x)) < .Machine$double.eps^0.5)) {
        return(formatC(x, digits = 0, format = "f"))
      }
      return(formatC(x, digits = digits, format = "f"))
    }
    if (is.logical(x)) {
      return(ifelse(is.na(x), "NA", ifelse(x, "TRUE", "FALSE")))
    }
    as.character(x)
  }

  formatted <- lapply(df, format_cell)
  formatted_df <- as.data.frame(formatted, stringsAsFactors = FALSE, check.names = FALSE)
  formatted_df[] <- lapply(formatted_df, escape_latex) # Escape after formatting so symbols such as % in labels are safe.
  col_spec <- paste(rep("l", ncol(formatted_df)), collapse = "") # Left alignment makes mixed numeric/text columns easier to read.
  header <- paste(escape_latex(names(formatted_df)), collapse = " & ")
  body <- apply(formatted_df, 1, function(row) paste(row, collapse = " & "))

  if (longtable) {
    return(c(
      paste0("\\begin{longtable}{", col_spec, "}"),
      paste0("\\caption{", escape_latex(caption), "}\\label{", label, "}\\\\"),
      "\\toprule",
      paste0(header, " \\\\"),
      "\\midrule",
      "\\endfirsthead",
      "\\toprule",
      paste0(header, " \\\\"),
      "\\midrule",
      "\\endhead",
      paste0(body, " \\\\"),
      "\\bottomrule",
      "\\end{longtable}"
    ))
  }

  c(
    "\\begin{table}[H]",
    "\\centering",
    paste0("\\caption{", escape_latex(caption), "}"),
    paste0("\\label{", label, "}"),
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\toprule",
    paste0(header, " \\\\"),
    "\\midrule",
    paste0(body, " \\\\"),
    "\\bottomrule",
    "\\end{tabular}",
    "\\end{table}"
  )
}

# Insert a previously written PNG into the LaTeX report.
latex_include_graphic <- function(file_path, caption, label, width = "0.92\\textwidth") {
  rel_path <- gsub("\\\\", "/", file_path) # LaTeX is more reliable with forward slashes, even on Windows.
  c(
    "\\begin{figure}[H]",
    "\\centering",
    paste0("\\includegraphics[width=", width, "]{", rel_path, "}"),
    paste0("\\caption{", escape_latex(caption), "}"),
    paste0("\\label{", label, "}"),
    "\\end{figure}"
  )
}

# Data ingestion and validation ------------------------------------------------
# The analysis starts from one Excel workbook. Validation is strict so the later
# statistical steps fail fast if the data structure is not what the models expect.

read_source_data <- function(input_file) {
  if (!file.exists(input_file)) {
    stop("Input file not found: ", input_file, call. = FALSE)
  }

  if (requireNamespace("readxl", quietly = TRUE)) {
    return(as.data.frame(readxl::read_xlsx(input_file))) # Prefer readxl because it preserves workbook content directly inside R.
  }

  python_cmd <- find_python_command() # Fall back to pandas only when readxl is unavailable.
  if (!nzchar(python_cmd)) {
    stop(
      "The package 'readxl' is not installed and no Python interpreter was found for the fallback reader.",
      call. = FALSE
    )
  }

  py_code <- paste(
    "import pandas as pd",
    sprintf("df = pd.read_excel(r'''%s''')", normalizePath(input_file, winslash = "/", mustWork = TRUE)), # Use a raw string so Windows paths survive unchanged.
    "print(df.to_csv(index=False))", # Emit CSV text back to R so the rest of the code needs only one import path.
    sep = "\n"
  )

  csv_lines <- system2(
    command = python_cmd,
    args = "-",
    input = py_code,
    stdout = TRUE,
    stderr = TRUE
  )

  status <- attr(csv_lines, "status") # system2 stores the exit code as an attribute on captured output.
  if (!is.null(status) && status != 0L) {
    stop(
      "The Python fallback reader failed.\n",
      paste(csv_lines, collapse = "\n"),
      call. = FALSE
    )
  }

  utils::read.csv(
    text = paste(csv_lines, collapse = "\n"), # Parse the returned CSV text into a base-R data frame.
    na.strings = c("", "NA", "NaN"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

# Verify that the workbook contains every variable needed for scoring,
# reshaping, descriptives, and hypothesis tests.
validate_source_data <- function(df) {
  participant_vars <- c(
    "id", "commitment", "age", "economic_status", "sex", "faculty_player",
    "ac1", "ac2", "treatment"
  )
  empathy_vars <- c(
    "FS1", "EC2", "PT3", "EC4", "FS5", "PD6", "FS7", "PT8", "EC9", "PD10",
    "PT11", "FS12", "PD13", "EC14", "PT15", "FS16", "EC17", "PD18", "EC19",
    "FS20", "PT21", "PD22", "PT23", "EC24", "FS25", "PT26", "PD27", "EC28"
  )
  scenario_vars <- unlist(lapply(1:10, function(stage) { # Each stage should contribute the same repeated-measures fields.
    c(
      sprintf("faculty_neg_1_s%d", stage),
      sprintf("faculty_neg_2_s%d", stage),
      sprintf("faculty_victim_s%d", stage),
      sprintf("decision_neg1_s%d", stage),
      sprintf("decision_neg2_s%d", stage),
      sprintf("judgement_compare_s%d", stage),
      sprintf("judgement_n1_s%d", stage),
      sprintf("judgement_n2_s%d", stage)
    )
  }))

  required_vars <- c(participant_vars, empathy_vars, scenario_vars)
  missing_vars <- setdiff(required_vars, names(df)) # Any missing column would make the derived variables or models invalid.

  if (length(missing_vars) > 0L) {
    stop(
      "The source workbook is missing required columns: ",
      paste(missing_vars, collapse = ", "),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

# Psychometric scoring and analytic data construction --------------------------

# Compute a respondent-level mean only when enough item responses are present.
row_mean_with_floor <- function(df, cols, min_non_missing = ceiling(length(cols) * 0.8)) {
  available <- rowSums(!is.na(df[, cols, drop = FALSE])) # Count non-missing items per participant.
  values <- rowMeans(df[, cols, drop = FALSE], na.rm = TRUE) # Use the mean so scales stay on the original response metric.
  values[available < min_non_missing] <- NA_real_ # Drop scores that are based on too little information.
  values
}

# Classical Cronbach's alpha summarizes internal consistency across items.
cronbach_alpha <- function(df, cols) {
  item_frame <- df[, cols, drop = FALSE]
  item_frame <- item_frame[stats::complete.cases(item_frame), , drop = FALSE] # Use complete item sets because alpha depends on a common covariance matrix.
  if (nrow(item_frame) < 2L || ncol(item_frame) < 2L) {
    return(NA_real_)
  }

  item_vars <- apply(item_frame, 2, stats::var) # Alpha compares the sum of item variances with total-score variance.
  total_scores <- rowSums(item_frame)
  total_var <- stats::var(total_scores)

  if (is.na(total_var) || total_var <= 0) {
    return(NA_real_)
  }

  k <- ncol(item_frame) # Number of items in the scale.
  (k / (k - 1)) * (1 - sum(item_vars) / total_var)
}

# Standardize a variable so one unit equals one sample standard deviation.
z_score <- function(x) {
  if (all(is.na(x))) {
    return(rep(NA_real_, length(x)))
  }
  as.numeric((x - mean(x, na.rm = TRUE)) / stats::sd(x, na.rm = TRUE))
}

# Score the Interpersonal Reactivity Index and create analysis-ready participant flags.
score_iri <- function(df) {
  iri_scales <- list(
    iri_fs = c("FS1", "FS5", "FS7", "FS12", "FS16", "FS20", "FS25"),
    iri_ec = c("EC2", "EC4", "EC9", "EC14", "EC17", "EC19", "EC24", "EC28"),
    iri_pt = c("PT3", "PT8", "PT11", "PT15", "PT21", "PT23", "PT26"),
    iri_pd = c("PD6", "PD10", "PD13", "PD18", "PD22", "PD27")
  )

  iri_items <- unlist(iri_scales, use.names = FALSE) # The total IRI composite pools all subscale items.

  scored <- df
  scored$iri_total <- row_mean_with_floor(scored, iri_items, min_non_missing = ceiling(length(iri_items) * 0.8)) # Require 80% completion for the main empathy composite.
  scored$iri_total_z <- z_score(scored$iri_total) # Standardization makes the Tobit coefficient interpretable per SD increase in empathy.

  for (scale_name in names(iri_scales)) {
    scale_items <- iri_scales[[scale_name]]
    scored[[scale_name]] <- row_mean_with_floor(
      scored,
      scale_items,
      min_non_missing = max(1L, floor(length(scale_items) * 0.75)) # Subscales allow slightly more missingness because they contain fewer items.
    )
  }

  scored$sex_label <- ifelse(scored$sex == 2, "Man", "Woman") # Human-readable labels make summaries and plots easier to read.
  scored$faculty_player_label <- ifelse(scored$faculty_player == 2, "Engineering", "Humanities")
  scored$treatment_label <- ifelse(scored$treatment == 2, "Observer first", "Victim first")
  scored$attention_pass <- scored$ac1 == 1 & scored$ac2 == 1 # Primary sample quality screen.
  scored$analysis_include <- scored$attention_pass & !is.na(scored$iri_total) # The main models keep only valid empathy scores plus passed checks.
  scored
}

# Treatment assignment changes whether earlier stages are experienced as victim
# or observer trials, so role must be reconstructed from treatment plus stage.
derive_role <- function(treatment, stage) {
  if (treatment == 1L) {
    if (stage <= 5L) {
      return("victim") # Treatment 1 starts with the participant in the victim perspective.
    }
    return("observer") # Later stages switch to the observer perspective.
  }

  if (stage <= 5L) {
    return("observer") # Treatment 2 uses the opposite ordering.
  }
  "victim"
}

# Reshape the wide workbook into negotiator-level rows, which is the unit used
# by the descriptive tables and Tobit models.
prepare_analysis_data <- function(df) {
  participants <- score_iri(df) # Start from the participant file enriched with empathy scores and inclusion flags.
  n_rows <- nrow(participants) * 20L # Each participant contributes 10 stages x 2 negotiators = 20 judgment rows.
  long_rows <- vector("list", n_rows) # Preallocate for speed and to avoid repeated list growth inside loops.
  index <- 1L

  for (row_id in seq_len(nrow(participants))) {
    row <- participants[row_id, , drop = FALSE] # Keep a one-row data frame so name-based indexing stays consistent.

    for (stage in 1:10) {
      role <- derive_role(as.integer(row$treatment), stage) # Recover the participant's role in this stage from the crossover design.

      for (slot in 1:2) {
        neg_faculty <- as.integer(row[[sprintf("faculty_neg_%d_s%d", slot, stage)]]) # Faculty identity of the focal negotiator.
        victim_faculty <- as.integer(row[[sprintf("faculty_victim_s%d", stage)]]) # Faculty identity of the harmed party.
        participant_faculty <- as.integer(row$faculty_player) # Faculty identity of the evaluator.
        judgement <- as.numeric(row[[sprintf("judgement_n%d_s%d", slot, stage)]]) # Observed bounded outcome used in the Tobit model.
        negotiator_alignment <- if (neg_faculty == 3L) {
          "control" # Code 3 means the negotiator faculty label was hidden.
        } else if (neg_faculty == participant_faculty) {
          "ingroup" # Labeled negotiator belongs to the evaluator's own faculty group.
        } else {
          "outgroup" # Labeled negotiator belongs to the evaluator's opposing faculty group.
        }

        long_rows[[index]] <- data.frame(
          id = as.integer(row$id), # Participant identifier used for clustering standard errors later.
          stage = stage, # Scenario stage indicator; included as a fixed effect in the models.
          negotiator_slot = slot, # Two negotiators are judged in each stage.
          role = role, # Victim vs observer perspective.
          role_observer = as.integer(role == "observer"), # Dummy-coded role for regression convenience.
          age = as.numeric(row$age),
          economic_status = as.numeric(row$economic_status),
          sex = as.integer(row$sex),
          sex_man = as.integer(row$sex == 2), # Binary coding matches the reference-category interpretation in the report.
          participant_faculty = participant_faculty,
          participant_engineering = as.integer(participant_faculty == 2), # Engineering is coded 1 so humanities acts as the reference group.
          treatment = as.integer(row$treatment),
          attention_pass = as.logical(row$attention_pass),
          analysis_include = as.logical(row$analysis_include),
          iri_total = as.numeric(row$iri_total),
          iri_total_z = as.numeric(row$iri_total_z),
          iri_fs = as.numeric(row$iri_fs),
          iri_ec = as.numeric(row$iri_ec),
          iri_pt = as.numeric(row$iri_pt),
          iri_pd = as.numeric(row$iri_pd),
          faculty_negotiator = neg_faculty,
          faculty_victim = victim_faculty,
          negotiator_alignment = negotiator_alignment,
          perp_outgroup = as.integer(negotiator_alignment == "outgroup"), # Key H2b/H3 indicator.
          perp_control = as.integer(negotiator_alignment == "control"), # Separate indicator for hidden-label control trials.
          victim_outgroup = as.integer(victim_faculty != participant_faculty), # Whether the harmed person belongs to the evaluator's outgroup.
          same_group_harm = if (neg_faculty == 3L) NA_integer_ else as.integer(neg_faculty == victim_faculty), # H2a is only defined when the negotiator is not in the control condition.
          decision_accept = as.integer(row[[sprintf("decision_neg%d_s%d", slot, stage)]]), # 1 means the negotiator chose the harmful but payoff-increasing option.
          comparative_judgement = as.integer(row[[sprintf("judgement_compare_s%d", stage)]]), # Stage-level comparison variable retained for completeness.
          judgement = judgement, # Raw observed rating on the original -9 to 9 scale.
          severity = 9 - judgement, # Derived severity measure kept for possible alternate summaries.
          condemnation = -judgement, # Sign-flipped version where larger values mean harsher condemnation.
          stringsAsFactors = FALSE
        )
        index <- index + 1L # Advance to the next storage slot in the preallocated list.
      }
    }
  }

  judgments_all <- do.call(rbind, long_rows) # Collapse the list of row fragments into one long data frame.
  judgments_all$role <- factor(judgments_all$role, levels = c("victim", "observer")) # Fix reference levels before modeling.
  judgments_all$negotiator_alignment <- factor(
    judgments_all$negotiator_alignment,
    levels = c("ingroup", "outgroup", "control")
  )

  judgments_analysis <- judgments_all[judgments_all$analysis_include, , drop = FALSE] # Main analysis sample after participant-level screening.
  judgments_accept <- judgments_analysis[judgments_analysis$decision_accept == 1L, , drop = FALSE] # Harmful decisions only, matching the primary hypotheses.
  judgments_betrayal <- judgments_accept[judgments_accept$perp_control == 0L, , drop = FALSE] # Remove unlabeled control perpetrators for the same-group-harm test.

  list(
    participants = participants,
    judgments_all = judgments_all,
    judgments_analysis = judgments_analysis,
    judgments_accept = judgments_accept,
    judgments_betrayal = judgments_betrayal
  )
}

# Export intermediate analysis datasets so the cleaning and reshape steps remain inspectable.
write_data_outputs <- function(prep, paths) {
  utils::write.csv(prep$participants, file.path(paths$data_dir, "participants_scored.csv"), row.names = FALSE, na = "")
  utils::write.csv(prep$judgments_all, file.path(paths$data_dir, "judgments_long_all.csv"), row.names = FALSE, na = "")
  utils::write.csv(prep$judgments_analysis, file.path(paths$data_dir, "judgments_long_analysis.csv"), row.names = FALSE, na = "")
  utils::write.csv(prep$judgments_accept, file.path(paths$data_dir, "judgments_long_accept_only.csv"), row.names = FALSE, na = "")
}

# Participant-level descriptives summarize the analysis sample after screening.
build_participant_summary <- function(prep) {
  participants <- prep$participants
  analysis_participants <- participants[participants$analysis_include, , drop = FALSE]

  data.frame(
    Metric = c(
      "Participants in workbook",
      "Participants passing both attention checks",
      "Participants in primary analysis",
      "Mean age (analysis sample)",
      "SD age (analysis sample)",
      "Women in analysis sample",
      "Men in analysis sample",
      "Humanities in analysis sample",
      "Engineering in analysis sample",
      "Victim-first treatment in analysis sample",
      "Observer-first treatment in analysis sample"
    ),
    Value = c(
      nrow(participants),
      sum(participants$attention_pass, na.rm = TRUE),
      nrow(analysis_participants),
      safe_mean(analysis_participants$age),
      safe_sd(analysis_participants$age),
      sum(analysis_participants$sex == 1, na.rm = TRUE),
      sum(analysis_participants$sex == 2, na.rm = TRUE),
      sum(analysis_participants$faculty_player == 1, na.rm = TRUE),
      sum(analysis_participants$faculty_player == 2, na.rm = TRUE),
      sum(analysis_participants$treatment == 1, na.rm = TRUE),
      sum(analysis_participants$treatment == 2, na.rm = TRUE)
    ),
    stringsAsFactors = FALSE
  )
}

# Empathy descriptives report scale location, spread, range, and reliability.
build_empathy_summary <- function(prep) {
  participants <- prep$participants[prep$participants$analysis_include, , drop = FALSE] # Restrict reliability/descriptives to the analyzed participant sample.
  scale_map <- list(
    `IRI total` = c("iri_total", 28L),
    `Fantasy` = c("iri_fs", 7L),
    `Empathic concern` = c("iri_ec", 8L),
    `Perspective taking` = c("iri_pt", 7L),
    `Personal distress` = c("iri_pd", 6L)
  )

  item_lookup <- list(
    iri_total = c(
      "FS1", "EC2", "PT3", "EC4", "FS5", "PD6", "FS7", "PT8", "EC9", "PD10",
      "PT11", "FS12", "PD13", "EC14", "PT15", "FS16", "EC17", "PD18", "EC19",
      "FS20", "PT21", "PD22", "PT23", "EC24", "FS25", "PT26", "PD27", "EC28"
    ),
    iri_fs = c("FS1", "FS5", "FS7", "FS12", "FS16", "FS20", "FS25"),
    iri_ec = c("EC2", "EC4", "EC9", "EC14", "EC17", "EC19", "EC24", "EC28"),
    iri_pt = c("PT3", "PT8", "PT11", "PT15", "PT21", "PT23", "PT26"),
    iri_pd = c("PD6", "PD10", "PD13", "PD18", "PD22", "PD27")
  )

  rows <- lapply(names(scale_map), function(scale_label) {
    scale_info <- scale_map[[scale_label]]
    scale_name <- scale_info[[1]]
    items <- item_lookup[[scale_name]] # Pull the actual item names so Cronbach's alpha uses the correct item set.
    data.frame(
      Scale = scale_label,
      Items = as.integer(scale_info[[2]]),
      Mean = safe_mean(participants[[scale_name]]),
      SD = safe_sd(participants[[scale_name]]),
      Min = min(participants[[scale_name]], na.rm = TRUE),
      Max = max(participants[[scale_name]], na.rm = TRUE),
      Alpha = cronbach_alpha(participants, items),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

# Group summaries feed the descriptive tables and uncertainty bars in the figures.
summarise_group <- function(df, group_vars, outcome = "judgement") {
  split_index <- interaction(df[, group_vars, drop = FALSE], drop = TRUE, sep = "___") # Create a unique label for every combination of grouping variables.
  chunks <- split(df, split_index) # Split the long data into independent subgroup data frames.

  rows <- lapply(chunks, function(chunk) {
    keys <- chunk[1, group_vars, drop = FALSE] # The first row carries the subgroup labels.
    keys$Observations <- nrow(chunk)
    keys$MeanJudgement <- safe_mean(chunk[[outcome]])
    keys$SDJudgement <- safe_sd(chunk[[outcome]])
    keys$SEJudgement <- safe_se(chunk[[outcome]])
    keys$Lower95 <- keys$MeanJudgement - 1.96 * keys$SEJudgement # Wald-style 95% interval for visual summaries.
    keys$Upper95 <- keys$MeanJudgement + 1.96 * keys$SEJudgement
    keys
  })

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}

# Summarize the amount of usable judgment data and the extent of censoring.
build_judgement_summary <- function(prep) {
  analysis <- prep$judgments_analysis
  accept <- prep$judgments_accept

  data.frame(
    Metric = c(
      "Negotiator-level judgments in analysis sample",
      "Harmful decisions in primary model sample",
      "Acceptance rate in analysis sample",
      "Mean raw judgment for rejected decisions",
      "Mean raw judgment for accepted decisions",
      "Left-censored share at -9 in accepted sample",
      "Right-censored share at 9 in accepted sample"
    ),
    Value = c(
      nrow(analysis),
      nrow(accept),
      mean(analysis$decision_accept, na.rm = TRUE),
      safe_mean(analysis$judgement[analysis$decision_accept == 0]),
      safe_mean(analysis$judgement[analysis$decision_accept == 1]),
      mean(accept$judgement == -9, na.rm = TRUE),
      mean(accept$judgement == 9, na.rm = TRUE)
    ),
    stringsAsFactors = FALSE
  )
}

# Describe the harmful-decision sample by perpetrator alignment and role.
build_harmful_descriptives <- function(prep) {
  harmful <- prep$judgments_accept
  summary_df <- summarise_group(
    harmful,
    group_vars = c("negotiator_alignment", "role")
  )

  summary_df$negotiator_alignment <- as.character(summary_df$negotiator_alignment)
  summary_df$role <- as.character(summary_df$role)
  summary_df
}

# Plotting helpers -------------------------------------------------------------
# The project exports static, high-contrast figures meant to remain readable in
# Word/PDF output and for readers with low vision.

get_plot_style <- function() {
  list(
    ink = "#1A1A1A",
    primary = "#0B5E8E",
    primary_dark = "#083B5C",
    primary_light = "#CFE3F1",
    grid = "#D8D8D8",
    background = "#FFFFFF"
  )
}

# Open a PNG device at print-quality resolution.
open_accessible_png <- function(file_path, width = 8, height = 5) {
  grDevices::png(
    filename = file_path,
    width = width,
    height = height,
    units = "in",
    res = 300,
    bg = "white"
  )
}

# Base plotting parameters are centralized so every figure shares the same look.
apply_accessible_theme <- function() {
  style <- get_plot_style()
  graphics::par(
    bg = style$background,
    fg = style$ink,
    col.axis = style$ink,
    col.lab = style$ink,
    col.main = style$ink,
    cex.axis = 1.05,
    cex.lab = 1.15,
    cex.main = 1.10,
    family = "sans",
    las = 1,
    lend = "round",
    lwd = 2,
    mar = c(5, 5, 2.5, 1.5),
    bty = "l"
  )
}

# Age is summarized only for participants who survive the main analysis filter.
plot_age_histogram <- function(prep, paths) {
  participants <- prep$participants[prep$participants$analysis_include, , drop = FALSE]
  style <- get_plot_style()
  file_path <- file.path(paths$figures_dir, "figure_01_age_distribution.png")

  open_accessible_png(file_path)
  on.exit(grDevices::dev.off(), add = TRUE)
  apply_accessible_theme()

  age_breaks <- pretty(participants$age, n = 8) # pretty() chooses human-readable bin edges.
  hist_info <- graphics::hist(
    participants$age,
    breaks = age_breaks,
    col = style$primary_light,
    border = style$primary_dark,
    main = "",
    xlab = "Age (years)",
    ylab = "Participants"
  )
  graphics::abline(h = pretty(c(0, hist_info$counts)), col = style$grid, lwd = 1)
  title(main = "Age distribution in the analysis sample")
  invisible(file_path)
}

# The empathy histogram shows the distribution of the main psychological predictor.
plot_empathy_histogram <- function(prep, paths) {
  participants <- prep$participants[prep$participants$analysis_include, , drop = FALSE]
  style <- get_plot_style()
  file_path <- file.path(paths$figures_dir, "figure_02_iri_total_distribution.png")

  open_accessible_png(file_path)
  on.exit(grDevices::dev.off(), add = TRUE)
  apply_accessible_theme()

  hist_info <- graphics::hist(
    participants$iri_total,
    breaks = pretty(participants$iri_total, n = 8),
    col = style$primary_light,
    border = style$primary_dark,
    main = "",
    xlab = "IRI composite mean score",
    ylab = "Participants"
  )
  graphics::abline(h = pretty(c(0, hist_info$counts)), col = style$grid, lwd = 1)
  title(main = "Empathy composite distribution")
  invisible(file_path)
}

# Compare raw judgments for harmful deals that were accepted versus rejected.
plot_severity_by_decision <- function(prep, paths) {
  analysis <- prep$judgments_analysis
  style <- get_plot_style()
  file_path <- file.path(paths$figures_dir, "figure_03_judgement_by_decision.png")

  open_accessible_png(file_path)
  on.exit(grDevices::dev.off(), add = TRUE)
  apply_accessible_theme()

  analysis$decision_label <- ifelse(analysis$decision_accept == 1, "Accepted harmful deal", "Rejected harmful deal") # Human-readable labels for the boxplot grouping.
  graphics::boxplot(
    judgement ~ decision_label,
    data = analysis,
    horizontal = TRUE,
    outline = FALSE,
    col = style$primary_light,
    border = style$primary_dark,
    xlab = "Raw moral-judgment score (-9 to 9)",
    ylab = ""
  )
  graphics::abline(v = pretty(c(-9, 9)), col = style$grid, lwd = 1)
  title(main = "Accepted harmful deals receive more negative ratings")
  invisible(file_path)
}

# Plot group means with 95% intervals to visualize H2/H3 patterns descriptively.
plot_harmful_group_means <- function(prep, paths) {
  harmful_summary <- build_harmful_descriptives(prep)
  style <- get_plot_style()
  file_path <- file.path(paths$figures_dir, "figure_04_harmful_decisions_by_group.png")

  harmful_summary$group_label <- paste(
    ifelse(harmful_summary$negotiator_alignment == "ingroup", "Ingroup", ifelse(harmful_summary$negotiator_alignment == "outgroup", "Outgroup", "Control")),
    ifelse(harmful_summary$role == "victim", "victim", "observer")
  )

  x_pos <- seq_len(nrow(harmful_summary)) # One plotting position per subgroup mean.

  open_accessible_png(file_path, width = 9, height = 5.5)
  on.exit(grDevices::dev.off(), add = TRUE)
  apply_accessible_theme()

  graphics::plot(
    x = x_pos,
    y = harmful_summary$MeanJudgement,
    ylim = range(c(harmful_summary$Lower95, harmful_summary$Upper95), na.rm = TRUE), # Ensure the confidence bars fully fit in the plotting window.
    xaxt = "n",
    xlab = "",
    ylab = "Mean moral-judgment score among harmful decisions",
    pch = 19,
    cex = 1.4,
    col = style$primary,
    main = "Judgment by perpetrator alignment and evaluator role"
  )
  graphics::axis(1, at = x_pos, labels = harmful_summary$group_label, cex.axis = 0.9)
  graphics::abline(h = pretty(range(c(harmful_summary$Lower95, harmful_summary$Upper95), na.rm = TRUE)), col = style$grid, lwd = 1)
  graphics::segments(
    x0 = x_pos,
    y0 = harmful_summary$Lower95,
    x1 = x_pos,
    y1 = harmful_summary$Upper95,
    col = style$primary_dark,
    lwd = 2
  )
  graphics::segments(
    x0 = x_pos - 0.12,
    y0 = harmful_summary$Lower95,
    x1 = x_pos + 0.12,
    y1 = harmful_summary$Lower95,
    col = style$primary_dark,
    lwd = 2
  )
  graphics::segments(
    x0 = x_pos - 0.12,
    y0 = harmful_summary$Upper95,
    x1 = x_pos + 0.12,
    y1 = harmful_summary$Upper95,
    col = style$primary_dark,
    lwd = 2
  )
  invisible(file_path)
}

# Create all figures in one pass so the report can refer to a single bundle.
make_figures <- function(prep, paths) {
  list(
    age = plot_age_histogram(prep, paths),
    empathy = plot_empathy_histogram(prep, paths),
    decision = plot_severity_by_decision(prep, paths),
    group = plot_harmful_group_means(prep, paths)
  )
}

# Modeling helpers -------------------------------------------------------------
# These functions translate raw coefficient names into readable labels and fit
# Tobit models that account for censoring at the observed judgment bounds.

label_term <- function(term) {
  direct_map <- c(
    "(Intercept)" = "Intercept",
    "iri_total_z" = "Empathy composite (z)",
    "perp_outgroup" = "Outgroup perpetrator (ref = ingroup)",
    "perp_control" = "Control label hidden (ref = ingroup)",
    "victim_outgroup" = "Victim outgroup (ref = ingroup)",
    "iri_total_z:perp_outgroup" = "Empathy x outgroup perpetrator",
    "iri_total_z:perp_control" = "Empathy x control label hidden",
    "role_observer" = "Observer role (ref = victim)",
    "participant_engineering" = "Engineering participant (ref = humanities)",
    "sex_man" = "Man (ref = woman)",
    "age" = "Age",
    "economic_status" = "Socioeconomic status",
    "same_group_harm" = "Negotiator and victim share faculty",
    "decision_accept" = "Negotiator accepted harmful deal"
  )

  if (term %in% names(direct_map)) {
    return(unname(direct_map[[term]]))
  }

  if (grepl("^factor\\(stage\\)", term)) {
    stage_number <- sub("^factor\\(stage\\)", "", term)
    return(paste0("Stage ", stage_number, " (ref = stage 1)"))
  }

  if (grepl("^factor\\(negotiator_slot\\)", term)) {
    slot_number <- sub("^factor\\(negotiator_slot\\)", "", term)
    return(paste0("Negotiator ", slot_number, " (ref = negotiator 1)"))
  }

  term
}

# Pull coefficients, robust SEs, p-values, and confidence intervals from survreg output.
extract_model_table <- function(model_fit) {
  summary_obj <- summary(model_fit)
  table_matrix <- summary_obj$table # survreg exposes coefficient summaries as a matrix in summary(model)$table.
  model_df <- data.frame(
    term = rownames(table_matrix),
    estimate = table_matrix[, 1],
    std_error = table_matrix[, 2],
    naive_se = table_matrix[, 3],
    z_value = table_matrix[, 4],
    p_value = table_matrix[, 5],
    stringsAsFactors = FALSE
  )
  model_df$conf_low <- model_df$estimate - 1.96 * model_df$std_error
  model_df$conf_high <- model_df$estimate + 1.96 * model_df$std_error
  model_df$label <- vapply(model_df$term, label_term, character(1)) # Convert design-matrix names into report-friendly labels.
  model_df
}

# Fit statistics document sample size, censoring counts, and rough pseudo-R2.
extract_model_stats <- function(model_fit, model_data, model_label) {
  loglik_values <- model_fit$loglik
  pseudo_r2 <- NA_real_

  if (!is.null(loglik_values) && length(loglik_values) == 2L && !isTRUE(all.equal(loglik_values[1], 0))) {
    pseudo_r2 <- 1 - (loglik_values[2] / loglik_values[1]) # McFadden-style pseudo-R2 using null and fitted log-likelihoods.
  }

  data.frame(
    Model = model_label,
    Observations = nrow(model_data),
    Participants = length(unique(model_data$id)),
    LowerBoundCensored = sum(model_data$judgement <= -9, na.rm = TRUE),
    UpperBoundCensored = sum(model_data$judgement >= 9, na.rm = TRUE),
    LogLik = as.numeric(stats::logLik(model_fit)),
    AIC = stats::AIC(model_fit),
    PseudoR2 = pseudo_r2,
    stringsAsFactors = FALSE
  )
}

# Implement a Tobit model via interval-censored Gaussian regression:
# values at -9 are treated as left-censored, values at 9 as right-censored, and
# interior values are observed exactly.
fit_clustered_tobit <- function(data, rhs_formula) {
  model_data <- data
  model_data$lower_endpoint <- ifelse(model_data$judgement <= -9, -Inf, model_data$judgement) # Left-censored observations only tell us the latent score is at or below -9.
  model_data$upper_endpoint <- ifelse(model_data$judgement >= 9, Inf, model_data$judgement) # Right-censored observations only tell us the latent score is at or above 9.

  formula_obj <- stats::as.formula(
    paste(
      "survival::Surv(lower_endpoint, upper_endpoint, type = 'interval2') ~",
      rhs_formula
    )
  )

  survival::survreg(
    formula = formula_obj,
    data = model_data,
    dist = "gaussian", # Gaussian latent errors reproduce the classical Tobit assumption.
    robust = TRUE, # Sandwich SEs make inference less sensitive to mild misspecification.
    cluster = model_data$id, # Cluster by participant because each person contributes repeated judgments.
    model = TRUE,
    x = TRUE,
    y = TRUE
  )
}

# Fit the three core model specifications used in the report and export each result.
fit_models <- function(prep, paths) {
  if (!requireNamespace("survival", quietly = TRUE)) {
    stop("The 'survival' package is required to fit Tobit models.", call. = FALSE)
  }

  main_rhs <- paste(
    "iri_total_z + perp_outgroup + perp_control + victim_outgroup +",
    "iri_total_z:perp_outgroup + iri_total_z:perp_control +",
    "role_observer + participant_engineering + sex_man + age + economic_status +",
    "factor(stage) + factor(negotiator_slot)"
  ) # Main harmful-decision model for H1, H2b, and H3.

  betrayal_rhs <- paste(
    "iri_total_z + same_group_harm + perp_outgroup + victim_outgroup +",
    "role_observer + participant_engineering + sex_man + age + economic_status +",
    "factor(stage) + factor(negotiator_slot)"
  ) # Same-group-harm model for H2a; the control condition is excluded because same-group harm is undefined there.

  full_rhs <- paste(
    "decision_accept + iri_total_z + perp_outgroup + perp_control + victim_outgroup +",
    "iri_total_z:perp_outgroup + iri_total_z:perp_control +",
    "role_observer + participant_engineering + sex_man + age + economic_status +",
    "factor(stage) + factor(negotiator_slot)"
  ) # Expanded full-sample model used as a robustness/descriptive check.

  model_specs <- list(
    main_harmful_tobit = list(
      label = "Main harmful-decision Tobit",
      data = prep$judgments_accept,
      rhs = main_rhs
    ),
    betrayal_tobit = list(
      label = "Same-faculty harm Tobit",
      data = prep$judgments_betrayal,
      rhs = betrayal_rhs
    ),
    full_sample_tobit = list(
      label = "Full-sample Tobit",
      data = prep$judgments_analysis,
      rhs = full_rhs
    )
  )

  results <- lapply(names(model_specs), function(model_name) {
    spec <- model_specs[[model_name]]
    fit <- fit_clustered_tobit(spec$data, spec$rhs)
    table_df <- extract_model_table(fit)
    stats_df <- extract_model_stats(fit, spec$data, spec$label)

    utils::write.csv(
      table_df,
      file.path(paths$models_dir, paste0(model_name, "_coefficients.csv")),
      row.names = FALSE
    )
    utils::write.csv(
      stats_df,
      file.path(paths$models_dir, paste0(model_name, "_fit_stats.csv")),
      row.names = FALSE
    )
    saveRDS(fit, file = file.path(paths$models_dir, paste0(model_name, ".rds"))) # Save the fitted object so diagnostics or re-reporting can happen without refitting.

    list(
      name = model_name,
      label = spec$label,
      formula_rhs = spec$rhs,
      data = spec$data,
      fit = fit,
      coefficients = table_df,
      fit_stats = stats_df
    )
  })

  names(results) <- names(model_specs)
  results
}

get_term_row <- function(model_table, term_name) {
  model_table[model_table$term == term_name, , drop = FALSE]
}

# Translate coefficient sign plus p-value into a hypothesis-testing verdict.
term_verdict <- function(estimate, p_value, expected = "positive") {
  if (is.na(estimate) || is.na(p_value)) {
    return("Not estimable")
  }

  if (p_value >= 0.05) {
    return("Inconclusive")
  }

  direction_matches <- if (expected == "positive") estimate > 0 else estimate < 0
  if (direction_matches) {
    return("Supported")
  }
  "Contradicted"
}

# Turn one model term into a reader-facing hypothesis decision row.
interpret_hypothesis_row <- function(hypothesis_id, hypothesis_text, row_df, expected = "positive") {
  if (nrow(row_df) == 0L) {
    return(data.frame(
      Hypothesis = hypothesis_id,
      Description = hypothesis_text,
      ModelTerm = "Missing",
      Estimate = NA_real_,
      CI95 = "NA",
      PValue = "NA",
      Verdict = "Not estimable",
      NullDecision = "Not estimable",
      ResearchDecision = "Not estimable",
      Interpretation = "The required model term was not available in the fitted model.",
      stringsAsFactors = FALSE
    ))
  }

  verdict <- term_verdict(row_df$estimate, row_df$p_value, expected = expected) # Separate statistical detectability from substantive direction.
  null_decision <- if (is.na(row_df$p_value)) {
    "Not estimable"
  } else if (row_df$p_value < 0.05) {
    "Reject H0"
  } else {
    "Fail to reject H0"
  }

  research_decision <- switch(
    verdict,
    Supported = "Support HA",
    Contradicted = "Reject HA",
    Inconclusive = "Insufficient evidence for HA",
    "Not estimable"
  )

  direction_text <- if (row_df$estimate > 0) {
    "more favorable moral judgments"
  } else {
    "harsher moral condemnation"
  }

  interpretation <- switch(
    verdict,
    Supported = paste0(
      hypothesis_id, " is supported: the estimated effect points toward ",
      direction_text, " and is statistically detectable."
    ),
    Contradicted = paste0(
      hypothesis_id, " is contradicted: the coefficient is statistically detectable but points in the opposite direction."
    ),
    Inconclusive = paste0(
      hypothesis_id, " is inconclusive: fail to reject the null. The coefficient direction is ",
      if (row_df$estimate > 0) "positive" else "negative",
      " but the estimate is not statistically distinguishable from zero."
    ),
    "The hypothesis could not be evaluated."
  )

  data.frame(
    Hypothesis = hypothesis_id,
    Description = hypothesis_text,
    ModelTerm = row_df$label,
    Estimate = row_df$estimate,
    CI95 = format_ci(row_df$conf_low, row_df$conf_high),
    PValue = format_p_value(row_df$p_value),
    Verdict = verdict,
    NullDecision = null_decision,
    ResearchDecision = research_decision,
    Interpretation = interpretation,
    stringsAsFactors = FALSE
  )
}

# Evaluate the four preregistered/substantive hypotheses against the fitted models.
validate_hypotheses <- function(model_results) {
  main_table <- model_results$main_harmful_tobit$coefficients
  betrayal_table <- model_results$betrayal_tobit$coefficients

  rbind(
    interpret_hypothesis_row(
      "H1",
      "Higher empathy predicts lower moral-judgment scores for harmful decisions.",
      get_term_row(main_table, "iri_total_z"),
      expected = "negative"
    ),
    interpret_hypothesis_row(
      "H2a",
      "Same-faculty harm receives lower moral-judgment scores than cross-faculty harm.",
      get_term_row(betrayal_table, "same_group_harm"),
      expected = "negative"
    ),
    interpret_hypothesis_row(
      "H2b",
      "Outgroup perpetrators receive lower moral-judgment scores than ingroup perpetrators.",
      get_term_row(main_table, "perp_outgroup"),
      expected = "negative"
    ),
    interpret_hypothesis_row(
      "H3",
      "Empathy becomes more negative in outgroup than ingroup cases.",
      get_term_row(main_table, "iri_total_z:perp_outgroup"),
      expected = "negative"
    )
  )
}

# Narrative helpers ------------------------------------------------------------
# These functions convert numeric results into plain-language report text.

describe_key_term <- function(model_table, term_name, positive_label, negative_label) {
  row_df <- get_term_row(model_table, term_name)
  if (nrow(row_df) == 0L) {
    return("The corresponding model term was not estimable.")
  }

  effect_label <- if (row_df$estimate >= 0) positive_label else negative_label
  significance <- if (row_df$p_value < 0.05) "statistically detectable" else "not statistically distinguishable from zero"

  paste0(
    effect_label,
    " (b = ", format_number(row_df$estimate, 2),
    ", 95% CI ", format_ci(row_df$conf_low, row_df$conf_high, 2),
    ", p = ", format_p_value(row_df$p_value),
    "; ", significance, ")."
  )
}

# Summarize the participant count and the number of negotiator-level observations.
compose_sample_narrative <- function(prep) {
  participants <- prep$participants
  analysis_participants <- participants[participants$analysis_include, , drop = FALSE]
  analysis <- prep$judgments_analysis
  accept <- prep$judgments_accept

  paste(
    "The workbook contains", nrow(participants), "participants, of whom",
    sum(participants$attention_pass, na.rm = TRUE), "passed both attention checks.",
    "The primary analysis retains", nrow(analysis_participants), "participants and",
    nrow(analysis), "negotiator-level judgments.",
    "The Tobit hypothesis models focus on", nrow(accept),
    "harmful decisions in which a negotiator accepted the payoff-increasing but victim-harming deal."
  )
}

# Highlight descriptive differences before any regression adjustment.
compose_descriptive_narrative <- function(prep) {
  analysis <- prep$judgments_analysis
  harmful <- prep$judgments_accept

  reject_mean <- safe_mean(analysis$judgement[analysis$decision_accept == 0])
  accept_mean <- safe_mean(analysis$judgement[analysis$decision_accept == 1])
  harmful_same <- safe_mean(harmful$judgement[harmful$same_group_harm == 1])
  harmful_diff <- safe_mean(harmful$judgement[harmful$same_group_harm == 0])
  outgroup_mean <- safe_mean(harmful$judgement[harmful$perp_outgroup == 1])
  ingroup_mean <- safe_mean(harmful$judgement[harmful$perp_outgroup == 0 & harmful$perp_control == 0])

  paste(
    "The observed Tobit outcome is the raw moral-judgment score from -9 to 9, where lower values indicate harsher condemnation.",
    "Descriptively, accepted harmful deals receive much lower ratings than rejected deals",
    "(mean judgment", format_number(accept_mean, 2), "versus", format_number(reject_mean, 2), ").",
    "Within the harmful-decision sample, same-faculty harm averages",
    format_number(harmful_same, 2), "judgment points compared with",
    format_number(harmful_diff, 2), "for cross-faculty harm.",
    "Outgroup perpetrators average", format_number(outgroup_mean, 2),
    "judgment points versus", format_number(ingroup_mean, 2), "for labeled ingroup perpetrators."
  )
}

# Summarize the most important model coefficients in prose.
compose_model_narrative <- function(model_results) {
  main_table <- model_results$main_harmful_tobit$coefficients
  betrayal_table <- model_results$betrayal_tobit$coefficients

  paste(
    "In the main harmful-decision Tobit model,",
    describe_key_term(
      main_table,
      "iri_total_z",
      "higher empathy is associated with more favorable judgments",
      "higher empathy is associated with harsher judgments"
    ),
    describe_key_term(
      main_table,
      "perp_outgroup",
      "Outgroup perpetrators receive more favorable judgments than ingroup perpetrators",
      "Outgroup perpetrators receive harsher judgments than ingroup perpetrators"
    ),
    describe_key_term(
      main_table,
      "iri_total_z:perp_outgroup",
      "The empathy slope becomes less negative in outgroup cases than ingroup cases",
      "The empathy slope becomes more negative in outgroup cases than ingroup cases"
    ),
    "In the same-faculty harm model,",
    describe_key_term(
      betrayal_table,
      "same_group_harm",
      "same-faculty harm is associated with more favorable judgments",
      "same-faculty harm is associated with harsher condemnation"
    )
  )
}

# Concatenate the hypothesis decisions into one paragraph for the reports.
compose_hypothesis_narrative <- function(hypothesis_table) {
  decision_lines <- apply(hypothesis_table, 1, function(row) {
    paste0(
      row[["Hypothesis"]], ": ",
      row[["NullDecision"]], "; ",
      row[["ResearchDecision"]], ". ",
      row[["Interpretation"]]
    )
  })

  paste(decision_lines, collapse = " ")
}

# Explain why Tobit is used and how much censoring is actually present.
compose_assumptions_narrative <- function(prep, tables) {
  participant_n <- nrow(prep$participants[prep$participants$analysis_include, , drop = FALSE])
  harmful_n <- nrow(prep$judgments_accept)
  left_share <- tables$judgement_summary$Value[tables$judgement_summary$Metric == "Left-censored share at -9 in accepted sample"]
  right_share <- tables$judgement_summary$Value[tables$judgement_summary$Metric == "Right-censored share at 9 in accepted sample"]

  paste(
    "The Tobit model is appropriate here because the observed dependent variable is bounded at -9 and 9 and the sample includes observations piled up at both limits.",
    "In the harmful-decision sample there are", harmful_n, "negotiator-level observations from", participant_n, "participants.",
    "The observed censoring shares are", format_pct(left_share, 1), "at the lower bound and", format_pct(right_share, 1), "at the upper bound.",
    "Substantive interpretation assumes a latent continuous evaluation process, approximately normal model errors, and correct specification of the linear predictor.",
    "Inference is clustered by participant to address repeated judgments within persons, but the estimates should still be read cautiously because the participant count is modest."
  )
}

# Record the empirical materials and the broad analysis steps for methods reporting.
compose_materials_methods_narrative <- function(prep) {
  paste(
    "Materials. The analysis uses the workbook data_final_FLORIDA.xlsx, the project codebook datacard.md, and the substantive framing in hypotheses.md.",
    "The source workbook contains 63 participant rows and repeated scenario blocks for 10 stages, with two negotiator decisions and two numerical judgments per stage.",
    "Methods. The pipeline reshapes the workbook from wide participant format to long negotiator-level format, scores the Interpersonal Reactivity Index, filters the primary analysis sample using the attention checks, estimates Tobit regressions for the bounded outcome, and exports tables, figures, Markdown, Word, LaTeX, and PDF reports."
  )
}

# Spell out the cleaning rules so readers can reconstruct sample inclusion.
compose_data_cleaning_narrative <- function(prep) {
  participants <- prep$participants
  analysis_participants <- participants[participants$analysis_include, , drop = FALSE]
  missing_iri <- sum(is.na(participants$iri_total))
  dropped_attention <- sum(!participants$attention_pass, na.rm = TRUE)

  paste(
    "Data cleaning proceeded in explicit steps.",
    "Step 1: validate that all required participant-level and scenario-level columns are present in the workbook.",
    "Step 2: preserve the raw participant-level file and derive IRI composite and subscale scores using row means with minimum non-missing thresholds.",
    "Step 3: compute the attention-check flag and define the primary analysis sample as participants who passed both checks and had a non-missing IRI composite.",
    "Step 4: reshape the repeated scenario variables into negotiator-level long format, yielding two judgment rows per stage per participant.",
    "Step 5: derive role, perpetrator alignment, victim alignment, same-group harm, and harmful-decision indicators.",
    "In this dataset,", dropped_attention, "participants fail at least one attention check and", missing_iri, "participants have a missing IRI composite, leaving", nrow(analysis_participants), "participants in the primary sample."
  )
}

# Explain the key modeling choices that connect the raw workbook to the regressions.
compose_transformation_narrative <- function() {
  paste(
    "Variable handling and transformation were kept close to the observed data structure.",
    "The dependent variable is the raw judgment score, bounded between -9 and 9, and it is modeled directly rather than transformed into a severity index.",
    "The empathy predictor is standardized as iri_total_z so its coefficient reflects a one-standard-deviation change in empathy.",
    "The main hypothesis models are restricted to harmful decisions where decision_accept = 1, because the hypotheses concern condemnation of harmful conduct rather than neutral or prosocial choices.",
    "Control variables include observer role, participant faculty, sex, age, socioeconomic status, stage indicators, and negotiator-slot indicators."
  )
}

# Report the main inferential takeaways while keeping the sign conventions explicit.
compose_results_narrative <- function(model_results, hypothesis_table) {
  main_table <- model_results$main_harmful_tobit$coefficients
  key_rows <- list(
    empathy = get_term_row(main_table, "iri_total_z"),
    outgroup = get_term_row(main_table, "perp_outgroup"),
    moderation = get_term_row(main_table, "iri_total_z:perp_outgroup"),
    victim = get_term_row(main_table, "victim_outgroup"),
    role = get_term_row(main_table, "role_observer")
  )

  paste(
    "The main harmful-decision Tobit model indicates that empathy has a negative estimated association with judgments, consistent with harsher condemnation at higher empathy, but the estimate is imprecise and not statistically distinguishable from zero",
    paste0("(b = ", format_number(key_rows$empathy$estimate, 2), ", p = ", format_p_value(key_rows$empathy$p_value), ")."),
    "The estimated outgroup-perpetrator effect is close to zero and slightly positive",
    paste0("(b = ", format_number(key_rows$outgroup$estimate, 2), ", p = ", format_p_value(key_rows$outgroup$p_value), ")."),
    "The empathy-by-outgroup interaction is negative, which matches the theorized direction for H3, but it is also statistically inconclusive",
    paste0("(b = ", format_number(key_rows$moderation$estimate, 2), ", p = ", format_p_value(key_rows$moderation$p_value), ")."),
    "Among the controls, outgroup victims are judged more negatively at the 0.05 threshold and observer-role evaluations are less negative than victim-role evaluations.",
    "Across the formal hypothesis tests, all four null hypotheses are retained at alpha = 0.05, although H2a is the closest case to the theorized pattern."
  )
}

# The discussion emphasizes uncertainty, sample size, and the strongest directional signal.
compose_discussion_narrative <- function(hypothesis_table) {
  h2a_row <- hypothesis_table[hypothesis_table$Hypothesis == "H2a", , drop = FALSE]

  paste(
    "The results suggest that the study has some directional consistency with the empathy and ingroup-betrayal accounts, but the evidence is not strong enough to support the research hypotheses under a conventional 5 percent threshold.",
    "The clearest substantive pattern is the negative point estimate for same-group harm, which is compatible with ingroup betrayal, yet still too uncertain for a firm conclusion",
    paste0("(p = ", h2a_row$PValue, ")."),
    "The lack of support for H2b indicates little evidence that outgroup perpetrators are condemned more harshly in this sample.",
    "Given the modest number of participants, repeated judgments nested within persons, and substantial censoring at the lower bound, the null findings should be interpreted as limited evidence rather than strong evidence of no effect."
  )
}

# Conclusion text is separated so it can be reused across output formats.
compose_conclusion_narrative <- function() {
  paste(
    "In conclusion, the bounded moral-judgment data are well suited to a Tobit framework, and the reporting pipeline now documents the full workflow from raw workbook to publication-style outputs.",
    "On the current data, the estimated effects do not justify rejecting the null hypotheses for H1, H2a, H2b, or H3 at alpha = 0.05.",
    "The most promising signal is the negative same-group-harm coefficient, which may warrant follow-up with a larger sample or a design with stronger identity contrasts."
  )
}

# Provide ASCII-style equations that render cleanly in Word without special math tooling.
word_equation_lines <- function() {
  c(
    "Observed outcome definition for Word:",
    "y_ij = -9 if y*_ij <= -9",
    "y_ij = y*_ij if -9 < y*_ij < 9",
    "y_ij = 9 if y*_ij >= 9",
    "",
    "Main harmful-decision model for Word:",
    "y*_ij = beta0 + beta1*IRI_i + beta2*OutgroupPerp_ij + beta3*ControlPerp_ij + beta4*VictimOutgroup_ij + beta5*(IRI_i*OutgroupPerp_ij) + beta6*(IRI_i*ControlPerp_ij) + gamma'*X_ij + e_ij",
    "",
    "Same-group-harm model for Word:",
    "y*_ij = alpha0 + alpha1*IRI_i + alpha2*SameGroupHarm_ij + alpha3*OutgroupPerp_ij + alpha4*VictimOutgroup_ij + delta'*X_ij + u_ij",
    "",
    "Where:",
    "IRI_i = standardized empathy composite",
    "OutgroupPerp_ij = 1 if the negotiator belongs to the evaluator's outgroup",
    "ControlPerp_ij = 1 if the negotiator's faculty label is hidden",
    "VictimOutgroup_ij = 1 if the victim belongs to the evaluator's outgroup",
    "SameGroupHarm_ij = 1 if negotiator and victim share the same labeled faculty",
    "X_ij = observer role, participant faculty, sex, age, socioeconomic status, stage indicators, and negotiator-slot indicator"
  )
}

# Build a portable relative path from the report folder to figures.
relative_markdown_path <- function(from_dir, to_file) {
  rel <- file.path("..", basename(dirname(to_file)), basename(to_file))
  gsub("\\\\", "/", rel)
}

# Write all summary tables to disk and return them for immediate report assembly.
write_tables <- function(prep, model_results, hypothesis_table, paths) {
  participant_summary <- build_participant_summary(prep)
  empathy_summary <- build_empathy_summary(prep)
  judgement_summary <- build_judgement_summary(prep)
  harmful_summary <- build_harmful_descriptives(prep)
  package_summary <- get_package_availability()
  model_fit_summary <- do.call(
    rbind,
    lapply(model_results, function(x) x$fit_stats)
  )

  table_bundle <- list(
    participant_summary = participant_summary,
    empathy_summary = empathy_summary,
    judgement_summary = judgement_summary,
    harmful_summary = harmful_summary,
    package_summary = package_summary,
    model_fit_summary = model_fit_summary,
    hypothesis_summary = hypothesis_table
  )

  for (table_name in names(table_bundle)) {
    utils::write.csv(
      table_bundle[[table_name]],
      file.path(paths$tables_dir, paste0(table_name, ".csv")),
      row.names = FALSE
    )
  }

  table_bundle
}

# Convert the Markdown report into Word if Pandoc is installed locally.
render_word_report <- function(paths) {
  pandoc_path <- find_pandoc_path()
  if (!nzchar(pandoc_path)) {
    return(FALSE)
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE) # Restore the original working directory after rendering.
  setwd(paths$report_dir) # Render from inside the report folder so relative links resolve correctly.

  status <- system2(
    command = pandoc_path,
    args = c(
      basename(paths$report_md),
      "-o",
      basename(paths$report_docx),
      "--toc"
    )
  )

  identical(status, 0L) # Return a clean TRUE/FALSE flag to the calling pipeline.
}

# Build the standalone LaTeX article line by line so it can be compiled even
# without rmarkdown or knitr dependencies.
build_latex_report <- function(prep, model_results, hypothesis_table, tables, figures, paths) {
  hypotheses_source <- if (nzchar(paths$hypotheses_file)) basename(paths$hypotheses_file) else "Not found"
  main_table <- model_results$main_harmful_tobit$coefficients
  betrayal_table <- model_results$betrayal_tobit$coefficients
  main_display <- main_table[main_table$term != "Log(scale)", c("label", "estimate", "std_error", "conf_low", "conf_high", "p_value")]
  names(main_display) <- c("Term", "Estimate", "RobustSE", "CI_Low", "CI_High", "PValue")
  betrayal_display <- betrayal_table[betrayal_table$term != "Log(scale)", c("label", "estimate", "std_error", "conf_low", "conf_high", "p_value")]
  names(betrayal_display) <- c("Term", "Estimate", "RobustSE", "CI_Low", "CI_High", "PValue")

  lines <- c(
    "\\documentclass[11pt]{article}",
    "\\usepackage[margin=1in]{geometry}",
    "\\usepackage[T1]{fontenc}",
    "\\usepackage[utf8]{inputenc}",
    "\\usepackage{lmodern}",
    "\\usepackage{graphicx}",
    "\\usepackage{booktabs}",
    "\\usepackage{longtable}",
    "\\usepackage{float}",
    "\\usepackage{array}",
    "\\usepackage{hyperref}",
    "\\hypersetup{colorlinks=true,linkcolor=black,urlcolor=blue,citecolor=black}",
    "\\title{Tobit Regression Analysis Report}",
    "\\author{Automated Analysis Pipeline}",
    paste0("\\date{Generated on ", escape_latex(format(Sys.time(), "%Y-%m-%d %H:%M %Z")), "}"),
    "\\begin{document}",
    "\\maketitle",
    "\\begin{abstract}",
    escape_latex("This report documents the full Tobit analysis workflow for the Florida experiment dataset, including materials, data cleaning, long-format transformation, bounded-outcome modeling, statistical interpretation, assumptions, and conclusions."),
    "\\end{abstract}",
    "\\section{Introduction}",
    escape_latex("This report evaluates how empathy and social identity relate to moral judgments of negotiators in an incentivized experiment. The reporting workflow is designed to be reproducible and publication-oriented, using the same fitted models that drive the Markdown and Word outputs."),
    "\\section{Materials and Methods}",
    "\\subsection{Inputs and Materials}",
    escape_latex(paste("Dataset:", basename(paths$input_file), "Codebook:", basename(paths$datacard_file), "Hypotheses source:", hypotheses_source, ".")),
    escape_latex(compose_materials_methods_narrative(prep)),
    "\\subsection{Sample and Data Structure}",
    escape_latex(compose_sample_narrative(prep)),
    to_latex_table(tables$participant_summary, "Participant summary.", "tab:participant_summary"),
    "\\subsection{Data Cleaning and Step-by-Step Data Handling}",
    escape_latex(compose_data_cleaning_narrative(prep)),
    "\\subsection{Variable Transformation and Analysis Setup}",
    escape_latex(compose_transformation_narrative()),
    "\\subsection{Word-Friendly Model Equations}",
    "\\begin{flushleft}",
    "\\textbf{Observed outcome definition}\\\\",
    "y\\_ij = -9 if y*\\_ij <= -9\\\\",
    "y\\_ij = y*\\_ij if -9 < y*\\_ij < 9\\\\",
    "y\\_ij = 9 if y*\\_ij >= 9\\\\[0.4em]",
    "\\textbf{Main harmful-decision model}\\\\",
    "y*\\_ij = beta0 + beta1*IRI\\_i + beta2*OutgroupPerp\\_ij + beta3*ControlPerp\\_ij + beta4*VictimOutgroup\\_ij + beta5*(IRI\\_i*OutgroupPerp\\_ij) + beta6*(IRI\\_i*ControlPerp\\_ij) + gamma'*X\\_ij + e\\_ij\\\\[0.4em]",
    "\\textbf{Same-group-harm model}\\\\",
    "y*\\_ij = alpha0 + alpha1*IRI\\_i + alpha2*SameGroupHarm\\_ij + alpha3*OutgroupPerp\\_ij + alpha4*VictimOutgroup\\_ij + delta'*X\\_ij + u\\_ij",
    "\\end{flushleft}",
    "\\subsection{Empathy Scale Quality}",
    to_latex_table(tables$empathy_summary, "Empathy scale summary.", "tab:empathy_summary"),
    "\\section{Results}",
    "\\subsection{Descriptive Results}",
    escape_latex(compose_descriptive_narrative(prep)),
    to_latex_table(tables$judgement_summary, "Judgment summary.", "tab:judgement_summary"),
    to_latex_table(tables$harmful_summary, "Harmful-decision descriptive summary by group and role.", "tab:harmful_summary"),
    latex_include_graphic(file.path("..", "figures", basename(figures$age)), "Age distribution in the analysis sample.", "fig:age"),
    latex_include_graphic(file.path("..", "figures", basename(figures$empathy)), "Empathy composite distribution.", "fig:empathy"),
    latex_include_graphic(file.path("..", "figures", basename(figures$decision)), "Raw moral judgment by decision type.", "fig:decision"),
    latex_include_graphic(file.path("..", "figures", basename(figures$group)), "Mean judgment by perpetrator alignment and evaluator role.", "fig:group"),
    "\\subsection{Model Results}",
    escape_latex(compose_model_narrative(model_results)),
    escape_latex(compose_results_narrative(model_results, hypothesis_table)),
    to_latex_table(main_display, "Main harmful-decision Tobit coefficients.", "tab:main_tobit", longtable = TRUE),
    to_latex_table(betrayal_display, "Same-group-harm Tobit coefficients.", "tab:betrayal_tobit", longtable = TRUE),
    to_latex_table(tables$model_fit_summary, "Model fit summary.", "tab:model_fit"),
    "\\subsection{Hypothesis Tests and Decisions}",
    escape_latex("Decision rule: reject H0 when p < 0.05; otherwise fail to reject H0. Support for the research hypothesis requires both statistical detectability and the theorized sign."),
    escape_latex(compose_hypothesis_narrative(hypothesis_table)),
    to_latex_table(hypothesis_table, "Hypothesis validation table.", "tab:hypothesis_validation", longtable = TRUE),
    "\\section{Assumptions}",
    escape_latex(compose_assumptions_narrative(prep, tables)),
    "\\section{Discussion}",
    escape_latex(compose_discussion_narrative(hypothesis_table)),
    "\\section{Conclusions}",
    escape_latex(compose_conclusion_narrative()),
    "\\section{Reproducibility Notes}",
    escape_latex("The pipeline exports synchronized outputs in CSV, PNG, Markdown, Word, LaTeX, and PDF formats. The LaTeX and PDF outputs are generated directly from the fitted model results in the same run as the other reports."),
    "\\end{document}"
  )

  write_text_file(lines, paths$report_tex) # Write the raw LaTeX source for optional manual inspection or editing.
}

# Compile the LaTeX article twice so references and tables settle correctly.
render_pdf_report <- function(paths) {
  pdflatex_path <- find_pdflatex_path()
  if (!nzchar(pdflatex_path) || !file.exists(paths$report_tex)) {
    return(FALSE)
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(paths$report_dir)

  tex_name <- basename(paths$report_tex)
  first_status <- system2(
    command = pdflatex_path,
    args = c("-interaction=nonstopmode", "-halt-on-error", tex_name),
    stdout = TRUE,
    stderr = TRUE
  )
  if (!is.null(attr(first_status, "status")) && attr(first_status, "status") != 0L) {
    return(FALSE)
  }

  second_status <- system2(
    command = pdflatex_path,
    args = c("-interaction=nonstopmode", "-halt-on-error", tex_name),
    stdout = TRUE,
    stderr = TRUE
  )

  status_code <- attr(second_status, "status") # The second run catches cross-references and final compilation state.
  is.null(status_code) || identical(status_code, 0L)
}

# Build the main Markdown report that most readers will open first.
build_report <- function(prep, model_results, hypothesis_table, tables, figures, paths) {
  hypotheses_source <- if (nzchar(paths$hypotheses_file)) basename(paths$hypotheses_file) else "Not found"
  main_table <- model_results$main_harmful_tobit$coefficients
  betrayal_table <- model_results$betrayal_tobit$coefficients

  main_display <- main_table[main_table$term != "Log(scale)", c("label", "estimate", "std_error", "conf_low", "conf_high", "p_value")]
  names(main_display) <- c("Term", "Estimate", "RobustSE", "CI_Low", "CI_High", "PValue")
  betrayal_display <- betrayal_table[betrayal_table$term != "Log(scale)", c("label", "estimate", "std_error", "conf_low", "conf_high", "p_value")]
  names(betrayal_display) <- c("Term", "Estimate", "RobustSE", "CI_Low", "CI_High", "PValue")

  lines <- c(
    "# Tobit Regression Pipeline Report",
    "",
    paste0("Generated on ", format(Sys.time(), "%Y-%m-%d %H:%M %Z"), "."),
    "",
    "## Inputs",
    paste0("- Dataset: `", basename(paths$input_file), "`"),
    paste0("- Codebook: `", basename(paths$datacard_file), "`"),
    paste0("- Hypotheses source: `", hypotheses_source, "`"),
    "",
    "## Analysis Design",
    "- Unit of analysis: negotiator-level judgments (two judgments per stage, ten stages per participant).",
    "- Primary outcome: the raw bounded judgment score `judgement`, observed from `-9` (acted very badly) to `9` (acted very well).",
    "- Primary sample: participants passing both attention checks and with a non-missing empathy composite.",
    "- Main hypothesis models are estimated on harmful decisions only (`decision_accept = 1`).",
    "- The main Tobit specification uses `survival::survreg()` with participant-clustered robust standard errors and censoring at `-9` and `9`.",
    "- H2a is operationalized as `same_group_harm = 1` when the negotiator and victim share the same labeled faculty.",
    "- H2b and H3 are operationalized relative to the evaluator: `perp_outgroup = 1` when the negotiator belongs to the participant's outgroup.",
    "",
    "## Word-Friendly Equations",
    word_equation_lines(),
    "",
    "## Sample Overview",
    compose_sample_narrative(prep),
    "",
    to_markdown_table(tables$participant_summary, digits = 2),
    "",
    "## Empathy Scale Summary",
    to_markdown_table(tables$empathy_summary, digits = 3),
    "",
    "## Package Availability",
    "The local environment only has `survival` installed. `AER`, `VGAM`, and `censReg` are included as recommended alternatives in the documentation, but the fitted model below uses `survival::survreg()` because it supports clustered robust inference cleanly in this project.",
    "",
    to_markdown_table(tables$package_summary, digits = 3),
    "",
    "## Assumptions and Sample Size",
    compose_assumptions_narrative(prep, tables),
    "",
    "## Descriptive Patterns",
    compose_descriptive_narrative(prep),
    "",
    to_markdown_table(tables$judgement_summary, digits = 3),
    "",
    to_markdown_table(tables$harmful_summary, digits = 3),
    "",
    "### Figures",
    paste0("![Age distribution](", relative_markdown_path(paths$report_dir, figures$age), ")"),
    "",
    paste0("![Empathy composite distribution](", relative_markdown_path(paths$report_dir, figures$empathy), ")"),
    "",
    paste0("![Judgment by decision](", relative_markdown_path(paths$report_dir, figures$decision), ")"),
    "",
    paste0("![Harmful decisions by group](", relative_markdown_path(paths$report_dir, figures$group), ")"),
    "",
    "## Tobit Models",
    compose_model_narrative(model_results),
    "",
    "### Main Harmful-Decision Tobit",
    to_markdown_table(main_display, digits = 3),
    "",
    "### Same-Faculty Harm Tobit",
    to_markdown_table(betrayal_display, digits = 3),
    "",
    "### Model Fit Summary",
    to_markdown_table(tables$model_fit_summary, digits = 3),
    "",
    "## Hypothesis Validation",
    "Decision rule: reject H0 when p < 0.05; otherwise fail to reject H0. For the research hypothesis, 'Support HA' means the coefficient is statistically detectable and points in the theorized direction.",
    "",
    compose_hypothesis_narrative(hypothesis_table),
    "",
    to_markdown_table(hypothesis_table, digits = 3),
    "",
    "## Output Inventory",
    "- `outputs/data/` contains participant-level and long-format analysis datasets.",
    "- `outputs/tables/` contains all summary and hypothesis tables in CSV format.",
    "- `outputs/models/` contains fitted Tobit models (`.rds`) plus coefficient and fit-stat CSV files.",
    "- `outputs/figures/` contains 300 dpi minimalist figures using a high-contrast blue palette suitable for low-vision reading.",
    "- `outputs/report/` contains the Markdown report, Word report, LaTeX article, PDF article, and session information.",
    ""
  )

  write_text_file(lines, paths$report_md)
}

# Save the R session details to support exact reproducibility of package versions.
write_session_info <- function(paths) {
  info_lines <- capture.output(sessionInfo()) # capture.output converts the printed session summary into plain text lines.
  write_text_file(info_lines, paths$session_info)
}

# End-to-end orchestration: ingest data, score variables, fit models, export
# tables/figures/reports, and return everything in one object for scripting use.
run_full_pipeline <- function(project_root = ".") {
  ensure_pipeline_dependencies()

  paths <- get_project_paths(project_root)
  ensure_output_dirs(paths)

  raw_data <- read_source_data(paths$input_file)
  validate_source_data(raw_data)
  prep <- prepare_analysis_data(raw_data)
  write_data_outputs(prep, paths)

  figures <- make_figures(prep, paths)
  model_results <- fit_models(prep, paths)
  hypothesis_table <- validate_hypotheses(model_results)
  tables <- write_tables(prep, model_results, hypothesis_table, paths)

  build_report(prep, model_results, hypothesis_table, tables, figures, paths)
  build_latex_report(prep, model_results, hypothesis_table, tables, figures, paths)
  write_session_info(paths)
  word_exported <- render_word_report(paths)
  pdf_exported <- render_pdf_report(paths)

  list(
    paths = paths,
    prep = prep,
    figures = figures,
    model_results = model_results,
    hypothesis_table = hypothesis_table,
    word_exported = word_exported,
    pdf_exported = pdf_exported
  )
}
