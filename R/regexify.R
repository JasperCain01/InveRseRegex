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

# --- Multi-value generalization ------------------------------------------
#
# When the caller supplies several `want` values, we try to describe them all
# with one template. Two outcomes are possible:
#
#  * ALIGNED: every value tokenises to the same sequence of classes (and, for
#    "other" runs, the same literal characters). We then merge the per-position
#    run lengths into a range quantifier, so ("42", "37", "1234") -> \d{2,4}.
#
#  * NOT ALIGNED: the structures differ, so no single template is honest. We
#    fall back to an alternation of the individual patterns, e.g. (?:\d{2}|
#    [A-Za-z]{3}). This always works and does not pretend to a generality the
#    examples do not support.
#
# `build_body()` returns a list(body, alt): `alt = TRUE` means the body is an
# alternation and therefore needs a surrounding group when anchored.

# A structural signature for a tokenised value: the class of each run, plus the
# literal character for "other" runs (so "-" and "/" are not treated as
# interchangeable). Equal signatures => values can share one template.
tok_signature <- function(toks) {
  if (length(toks) == 0L) return("")
  parts <- vapply(toks, function(t) {
    if (t$class == "other") paste0("other:", t$char) else t$class
  }, character(1))
  paste(parts, collapse = "|")
}

# Render one merged position given the observed min/max run lengths across all
# aligned values. Shared by the single- and multi-value paths (for a single
# value nmin == nmax, so this reduces to the plain quantifier).
render_quant <- function(base, cls, nmin, nmax, level) {
  if (cls == "other") {
    if (nmin == nmax) return(if (nmin == 1L) base else paste0(base, "{", nmin, "}"))
    return(paste0(base, "{", nmin, ",", nmax, "}"))
  }
  if (level == "loose") return(paste0(base, "+"))
  if (nmin == nmax) {
    if (level == "class") return(strrep(base, nmin))
    return(if (nmin == 1L) base else paste0(base, "{", nmin, "}"))
  }
  # Differing lengths: a bounded range expresses "between nmin and nmax".
  paste0(base, "{", nmin, ",", nmax, "}")
}

# Merge a set of aligned tokenisations into a single body.
merge_render <- function(tok_list, level, flavor) {
  k <- length(tok_list[[1]])
  frags <- vapply(seq_len(k), function(i) {
    toks_i <- lapply(tok_list, `[[`, i)
    cls <- toks_i[[1]]$class
    ns <- vapply(toks_i, `[[`, integer(1), "n")
    base <- base_fragment(toks_i[[1]], flavor)
    render_quant(base, cls, min(ns), max(ns), level)
  }, character(1))
  paste(frags, collapse = "")
}

# Build the pattern body (no capture, no anchors) for one or more values.
build_body <- function(values, level, flavor) {
  if (level == "exact") {
    uv <- unique(values)
    if (length(uv) == 1L) return(list(body = escape_regex(uv), alt = FALSE))
    return(list(body = paste(vapply(uv, escape_regex, character(1)),
                             collapse = "|"),
                alt = TRUE))
  }

  tok_list <- lapply(values, tokenize)
  sigs <- vapply(tok_list, tok_signature, character(1))

  # Aligned (and non-empty): merge into one template.
  if (length(unique(sigs)) == 1L && length(tok_list[[1]]) > 0L) {
    return(list(body = merge_render(tok_list, level, flavor), alt = FALSE))
  }

  # A single distinct value that happened to tokenise to nothing (empty string).
  if (length(unique(values)) == 1L) {
    return(list(body = value_to_body(values[[1]], level, flavor), alt = FALSE))
  }

  # Not aligned: honest alternation of the per-value patterns.
  bodies <- unique(vapply(values, value_to_body, character(1),
                          level = level, flavor = flavor))
  list(body = paste(bodies, collapse = "|"), alt = length(bodies) > 1L)
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

  # Build the body (handles single and multiple `want` values).
  bb <- build_body(want, generalize, flavor)

  # Wrap for capture, or (for a bare alternation) in a non-capturing group so
  # anchors bind to the whole alternation rather than just one branch.
  core <- if (isTRUE(capture)) {
    paste0("(", bb$body, ")")
  } else if (isTRUE(bb$alt)) {
    paste0("(?:", bb$body, ")")
  } else {
    bb$body
  }

  # Anchors sit OUTSIDE the capture group: e.g. \b(\d{3}-\d{4})\b.
  anc <- resolve_anchor(anchor, text = text, want = want)
  pattern <- paste0(anc$prefix, core, anc$suffix)

  result <- new_regexify(pattern, meta = list(
    text = text, want = want, generalize = generalize,
    flavor = flavor, capture = capture, anchor = anchor,
    matches = NULL, missing = character(0), extras = character(0)
  ))

  # Verify against the source text and surface problems as warnings. The match
  # information is stashed in the object's metadata for the print method.
  if (isTRUE(verify)) {
    v <- verify_pattern(pattern, text = text, want = want, flavor = flavor)
    meta <- attr(result, "meta")
    meta$matches <- v$matches
    meta$missing <- v$missing
    meta$extras <- v$extras
    attr(result, "meta") <- meta
  }
  result
}

