# utils.R -----------------------------------------------------------------
#
# Small internal helpers shared across the package. Nothing here is exported.

# The set of characters that carry special meaning in a PCRE pattern *outside*
# a character class. Any literal we emit must have these escaped with a
# backslash so the generated regex matches the character itself.
#
# Judgement call: we escape only characters that are actually special outside a
# character class. In particular `-` and `/` are NOT escaped — `-` is only
# special inside `[...]`, and we never build classes out of user literals (our
# only character classes are the fixed atoms `[A-Za-z]` etc.), so escaping it
# would just add noise (`\d{3}\-\d{4}`) to patterns humans have to read. `/` is
# never special in PCRE. The result is cleaner, still-correct output.
.regex_metachars <- c(
  "\\", "^", "$", ".", "|", "?", "*", "+",
  "(", ")", "[", "]", "{", "}"
)

# Escape a single literal character for safe inclusion in a pattern.
escape_regex_char <- function(ch) {
  if (ch %in% .regex_metachars) paste0("\\", ch) else ch
}

# Escape every character of a string as a literal (used by the `exact` level).
escape_regex <- function(x) {
  chars <- strsplit(x, "", fixed = TRUE)[[1]]
  paste(vapply(chars, escape_regex_char, character(1)), collapse = "")
}

# Resolve the argument-matching for the small set of choice arguments in one
# place, so error messages are consistent. `match.arg()` already gives good
# messages; this wrapper just documents intent at call sites.
match_choice <- function(arg, choices) {
  match.arg(arg, choices)
}
