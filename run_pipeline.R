args <- commandArgs(trailingOnly = TRUE) # Read optional command-line arguments passed to the script.
project_root <- if (length(args) >= 1L) args[[1]] else "." # Use the supplied project folder, or default to the current directory.

source(file.path(project_root, "R", "pipeline_functions.R")) # Load the reusable functions that score scales, fit Tobit models, and export reports.

results <- run_full_pipeline(project_root) # Execute the full statistical workflow from raw workbook to fitted models and report files.

cat("Pipeline completed.\n") # Signal that the script reached the end without an error.
cat("Markdown report:", results$paths$report_md, "\n") # Report the main human-readable output path first.
if (isTRUE(results$word_exported)) {
  cat("Word report:", results$paths$report_docx, "\n") # Pandoc was available, so the Markdown report was converted to Word.
} else {
  cat("Word report was not created because Pandoc was not found.\n") # Missing Pandoc prevents document conversion but not the analysis itself.
}
cat("LaTeX report:", results$paths$report_tex, "\n") # The LaTeX source is always written so the report can be compiled later if needed.
if (isTRUE(results$pdf_exported)) {
  cat("PDF report:", results$paths$report_pdf, "\n") # pdflatex succeeded, so the publication-style PDF is available.
} else {
  cat("PDF report was not created because pdflatex was not found or LaTeX compilation failed.\n") # Separate the analysis result from optional rendering failures.
}
