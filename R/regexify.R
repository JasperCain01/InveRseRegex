# regexify.R --------------------------------------------------------------
#
# The public entry point. `regexify()` takes example text and the value(s) the
# user wants to extract from it, and returns a regular expression that captures
# them. The heavy lifting of turning a value into a pattern lives in the
# per-token renderer below; `regexify()` orchestrates tokenising, rendering,
# wrapping in a capture group, anchoring, and (from stage 4) verification.

# --- Per-token rendering -------------------------------------------------
#
# `base_fragment()` maps a single token to its "atom": the smallest regex piece
# that matches one character of that class, in the requested flavor.
#
#   flavor = "pcre"  : digit -> \d      alpha -> [A-Za-z]   space -> \s
#   flavor = "posix" : digit -> [0-9]   alpha -> [A-Za-z]   space -> [[:space:]]
#
# For an "other" token we emit the escaped literal character itself. Note that
# in R source, "\\d" is the two-character string backslash + d — i.e. the real
# regex atom `\d`. The double backslash is R's string escaping, not part of the
# pattern (see also `as_r_literal()`).
base_fragment <- function(tok, flavor) {
  if (tok$class == "digit") return(if (flavor == "pcre") "\\d" else "[0-9]")
  if (tok$class == "alpha") return("[A-Za-z]")
  if (tok$class == "space") return(if (flavor == "pcre") "\\s" else "[[:space:]]")
  # "other": a single, escaped literal character.
  escape_regex_char(tok$char)
}

# `render_token()` applies the generalization level to a token's atom.
#
#   exact   : handled by the caller (whole value escaped literally).
#   class   : one atom per character, no quantifier (e.g. \d\d\d).
#   compact : atom + {n} when the run repeats (e.g. \d{3}); bare atom when n==1.
#   loose   : atom + `+` for the class-based tokens (e.g. \d+).
#
# Judgement call: quantifier generalization (`{n}` / `+`) is only applied to the
# class-based tokens (digit/alpha/space). "other" literals are never turned into
# `+` — `\-+` would surprisingly match "----" — so a repeated literal uses `{n}`
# and a lone literal stays exact. This keeps generated patterns intuitive.
render_token <- function(tok, level, flavor) {
  base <- base_fragment(tok, flavor)
  n <- tok$n

  if (tok$class == "other") {
    if (level == "class") return(strrep(base, n))
    if (n == 1L) return(base)
    return(paste0(base, "{", n, "}"))
  }

  switch(
    level,
    class   = strrep(base, n),
    compact = if (n == 1L) base else paste0(base, "{", n, "}"),
    loose   = paste0(base, "+"),
    # `exact` never reaches here (handled upstream); guard anyway.
    stop("unhandled generalize level: ", level, call. = FALSE)
  )
}

# Turn one literal value into a pattern body (no capture group, no anchors).
value_to_body <- function(value, level, flavor) {
  if (level == "exact") return(escape_regex(value))
  toks <- tokenize(value)
  if (length(toks) == 0L) return("")  # empty value -> empty body
  fragments <- vapply(toks, render_token, character(1),
                      level = level, flavor = flavor)
  paste(fragments, collapse = "")
}

# --- Construction of the return object -----------------------------------
#
# `regexify()` returns a character scalar carrying the pattern, given the class
# "regexify" so it can print nicely (see print.regexify), plus metadata in
# attributes. It IS an ordinary character underneath, so it can be passed
# straight to stringr::str_extract(), grepl(), regmatches(), etc.
new_regexify <- function(pattern, meta = list()) {
  structure(pattern, class = c("regexify", "character"), meta = meta)
}

