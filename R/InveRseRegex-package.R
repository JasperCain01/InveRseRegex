#' InveRseRegex: infer regular expressions from example text
#'
#' InveRseRegex inverts the usual regex workflow. Rather than writing a pattern
#' to find text, you supply the text and the value(s) you want to extract, and
#' the package infers a regular expression that captures them — generalised at a
#' level you choose and verified against the input.
#'
#' The main entry point is [regexify()]. See [as_r_literal()] for turning a
#' generated pattern into paste-ready R source.
#'
#' @keywords internal
"_PACKAGE"
