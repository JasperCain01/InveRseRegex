# tokenize.R --------------------------------------------------------------
#
# The tokenizer is the heart of InveRseRegex. It takes a literal string (the
# value the user wants to match) and breaks it into a sequence of "runs", where
# each run is a maximal stretch of characters that share a character *class*.
# The generaliser (see regexify.R) then turns each run into a regex fragment at
# the requested level of generality.
#
# Design / judgement calls captured here:
#
#  * We use FOUR coarse classes: "digit", "alpha", "space", "other".
#    - Letters can be handled in two ways, chosen by the `case_sensitive` flag
#      threaded down from `regexify()`:
#        * case_sensitive = TRUE (default): an "alpha" run is further split by
#          case into "upper" (`[A-Z]`) and "lower" (`[a-z]`) runs, so a
#          capitalised word "Margaret" tokenises to upper(1) + lower(7) and
#          naturally renders `[A-Z][a-z]{7}`. This is what makes patterns like
#          "the first two capitalised words" expressible.
#        * case_sensitive = FALSE: letters of either case fold into one "alpha"
#          class rendered `[A-Za-z]` (the original, case-insensitive behaviour),
#          which over-fits less when case is irrelevant.
#    - "space" covers any whitespace and is rendered `\s`.
#    - "other" is everything else (punctuation, symbols, and -- deliberately --
#      any non-ASCII character, since `[A-Za-z]`/`[0-9]` are ASCII-only here).
#      "other" runs are escaped and emitted literally, which is always safe.
#
#  * Runs of "other" are only merged when the *same* character repeats. "--" is
#    one run of '-' x2 (so it can become `\-{2}`), but "->" is two runs ('-'
#    then '>') because merging different literals would be meaningless.
#
#  * Non-ASCII handling: a character such as "e-acute" is classed "other" and
#    emitted as an escaped literal. It will still match; it simply is not
#    generalised. This keeps the package dependency-free and predictable. A
#    future Unicode-aware mode is noted in the implementation plan.

# Classify a single character into one of the four coarse classes.
#
# We test against ASCII ranges explicitly (rather than POSIX classes like
# `[[:alpha:]]`) so the behaviour does not silently change with the user's
# locale -- reproducibility matters more than locale-awareness for a code
# generator.
char_class <- function(ch) {
  if (grepl("[0-9]", ch)) return("digit")
  if (grepl("[A-Za-z]", ch)) return("alpha")
  if (grepl("[ \t\r\n\v\f]", ch)) return("space")
  "other"
}

# Refine a coarse class into a case-aware one. Only "alpha" is affected, and
# only when `case_sensitive` is TRUE: an uppercase letter becomes "upper", a
# lowercase letter becomes "lower". Every other class is returned unchanged.
# Keeping this separate from `char_class()` means the coarse classifier (and its
# behaviour) is preserved, and the case split is a thin, opt-out layer on top.
refine_class <- function(ch, coarse, case_sensitive) {
  if (case_sensitive && coarse == "alpha") {
    return(if (grepl("[A-Z]", ch)) "upper" else "lower")
  }
  coarse
}

# Break a string into class-runs.
#
# Returns a list of tokens. Each token is a list with:
#   class : one of "digit" / "upper" / "lower" / "alpha" / "space" / "other"
#           ("upper"/"lower" when case_sensitive, "alpha" when not)
#   value : the literal substring this run covers (useful for `exact` output
#           and for debugging)
#   char  : a single representative character of the run (used when emitting an
#           escaped literal for an "other" run)
#   n     : the number of characters in the run (drives quantifiers)
#
# `case_sensitive` (default TRUE) controls whether letter runs are split by
# case; see the header comment. An empty string yields an empty list, which
# callers must handle.
tokenize <- function(x, case_sensitive = TRUE) {
  if (!is.character(x) || length(x) != 1L) {
    stop("`tokenize()` expects a single string.", call. = FALSE)
  }
  chars <- strsplit(x, "", fixed = TRUE)[[1]]
  if (length(chars) == 0L) return(list())

  coarse <- vapply(chars, char_class, character(1))
  classes <- vapply(seq_along(chars), function(i) {
    refine_class(chars[[i]], coarse[[i]], case_sensitive)
  }, character(1))

  tokens <- list()
  run_start <- 1L

  # Walk the characters, closing off a run whenever the class changes -- or,
  # within an "other" run, whenever the literal character itself changes.
  emit <- function(from, to) {
    cls <- classes[[from]]
    piece <- paste(chars[from:to], collapse = "")
    list(class = cls, value = piece, char = chars[[from]], n = to - from + 1L)
  }

  if (length(chars) >= 2L) {
    for (i in 2:length(chars)) {
      same_class <- classes[[i]] == classes[[i - 1L]]
      # For "other", also require the exact same character to continue the run.
      same_run <- same_class &&
        !(classes[[i]] == "other" && chars[[i]] != chars[[i - 1L]])
      if (!same_run) {
        tokens[[length(tokens) + 1L]] <- emit(run_start, i - 1L)
        run_start <- i
      }
    }
  }
  # Close the final run.
  tokens[[length(tokens) + 1L]] <- emit(run_start, length(chars))
  tokens
}
