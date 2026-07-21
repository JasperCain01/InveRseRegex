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
# in R source, "\\d" is the two-character string backslash + d -- i.e. the real
# regex atom `\d`. The double backslash is R's string escaping, not part of the
# pattern (see also `as_r_literal()`).
base_fragment <- function(tok, flavor) {
  if (tok$class == "digit") return(if (flavor == "pcre") "\\d" else "[0-9]")
  if (tok$class == "alpha") return("[A-Za-z]")
  # Case-aware atoms. We use explicit ASCII ranges in BOTH flavors (rather than
  # POSIX `[[:upper:]]`/`[[:lower:]]`) so the result is locale-independent, in
  # keeping with the tokenizer's ASCII-only philosophy.
  if (tok$class == "upper") return("[A-Z]")
  if (tok$class == "lower") return("[a-z]")
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
# `+` -- `\-+` would surprisingly match "----" -- so a repeated literal uses `{n}`
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
value_to_body <- function(value, level, flavor, case_sensitive = TRUE) {
  if (level == "exact") return(escape_regex(value))
  toks <- tokenize(value, case_sensitive = case_sensitive)
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

# Build the pattern body (no capture, no anchors) for one or more values that
# occupy the SAME position (a single segment observed across several examples,
# or several alternative `want` values). Returns list(body, alt) where
# `alt = TRUE` means the body is a bare alternation needing a surrounding group.
build_body <- function(values, level, flavor, case_sensitive = TRUE) {
  if (level == "exact") {
    uv <- unique(values)
    if (length(uv) == 1L) return(list(body = escape_regex(uv), alt = FALSE))
    return(list(body = paste(vapply(uv, escape_regex, character(1)),
                             collapse = "|"),
                alt = TRUE))
  }

  tok_list <- lapply(values, tokenize, case_sensitive = case_sensitive)
  sigs <- vapply(tok_list, tok_signature, character(1))

  # Aligned (and non-empty): merge into one template.
  if (length(unique(sigs)) == 1L && length(tok_list[[1]]) > 0L) {
    return(list(body = merge_render(tok_list, level, flavor), alt = FALSE))
  }

  # A single distinct value that happened to tokenise to nothing (empty string).
  if (length(unique(values)) == 1L) {
    return(list(body = value_to_body(values[[1]], level, flavor, case_sensitive),
                alt = FALSE))
  }

  # Not aligned: honest alternation of the per-value patterns.
  bodies <- unique(vapply(values, value_to_body, character(1),
                          level = level, flavor = flavor,
                          case_sensitive = case_sensitive))
  list(body = paste(bodies, collapse = "|"), alt = length(bodies) > 1L)
}

# --- Multi-segment / multi-example assembly ------------------------------
#
# `build_core()` is the layer above `build_body()`. It takes the full set of
# examples (each a text + the want drawn from it), aligns every `want` to its
# `text`, and stitches the results into one pattern body:
#
#   * When every alignment is "plain" (a contiguous want == one segment, no
#     fillers) the whole thing reduces to the original single-body path, so the
#     output is byte-for-byte what earlier versions produced. This keeps the
#     simple, common case simple.
#
#   * Otherwise the examples describe a value with excluded middle sections. If
#     they share the same part structure we merge segment-by-segment (each
#     segment its own capture group) and render the fillers between them; if the
#     structures differ we fall back to an honest alternation of whole per-example
#     patterns.
#
# Returns list(body, alt) exactly like build_body, so the caller wraps/anchors
# it uniformly. When `capture` is TRUE the segment capture groups are already
# embedded in `body`, and the caller must NOT add another one; `captured` in the
# return says whether that has happened.

# Render a filler (excluded middle) according to the `fill` mode.
#   "skip"    : ".*?" -- a lazy wildcard, maximally tolerant.
#   "literal" : the exact skipped text (escaped). Across examples this is only
#               honoured when every example skipped the same text; otherwise we
#               fall back to ".*?" because no single literal is faithful.
#   "class"   : a generalised class pattern for the skipped text, merged across
#               examples the same way segments are.
render_fill <- function(values, fill, level, flavor, case_sensitive) {
  if (fill == "skip") return(".*?")
  if (fill == "literal") {
    uv <- unique(values)
    if (length(uv) == 1L) return(escape_regex(uv))
    return(".*?")  # differing fillers -> no faithful literal
  }
  # fill == "class"
  bb <- build_body(values, level, flavor, case_sensitive)
  if (!nzchar(bb$body)) return(".*?")
  if (isTRUE(bb$alt)) paste0("(?:", bb$body, ")") else bb$body
}

# Wrap a single segment's body as a pattern piece, honouring `capture`.
segment_piece <- function(bb, capture) {
  if (isTRUE(capture)) return(paste0("(", bb$body, ")"))
  if (isTRUE(bb$alt)) return(paste0("(?:", bb$body, ")"))
  bb$body
}

build_core <- function(aligns, examples, level, flavor, capture,
                       case_sensitive, fill) {
  wants <- vapply(examples, `[[`, character(1), "want")

  # Exact level ignores alignment: escape the literal want(s) verbatim.
  if (level == "exact") {
    bb <- build_body(wants, level, flavor, case_sensitive)
    return(list(body = bb$body, alt = bb$alt, captured = FALSE))
  }

  # Common case: every want is a contiguous slice of its text -> one segment
  # each, no fillers. Delegate to the original single-body path unchanged.
  if (all(vapply(aligns, align_is_plain, logical(1)))) {
    bb <- build_body(wants, level, flavor, case_sensitive)
    return(list(body = bb$body, alt = bb$alt, captured = FALSE))
  }

  # At least one want spans excluded middle sections. Merge only when every
  # example shares the same part structure; otherwise alternate whole patterns.
  structures <- vapply(aligns, align_structure, character(1))
  if (length(unique(structures)) == 1L) {
    parts0 <- aligns[[1]]$parts
    pieces <- vapply(seq_along(parts0), function(p) {
      vals <- vapply(aligns, function(a) a$parts[[p]]$value, character(1))
      if (parts0[[p]]$type == "segment") {
        segment_piece(build_body(vals, level, flavor, case_sensitive), capture)
      } else {
        render_fill(vals, fill, level, flavor, case_sensitive)
      }
    }, character(1))
    return(list(body = paste(pieces, collapse = ""),
                alt = FALSE, captured = isTRUE(capture)))
  }

  # Structures differ: alternate each example's own (uncaptured) pattern.
  branch <- function(al) {
    parts <- lapply(al$parts, function(p) {
      if (p$type == "segment") {
        build_body(p$value, level, flavor, case_sensitive)$body
      } else {
        render_fill(p$value, fill, level, flavor, case_sensitive)
      }
    })
    paste(unlist(parts), collapse = "")
  }
  bodies <- unique(vapply(aligns, branch, character(1)))
  list(body = paste(bodies, collapse = "|"),
       alt = length(bodies) > 1L, captured = FALSE)
}

# --- Example normalisation -----------------------------------------------
#
# Turn the (text, want) arguments into a list of examples, each a
# list(text=, want=). Semantics:
#   * text length 1, want length N  : N examples sharing one text (this covers
#     both a single want and the "several alternative wants" case).
#   * text length N, want length N  : N paired examples (learn from all at once).
#   * text length N, want length 1  : the one want recycled across N texts.
# Any other length combination is an error.
normalize_examples <- function(text, want) {
  nt <- length(text)
  nw <- length(want)
  n <- max(nt, nw)
  if (nt == 1L) text <- rep(text, n)
  if (nw == 1L) want <- rep(want, n)
  if (length(text) != length(want)) {
    stop("`text` and `want` must have the same length, or one of them ",
         "must be a single string.", call. = FALSE)
  }
  lapply(seq_len(n), function(i) list(text = text[[i]], want = want[[i]]))
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
#' @param text The example text the value(s) come from. Usually a single string.
#'   May also be a character vector the same length as `want`, in which case each
#'   `text`/`want` element is treated as one example and the pattern is learned
#'   from all of them at once. Used for anchoring and (when `verify = TRUE`) to
#'   check the generated pattern actually matches.
#' @param want The value(s) to match, as a character vector. A single value is
#'   the common case. Several values are learned together: with one `text` they
#'   are alternative examples of the same field; paired element-wise with a
#'   vector `text` they are one example each. A `want` need NOT be a contiguous
#'   slice of its `text` -- if it skips over intervening text (e.g. you want the
#'   name and the year but not the "was born in" between them), the skipped
#'   sections are excluded and bridged per the `fill` argument.
#' @param generalize How aggressively to generalise. One of `"compact"` (merge
#'   runs into `{n}` quantifiers, the default), `"class"` (one class atom per
#'   character), `"loose"` (`+` quantifiers) or `"exact"` (escaped literal).
#' @param flavor Regex flavor of the output. `"pcre"` (default) uses `\\d`,
#'   `\\s`, `\\b` and works with stringr and base R when `perl = TRUE`.
#'   `"posix"` uses `[0-9]`, `[[:space:]]` for use with base R's default engine.
#' @param capture Wrap each matched value/segment in a capture group so tools
#'   like `stringr::str_match()` return it. `TRUE` by default.
#' @param anchor How to anchor the pattern. `"auto"` (default) anchors the whole
#'   string with `^`/`$` when `want` is the entire `text`, otherwise adds word
#'   boundaries where appropriate. `"none"`, `"line"` (`^`/`$`) and `"word"`
#'   (`\\b`) force a specific behaviour.
#' @param verify If `TRUE` (default), check the generated pattern against `text`
#'   and warn if it fails to match a requested value or matches extra text.
#' @param case_sensitive If `TRUE` (default), letters are split by case, so a
#'   capitalised word "Margaret" becomes `[A-Z][a-z]{7}` and case structure is
#'   preserved. If `FALSE`, letters fold into a single case-insensitive class
#'   `[A-Za-z]`.
#' @param fill How to bridge excluded sections when `want` is not contiguous in
#'   `text`. `"skip"` (default) inserts a lazy wildcard `.*?`; `"literal"` keeps
#'   the exact skipped text (falling back to `.*?` if it differs across
#'   examples); `"class"` inserts a generalised class pattern for the skipped
#'   text.
#'
#' @return A length-one character vector of class `"regexify"` holding the
#'   pattern. Use it directly as a regex, or [as_r_literal()] to get the
#'   paste-ready R source form.
#'
#' @examples
#' regexify("Call 555-1234 today", "555-1234")
#' regexify("id: ABC-0099", "ABC-0099", generalize = "loose")
#' # A non-contiguous want: capture the name and the year, exclude the middle.
#' regexify("Margaret Thatcher was born in 1925.", "Margaret Thatcher 1925")
#' # Learn one pattern from several labelled examples at once.
#' regexify(c("Tony Blair was born in 1953.", "John Major was born in 1943."),
#'          c("Tony Blair 1953", "John Major 1943"))
#' @export
regexify <- function(text, want,
                     generalize = c("compact", "class", "loose", "exact"),
                     flavor = c("pcre", "posix"),
                     capture = TRUE,
                     anchor = c("auto", "none", "line", "word"),
                     verify = TRUE,
                     case_sensitive = TRUE,
                     fill = c("skip", "literal", "class")) {
  generalize <- match_choice(generalize, c("compact", "class", "loose", "exact"))
  flavor <- match_choice(flavor, c("pcre", "posix"))
  anchor <- match_choice(anchor, c("auto", "none", "line", "word"))
  fill <- match_choice(fill, c("skip", "literal", "class"))

  if (!is.character(text) || length(text) < 1L) {
    stop("`text` must be a character vector with at least one value.",
         call. = FALSE)
  }
  if (!is.character(want) || length(want) < 1L) {
    stop("`want` must be a character vector with at least one value.",
         call. = FALSE)
  }

  # Pair up text and want into examples, then align each want to its text so a
  # non-contiguous want is split into captured segments + excluded fillers.
  examples <- normalize_examples(text, want)
  aligns <- lapply(examples, function(e) align_want_to_text(e$text, e$want))

  # A want that is not even a subsequence of its text (often a typo) cannot be
  # aligned. Warn and fall back to treating it as a plain contiguous segment so
  # the function still returns a pattern derived from the want itself. The
  # heads-up is a text-consistency check, so it is gated on `verify` (opting out
  # of verification opts out of the nag) and skipped at the `exact` level (where
  # alignment is unused anyway).
  warn_align <- isTRUE(verify) && generalize != "exact"
  for (i in seq_along(aligns)) {
    if (!aligns[[i]]$ok) {
      if (warn_align) warning(sprintf(
        "`want` %s was not found within its `text`%s; the pattern is derived from `want` alone (check for typos).",
        encodeString(examples[[i]]$want, quote = "\""),
        if (nzchar(aligns[[i]]$leftover))
          paste0(" (unmatched from ",
                 encodeString(aligns[[i]]$leftover, quote = "\""), ")")
        else ""),
        call. = FALSE)
      aligns[[i]] <- list(
        ok = FALSE,
        parts = list(list(type = "segment", value = examples[[i]]$want,
                          start = NA_integer_, end = NA_integer_)),
        leftover = ""
      )
    }
  }

  built <- build_core(aligns, examples, generalize, flavor, capture,
                      case_sensitive, fill)

  # Wrap the body for capture (single-segment path) or, for a bare alternation,
  # in a non-capturing group so anchors bind to the whole alternation. When
  # `built$captured` is TRUE the segments already carry their own groups.
  core <- if (isTRUE(built$captured)) {
    built$body
  } else if (isTRUE(capture)) {
    paste0("(", built$body, ")")
  } else if (isTRUE(built$alt)) {
    paste0("(?:", built$body, ")")
  } else {
    built$body
  }

  # Anchors sit OUTSIDE the outermost group: e.g. \b(\d{3}-\d{4})\b.
  anc <- resolve_anchor(anchor, examples = examples, aligns = aligns)
  pattern <- paste0(anc$prefix, core, anc$suffix)

  result <- new_regexify(pattern, meta = list(
    text = text, want = want, generalize = generalize,
    flavor = flavor, capture = capture, anchor = anchor,
    case_sensitive = case_sensitive, fill = fill,
    matches = NULL, missing = character(0), extras = character(0)
  ))

  # Verify against each example's source text and surface problems as warnings.
  if (isTRUE(verify)) {
    v <- verify_pattern(pattern, examples = examples, aligns = aligns,
                        flavor = flavor, generalize = generalize)
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
resolve_anchor <- function(anchor, examples, aligns) {
  switch(
    anchor,
    none = list(prefix = "", suffix = ""),
    line = list(prefix = "^", suffix = "$"),
    word = list(prefix = "\\b", suffix = "\\b"),
    auto = infer_auto_anchor(examples, aligns),
    stop("unhandled anchor mode: ", anchor, call. = FALSE)
  )
}

# Infer sensible anchors from how the value sits inside the text.
#
#  * If a single example's want IS the whole text, anchor the line with ^ ... $.
#  * Otherwise add a word boundary (\b) at an edge only when it is BOTH useful
#    (the value's edge character is a word character) AND consistent with the
#    text (the neighbouring character is a non-word character or a string end).
#    The relevant edges are the FIRST segment's leading character and the LAST
#    segment's trailing character (fillers in the middle are excluded, so they
#    do not bear on the outer anchors). Checking the actual context means the
#    boundary we add never breaks the match we are describing; a boundary is
#    used only if it holds for every example.
infer_auto_anchor <- function(examples, aligns) {
  if (length(examples) == 1L &&
      align_is_plain(aligns[[1]]) &&
      identical(examples[[1]]$want, examples[[1]]$text)) {
    return(list(prefix = "^", suffix = "$"))
  }
  is_word <- function(ch) nzchar(ch) && grepl("[A-Za-z0-9_]", ch)

  ok_start <- TRUE
  ok_end <- TRUE
  for (i in seq_along(examples)) {
    txt <- examples[[i]]$text
    segs <- Filter(function(p) p$type == "segment", aligns[[i]]$parts)
    # No usable positions (e.g. an unaligned typo fallback): decline boundaries.
    if (length(segs) == 0L || is.na(segs[[1]]$start)) {
      ok_start <- FALSE; ok_end <- FALSE; break
    }
    first_seg <- segs[[1]]
    last_seg <- segs[[length(segs)]]
    first_ch <- substr(first_seg$value, 1L, 1L)
    last_ch <- substr(last_seg$value, nchar(last_seg$value),
                      nchar(last_seg$value))
    before <- if (first_seg$start == 1L) "" else
      substr(txt, first_seg$start - 1L, first_seg$start - 1L)
    after <- if (last_seg$end >= nchar(txt)) "" else
      substr(txt, last_seg$end + 1L, last_seg$end + 1L)

    ok_start <- ok_start && is_word(first_ch) && !is_word(before)
    ok_end <- ok_end && is_word(last_ch) && !is_word(after)
  }
  list(prefix = if (ok_start) "\\b" else "",
       suffix = if (ok_end) "\\b" else "")
}

# --- Verification --------------------------------------------------------
#
# Run the generated pattern against each example's source text and report:
#   * `missing` : requested values the pattern fails to match (a real bug in the
#                 result -- warned about loudly).
#   * `extras`  : substrings the pattern matches that were not requested (a sign
#                 the pattern may be over-general -- warned about as a heads-up).
# The full vector of matches (across examples) is returned for display.
#
# For a contiguous want the full match equals the want, so we compare directly.
# For a non-contiguous want the full match spans the excluded fillers too, so we
# instead check that the pattern's CAPTURE GROUPS recover each wanted segment.
verify_pattern <- function(pattern, examples, aligns, flavor,
                           generalize = "compact") {
  perl <- flavor == "pcre"
  all_full <- character(0)
  missing <- character(0)
  extras <- character(0)

  # De-duplicate identical (text, want) pairs so a recycled text is not
  # double-counted, and group wants by text for the extras count.
  seen <- character(0)
  for (i in seq_along(examples)) {
    txt <- examples[[i]]$text
    wnt <- examples[[i]]$want
    key <- paste(txt, wnt, sep = "\r")
    if (key %in% seen) next
    seen <- c(seen, key)

    # A non-contiguous want that could not be aligned was already reported at
    # construction time; re-checking would just repeat the news with a
    # misleading "try a looser level" hint, so skip it. (The `exact` level does
    # not use alignment, so it is verified normally even when ok is FALSE.)
    if (!aligns[[i]]$ok && generalize != "exact") next

    m <- gregexpr(pattern, txt, perl = perl)
    full <- regmatches(txt, m)[[1]]
    if (length(full) == 0L) full <- character(0)
    all_full <- c(all_full, full)

    if (align_is_plain(aligns[[i]])) {
      # Contiguous: the want should appear verbatim among the matches.
      if (!(wnt %in% full)) missing <- c(missing, wnt)
      extras <- c(extras, setdiff(full, examples[[i]]$want))
    } else {
      # Non-contiguous: check the capture groups recover the wanted segments.
      rm <- regexec(pattern, txt, perl = perl)
      groups <- regmatches(txt, rm)[[1]]
      captured <- if (length(groups) > 1L) groups[-1L] else character(0)
      segs <- align_segments(aligns[[i]])
      if (!all(segs %in% captured)) missing <- c(missing, wnt)
    }
  }
  missing <- unique(missing)
  extras <- unique(extras)

  if (length(missing) > 0L) {
    warning("Generated pattern does not match requested value(s): ",
            paste(missing, collapse = ", "),
            ". Try a looser `generalize` level or check the input.",
            call. = FALSE)
  }
  wanted_all <- unique(vapply(examples, `[[`, character(1), "want"))
  n_extra <- length(all_full) - sum(all_full %in% wanted_all)
  if (n_extra > 0L && length(extras) > 0L) {
    eg <- take(extras, 3L)
    warning(sprintf(
      "Generated pattern also matches %d other substring(s) in the text%s. Consider a stricter `generalize` level or anchoring.",
      n_extra,
      paste0(", e.g. ", paste(eg, collapse = ", "))),
      call. = FALSE)
  }
  list(matches = all_full, missing = missing, extras = extras)
}