# --- Anchoring -----------------------------------------------------------
#
# Returns the prefix/suffix strings to place around the core pattern.
resolve_anchor <- function(anchor, text, want) {
  switch(
    anchor,
    none = list(prefix = "", suffix = ""),
    line = list(prefix = "^", suffix = "$"),
    word = list(prefix = "\\b", suffix = "\\b"),
    auto = infer_auto_anchor(text, want),
    stop("unhandled anchor mode: ", anchor, call. = FALSE)
  )
}

# Infer sensible anchors from how the value sits inside the text.
#
#  * If the single value IS the whole text, anchor the line with ^ ... $.
#  * Otherwise add a word boundary (\b) at an edge only when it is BOTH useful
#    (the value's edge character is a word character) AND consistent with the
#    text (the neighbouring character is a non-word character or a string end).
#    Checking the actual context means the boundary we add never breaks the
#    match we are trying to describe. Decisions are based on the first
#    occurrence of each value; a boundary is used only if it holds for all.
infer_auto_anchor <- function(text, want) {
  if (length(want) == 1L && identical(want, text)) {
    return(list(prefix = "^", suffix = "$"))
  }
  is_word <- function(ch) nzchar(ch) && grepl("[A-Za-z0-9_]", ch)

  ok_start <- TRUE
  ok_end <- TRUE
  for (w in want) {
    if (!nzchar(w)) { ok_start <- FALSE; ok_end <- FALSE; break }
    pos <- gregexpr(w, text, fixed = TRUE)[[1]][1]
    if (pos == -1L) { ok_start <- FALSE; ok_end <- FALSE; break }
    first_ch <- substr(w, 1L, 1L)
    last_ch <- substr(w, nchar(w), nchar(w))
    before <- if (pos == 1L) "" else substr(text, pos - 1L, pos - 1L)
    after_i <- pos + nchar(w)
    after <- if (after_i > nchar(text)) "" else substr(text, after_i, after_i)

    ok_start <- ok_start && is_word(first_ch) && !is_word(before)
    ok_end <- ok_end && is_word(last_ch) && !is_word(after)
  }
  list(prefix = if (ok_start) "\\b" else "",
       suffix = if (ok_end) "\\b" else "")
}

# --- Verification --------------------------------------------------------
#
# Run the generated pattern against the source text and report:
#   * `missing` : requested values the pattern fails to match (a real bug in the
#                 result — warned about loudly).
#   * `extras`  : substrings the pattern matches that were not requested (a sign
#                 the pattern may be over-general — warned about as a heads-up).
# The full vector of matches is returned for display.
verify_pattern <- function(pattern, text, want, flavor) {
  perl <- flavor == "pcre"
  m <- gregexpr(pattern, text, perl = perl)
  full <- regmatches(text, m)[[1]]
  if (length(full) == 0L) full <- character(0)

  wanted <- unique(want)
  missing <- setdiff(wanted, full)
  extras <- setdiff(full, wanted)

  if (length(missing) > 0L) {
    warning("Generated pattern does not match requested value(s): ",
            paste(missing, collapse = ", "),
            ". Try a looser `generalize` level or check the input.",
            call. = FALSE)
  }
  # Count extra *occurrences* (not just distinct values) beyond what was asked.
  n_extra <- length(full) - sum(full %in% wanted)
  if (n_extra > 0L) {
    eg <- utils::head(unique(extras), 3L)
    warning(sprintf(
      "Generated pattern also matches %d other substring(s) in the text%s. Consider a stricter `generalize` level or anchoring.",
      n_extra,
      if (length(eg)) paste0(", e.g. ", paste(eg, collapse = ", ")) else ""),
      call. = FALSE)
  }
  list(matches = full, missing = missing, extras = extras)
}
