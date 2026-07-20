# display.R ---------------------------------------------------------------
#
# Helpers for showing a generated pattern to a human. These exist to defuse the
# single most common R-regex confusion: the difference between the *content* of
# a pattern string (`\d`, one backslash) and the way you must *write that string
# in R source* (`"\\d"`, two backslashes). `regexify()` returns the content; if
# you copy what you see at the console into an R script verbatim, `\d` is not a
# valid string escape. `as_r_literal()` gives you the paste-ready source form.

#' Render a pattern as paste-ready R source
#'
#' A regex like `\d{3}` must be written `"\\d{3}"` in R source because the
#' backslash is itself an escape character in R strings. `as_r_literal()`
#' produces exactly that quoted, double-escaped form so you can paste a
#' generated pattern straight into a script.
#'
#' @param x A pattern (character vector); typically the result of [regexify()].
#' @return A character vector of the same length, each element the R source
#'   literal (including surrounding quotes) for the corresponding pattern.
#' @examples
#' p <- regexify("Call 555-1234", "555-1234")
#' as_r_literal(p)
#' # copy the printed value, quotes and all, into your R code
#' @export
as_r_literal <- function(x) {
  # encodeString() doubles backslashes and escapes quotes; quote = '"' adds the
  # surrounding double quotes, giving a directly pasteable R string literal.
  encodeString(as.character(x), quote = "\"")
}

#' @export
print.regexify <- function(x, ...) {
  meta <- attr(x, "meta")
  pattern <- as.character(x)  # drops class + attributes, leaving the raw pattern

  cat("<regexify>\n")
  cat("  pattern : ", pattern, "\n", sep = "")
  cat("  R source: ", as_r_literal(pattern), "\n", sep = "")

  if (!is.null(meta)) {
    # Match summary is only present when the pattern was verified.
    if (!is.null(meta$matches)) {
      n <- length(meta$matches)
      shown <- take(meta$matches, 5L)
      detail <- if (n > 0L) paste0(" (", paste(shown, collapse = ", "), ")") else ""
      cat(sprintf("  matches : %d in text%s\n", n, detail))
    }
    if (length(meta$missing) > 0L) {
      cat("  ! unmatched: ", paste(meta$missing, collapse = ", "), "\n", sep = "")
    }
    if (length(meta$extras) > 0L) {
      cat("  ! also matched: ",
          paste(take(meta$extras, 5L), collapse = ", "), "\n", sep = "")
    }
  }
  invisible(x)
}