#' Infer a regular expression from example text
#'
#' The inverse of the usual regex workflow: instead of writing a pattern to
#' find text, you supply the text and the value(s) you want, and `regexify()`
#' returns a regular expression that captures them.
#'
#' @param text A single string: the example text the value(s) come from. Used
#'   for anchoring decisions and (when `verify = TRUE`) to check the generated
#'   pattern actually matches.
#' @param want The substring(s) to match, as a character vector. A single value
#'   is the common case; several values cause the pattern to be generalised so
#'   it matches all of them.
#' @param generalize How aggressively to generalise. One of `"compact"` (merge
#'   runs into `{n}` quantifiers, the default), `"class"` (one class atom per
#'   character), `"loose"` (`+` quantifiers) or `"exact"` (escaped literal).
#' @param flavor Regex flavor of the output. `"pcre"` (default) uses `\\d`,
#'   `\\s`, `\\b` and works with stringr and base R when `perl = TRUE`.
#'   `"posix"` uses `[0-9]`, `[[:space:]]` for use with base R's default engine.
#' @param capture Wrap the matched value in a capture group so tools like
#'   `stringr::str_match()` return it. `TRUE` by default.
#' @param anchor How to anchor the pattern. `"auto"` (default) anchors the whole
#'   string with `^`/`$` when `want` is the entire `text`, otherwise adds word
#'   boundaries where appropriate. `"none"`, `"line"` (`^`/`$`) and `"word"`
#'   (`\\b`) force a specific behaviour.
#' @param verify If `TRUE` (default), check the generated pattern against `text`
#'   and warn if it fails to match a requested value or matches extra text.
#'
#' @return A length-one character vector of class `"regexify"` holding the
#'   pattern. Use it directly as a regex, or [as_r_literal()] to get the
#'   paste-ready R source form.
#'
#' @examples
#' regexify("Call 555-1234 today", "555-1234")
#' regexify("id: ABC-0099", "ABC-0099", generalize = "loose")
#' @export
regexify <- function(text, want,
                     generalize = c("compact", "class", "loose", "exact"),
                     flavor = c("pcre", "posix"),
                     capture = TRUE,
                     anchor = c("auto", "none", "line", "word"),
                     verify = TRUE) {
  generalize <- match_choice(generalize, c("compact", "class", "loose", "exact"))
  flavor <- match_choice(flavor, c("pcre", "posix"))
  anchor <- match_choice(anchor, c("auto", "none", "line", "word"))

  if (!is.character(text) || length(text) != 1L) {
    stop("`text` must be a single string.", call. = FALSE)
  }
  if (!is.character(want) || length(want) < 1L) {
    stop("`want` must be a character vector with at least one value.",
         call. = FALSE)
  }

  # Stage 3 supports a single value; multi-value generalization and anchoring
  # inference land in stage 4. Guard clearly so behaviour is never silently
  # wrong in the interim.
  if (length(want) > 1L) {
    stop("Multiple `want` values are not supported yet (coming in stage 4).",
         call. = FALSE)
  }

  body <- value_to_body(want, generalize, flavor)

  # Wrap the value in a capture group before anchoring, so anchors sit outside
  # the group: e.g. \b(\d{3}-\d{4})\b rather than (\b\d{3}-\d{4}\b).
  core <- if (isTRUE(capture)) paste0("(", body, ")") else body

  # Anchoring: stage 3 implements the explicit modes only. "auto" is treated as
  # "none" for now and gains real inference (whole-string vs word-boundary) in
  # stage 4.
  pattern <- apply_anchor(core, anchor, text = text, want = want)

  new_regexify(pattern, meta = list(
    text = text, want = want, generalize = generalize,
    flavor = flavor, capture = capture, anchor = anchor
  ))
}

# Apply an anchoring mode to an already-captured core pattern.
apply_anchor <- function(core, anchor, text, want) {
  switch(
    anchor,
    none = core,
    line = paste0("^", core, "$"),
    word = paste0("\\b", core, "\\b"),
    # "auto" inference is completed in stage 4; fall back to no anchor.
    auto = core,
    stop("unhandled anchor mode: ", anchor, call. = FALSE)
  )
}
