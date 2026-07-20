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
#  * We use FOUR coarse classes only: "digit", "alpha", "space", "other".
#    - Letters of either case are folded into a single "alpha" class rendered as
#      `[A-Za-z]`. Keeping upper/lower separate (e.g. `[A-Z][a-z]{2}` for "Abc")
#      is more specific but over-fits most real use cases and surprises users, so
#      the friendly default treats a letter as a letter. Case structure can still
#      be recovered by the caller escaping to the `exact` level.
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

# Break a string into class-runs.
#
# Returns a list of tokens. Each token is a list with:
#   class : one of "digit" / "alpha" / "space" / "other"
#   value : the literal substring this run covers (useful for `exact` output
#           and for debugging)
#   char  : a single representative character of the run (used when emitting an
#           escaped literal for an "other" run)
#   n     : the number of characters in the run (drives quantifiers)
#
# An empty string yields an empty list, which callers must handle.
tokenize <- function(x) {
  if (!is.character(x) || length(x) != 1L) {
    stop("`tokenize()` expects a single string.", call. = FALSE)
  }
  chars <- strsplit(x, "", fixed = TRUE)[[1]]
  if (length(chars) == 0L) return(list())

  classes <- vapply(chars, char_class, character(1))

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
