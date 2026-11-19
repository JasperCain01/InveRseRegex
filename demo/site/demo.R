# demo.R -------------------------------------------------------------------
#
# R-side glue for the browser demo. The page (app.js) sends its inputs here and
# gets back a single JSON string describing everything it needs to draw: the
# generated pattern, the R source form, verification results, match positions
# for highlighting, a plain-English explanation and the four generalisation
# levels side by side.
#
# All regex *evaluation* happens here, in R, using the same engine and the same
# `perl =` setting InveRseRegex uses. JavaScript's regex engine is neither PCRE
# nor TRE (it rejects `[[:space:]]` outright), so highlighting in JS would
# misrepresent what R does.
#
# This file is deliberately not part of the package: it exists only for the
# demo, and keeping it here leaves the package dependency-free.

# --- Minimal JSON encoder -------------------------------------------------
#
# jsonlite is not available in the browser without an extra download, and the
# shapes we send are simple, so a small encoder is enough. Rules:
#   * a named list           -> JSON object
#   * an unnamed list        -> JSON array
#   * NULL                   -> null
#   * a length-1 atomic      -> scalar (NA -> null)
#   * any other atomic       -> array, unless wrapped in I() which forces an
#                               array even for length 1
# Character vectors are escaped per RFC 8259.
demo_json <- function(x) {
  if (is.null(x)) return("null")
  if (is.list(x)) {
    items <- vapply(x, demo_json, character(1))
    nms <- names(x)
    if (!is.null(nms) && length(x) > 0L) {
      keys <- demo_json_string(nms)
      return(paste0("{", paste0(keys, ":", items, collapse = ","), "}"))
    }
    if (!is.null(nms)) return("{}")
    return(paste0("[", paste(items, collapse = ","), "]"))
  }
  force_array <- inherits(x, "AsIs")
  x <- unclass(x)
  if (length(x) == 0L) return("[]")
  vals <- if (is.character(x)) {
    out <- demo_json_string(x)
    out[is.na(x)] <- "null"
    out
  } else if (is.logical(x)) {
    ifelse(is.na(x), "null", ifelse(x, "true", "false"))
  } else if (is.numeric(x)) {
    out <- format(x, scientific = FALSE, trim = TRUE, digits = 15)
    out[!is.finite(x)] <- "null"
    out
  } else {
    stop("demo_json: unsupported type ", typeof(x), call. = FALSE)
  }
  if (length(vals) == 1L && !force_array) return(vals)
  paste0("[", paste(vals, collapse = ","), "]")
}

demo_json_string <- function(x) {
  x <- enc2utf8(as.character(x))
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  # Any remaining control characters as \u00XX escapes.
  ctrl <- grepl("[\001-\037]", x, perl = TRUE)
  if (any(ctrl)) {
    x[ctrl] <- vapply(x[ctrl], function(s) {
      cps <- utf8ToInt(s)
      paste(ifelse(cps < 32L, sprintf("\\u%04x", cps), intToUtf8(cps, multiple = TRUE)),
            collapse = "")
    }, character(1), USE.NAMES = FALSE)
  }
  paste0("\"", x, "\"")
}

# --- Match positions -------------------------------------------------------
#
# R reports match positions in characters (Unicode code points), 1-based. The
# browser indexes strings in UTF-16 code units, 0-based, so any character
# outside the Basic Multilingual Plane (most emoji) counts as two there. Get
# this wrong and every highlight after an emoji is shifted by one.

# Offsets table: element k (1-based) is the UTF-16 offset at which code point k
# starts; the final element is the total UTF-16 length.
demo_utf16_offsets <- function(text) {
  cps <- utf8ToInt(enc2utf8(text))
  if (length(cps) == 0L || anyNA(cps)) return(0L)
  c(0L, cumsum(ifelse(cps > 0xFFFF, 2L, 1L)))
}

# Every match of `pattern` in `text`, with capture groups, as UTF-16 offsets.
# Returns a list of matches, each list(start, end, groups), where `end` is
# exclusive and `groups` is a list with one entry per capture group: either
# list(start, end) or NULL when that group did not take part in the match.
# At most `limit` matches are returned.
demo_spans <- function(pattern, text, perl = TRUE, limit = 500L,
                       use_bytes = FALSE) {
  text <- enc2utf8(text)
  m <- gregexec(pattern, text, perl = perl, useBytes = use_bytes)[[1]]
  if (identical(as.integer(m)[1], -1L)) return(list())
  lens <- attr(m, "match.length")
  # gregexec returns a matrix (rows: full match then groups; one column per
  # match). With no capture groups it can come back as a plain vector.
  if (is.null(dim(m))) {
    m <- matrix(m, nrow = 1L)
    lens <- matrix(lens, nrow = 1L)
  }
  # When R matched byte-wise, positions are byte offsets. (R also flags pure
  # ASCII input as byte-wise, where bytes and characters coincide.) Convert the
  # positions of groups that took part; non-participating groups stay < 1.
  if (isTRUE(attr(m, "useBytes")) && grepl("[^\001-\177]", text, perl = TRUE)) {
    b2c <- demo_byte_to_char(text)
    hit <- m > 0L
    ends <- b2c[m[hit] + lens[hit]]
    starts <- b2c[m[hit]] + 1L
    m[hit] <- starts
    lens[hit] <- ends - (starts - 1L)
  }
  off <- demo_utf16_offsets(text)
  conv <- function(start, len) {
    if (is.na(start) || start < 1L || len < 0L) return(NULL)
    list(start = off[start], end = off[start + len])
  }
  n <- min(ncol(m), limit)
  lapply(seq_len(n), function(j) {
    full <- conv(m[1L, j], lens[1L, j])
    groups <- if (nrow(m) > 1L) {
      lapply(2:nrow(m), function(i) conv(m[i, j], lens[i, j]))
    } else list()
    list(start = full$start, end = full$end, groups = groups)
  })
}

# For byte offset b (1-based), the number of whole characters before it.
demo_byte_to_char <- function(text) {
  chars <- strsplit(text, "", fixed = TRUE)[[1]]
  widths <- nchar(chars, type = "bytes")
  idx <- rep(seq_along(chars) - 1L, widths)
  c(idx, length(chars))
}

# --- Plain-English explanation --------------------------------------------
#
# Explains the patterns InveRseRegex *generates*. That is a small, known subset
# of regex syntax, which is what makes a hand-written explainer tractable; it is
# not a general regex explainer, and anything outside the subset is reported as
# "not explained" rather than guessed at. The page never lets the user edit the
# pattern, so that should only happen if the package starts emitting something
# new -- which the tests are designed to catch.

# Character-class atoms: regex text -> singular / plural noun.
.demo_atoms <- list(
  "\\d"         = c("digit", "digits"),
  "[0-9]"       = c("digit", "digits"),
  "\\s"         = c("whitespace character", "whitespace characters"),
  "[[:space:]]" = c("whitespace character", "whitespace characters"),
  "[A-Z]"       = c("uppercase letter (A-Z)", "uppercase letters (A-Z)"),
  "[a-z]"       = c("lowercase letter (a-z)", "lowercase letters (a-z)"),
  "[A-Za-z]"    = c("letter (A-Z or a-z)", "letters (A-Z or a-z)"),
  "."           = c("character of any kind", "characters of any kind")
)

# Split a pattern into a list of tokens: list(text, kind, ...).
demo_tokenize_pattern <- function(pattern) {
  s <- pattern
  toks <- list()
  push <- function(text, kind, ...) {
    toks[[length(toks) + 1L]] <<- c(list(text = text, kind = kind), list(...))
  }
  starts_with <- function(prefix) startsWith(s, prefix)
  while (nzchar(s)) {
    matched <- FALSE
    # Multi-character atoms first (longest match wins).
    for (atom in names(.demo_atoms)[order(-nchar(names(.demo_atoms)))]) {
      if (starts_with(atom)) {
        push(atom, "atom", atom = atom)
        s <- substring(s, nchar(atom) + 1L)
        matched <- TRUE
        break
      }
    }
    if (matched) next
    if (starts_with("\\b")) { push("\\b", "boundary"); s <- substring(s, 3L); next }
    if (starts_with("(?:")) { push("(?:", "open_nc"); s <- substring(s, 4L); next }
    q <- regmatches(s, regexpr("^(\\{[0-9]+(,[0-9]*)?\\}|[+*?])\\??", s, perl = TRUE))
    if (length(q) == 1L) { push(q, "quant"); s <- substring(s, nchar(q) + 1L); next }
    ch <- substr(s, 1L, 1L)
    if (ch == "\\" && nchar(s) >= 2L) {
      nxt <- substr(s, 2L, 2L)
      # In PCRE and TRE alike, a backslash before any ASCII punctuation means
      # that character literally.
      if (grepl("^[[:punct:]]$", nxt) && grepl("^[ -~]$", nxt)) {
        push(paste0("\\", nxt), "literal", value = nxt)
      } else {
        push(paste0("\\", nxt), "unknown")
      }
      s <- substring(s, 3L)
      next
    }
    kind <- switch(ch, "^" = "start", "$" = "end", "(" = "open", ")" = "close",
                   "|" = "or", "[" = "unknown", NULL)
    if (is.null(kind)) push(ch, "literal", value = ch) else push(ch, kind)
    s <- substring(s, 2L)
  }
  toks
}

demo_quant_phrase <- function(q, sing, plur) {
  lazy <- nchar(q) > 1L && endsWith(q, "?")
  base <- if (lazy) substr(q, 1L, nchar(q) - 1L) else q
  phrase <- if (base == "+") {
    paste("One or more", plur)
  } else if (base == "*") {
    paste("Zero or more", plur)
  } else if (base == "?") {
    paste("Optionally, one", sing)
  } else {
    nums <- regmatches(base, gregexpr("[0-9]+", base))[[1]]
    if (!grepl(",", base, fixed = TRUE)) {
      paste("Exactly", nums[1], plur)
    } else if (length(nums) == 1L) {
      paste("At least", nums[1], plur)
    } else {
      paste("Between", nums[1], "and", nums[2], plur)
    }
  }
  if (lazy) phrase <- paste0(phrase, ", as few as possible")
  phrase
}

# Explain a generated pattern as a list of list(token, meaning) rows.
demo_explain <- function(pattern) {
  toks <- demo_tokenize_pattern(pattern)
  rows <- list()
  add <- function(token, meaning) {
    rows[[length(rows) + 1L]] <<- list(token = token, meaning = meaning)
  }
  quote_text <- function(x) paste0("“", x, "”")
  group_no <- 0L
  stack <- character(0)  # labels of currently open groups
  lit_buf <- character(0)
  lit_raw <- character(0)
  flush_literals <- function() {
    if (length(lit_buf) == 0L) return(invisible())
    txt <- paste(lit_buf, collapse = "")
    raw <- paste(lit_raw, collapse = "")
    add(raw, if (length(lit_buf) == 1L) {
      paste("The character", quote_text(txt))
    } else {
      paste("The exact text", quote_text(txt))
    })
    lit_buf <<- character(0)
    lit_raw <<- character(0)
  }
  i <- 1L
  n <- length(toks)
  while (i <= n) {
    t <- toks[[i]]
    nxt <- if (i < n) toks[[i + 1L]] else NULL
    has_q <- !is.null(nxt) && nxt$kind == "quant"
    if (t$kind == "literal" && !has_q) {
      lit_buf <- c(lit_buf, t$value)
      lit_raw <- c(lit_raw, t$text)
      i <- i + 1L
      next
    }
    flush_literals()
    if (t$kind %in% c("atom", "literal")) {
      if (t$kind == "atom") {
        nouns <- .demo_atoms[[t$atom]]
      } else {
        lit <- quote_text(t$value)
        nouns <- c(paste("character", lit), paste("characters", lit))
      }
      if (has_q) {
        add(paste0(t$text, nxt$text), demo_quant_phrase(nxt$text, nouns[1], nouns[2]))
        i <- i + 2L
      } else {
        add(t$text, paste("One", nouns[1]))
        i <- i + 1L
      }
      next
    }
    meaning <- switch(
      t$kind,
      start = "Start of the text",
      end = "End of the text",
      boundary = "Word boundary: the edge between a word character and anything else",
      or = "Or: the pattern on either side may match",
      open = {
        group_no <- group_no + 1L
        stack <- c(stack, paste("capture group", group_no))
        paste0("Start of capture group ", group_no, " (the part you want back)")
      },
      open_nc = {
        stack <- c(stack, "group")
        "Start of a group that is not captured"
      },
      close = {
        label <- if (length(stack)) stack[length(stack)] else "group"
        stack <- stack[-length(stack)]
        paste0("End of ", label)
      },
      quant = "Repeat the previous item (not explained further)",
      "Not explained: outside the syntax InveRseRegex generates"
    )
    add(t$text, meaning)
    i <- i + 1L
  }
  flush_literals()
  rows
}

# --- Snippets ---------------------------------------------------------------

demo_snippets <- function(pattern, flavor) {
  lit <- InveRseRegex::as_r_literal(pattern)
  perl <- if (flavor == "pcre") ", perl = TRUE" else ""
  out <- list(
    list(label = "stringr: extract the first match",
         code = paste0("stringr::str_extract(x, ", lit, ")")),
    list(label = "stringr: matrix of full match and capture groups",
         code = paste0("stringr::str_match(x, ", lit, ")")),
    list(label = "base R: does each string match?",
         code = paste0("grepl(", lit, ", x", perl, ")")),
    list(label = "base R: extract every match",
         code = paste0("regmatches(x, gregexpr(", lit, ", x", perl, "))"))
  )
  if (flavor == "posix") {
    out[[1]]$note <- out[[2]]$note <-
      "stringr uses the ICU engine; the POSIX flavour is meant for base R."
  }
  out
}

# --- Main entry point -------------------------------------------------------

# Call regexify() with verification on, collecting its warnings rather than
# letting them escape. Errors are returned (as condition objects), not thrown.
demo_regexify <- function(text, want, generalize, flavor, capture, anchor,
                          case_sensitive, fill) {
  warnings <- character(0)
  result <- tryCatch(
    withCallingHandlers(
      InveRseRegex::regexify(text, want, generalize = generalize,
                             flavor = flavor, capture = capture,
                             anchor = anchor, case_sensitive = case_sensitive,
                             fill = fill, verify = TRUE),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) e
  )
  list(result = result, warnings = warnings)
}

# Run regexify() and build everything the page needs. Errors in the user's
# input come back as list(ok = FALSE, error = <message>).
demo_run <- function(text, want, generalize = "compact", flavor = "pcre",
                     capture = TRUE, anchor = "auto", case_sensitive = TRUE,
                     fill = "skip", test_text = "") {
  text <- enc2utf8(as.character(text))
  want <- enc2utf8(as.character(want))
  if (length(text) == 0L || all(!nzchar(want))) {
    return(list(ok = FALSE, error = "Enter some text and the part of it you want."))
  }
  run <- demo_regexify(text, want, generalize, flavor, capture, anchor,
                       case_sensitive, fill)
  if (inherits(run$result, "error")) {
    return(list(ok = FALSE, error = conditionMessage(run$result)))
  }
  pattern <- as.character(run$result)
  meta <- attr(run$result, "meta")
  perl <- flavor == "pcre"

  levels <- lapply(c("exact", "class", "compact", "loose"), function(lv) {
    r <- demo_regexify(text, want, lv, flavor, capture, anchor,
                       case_sensitive, fill)
    if (inherits(r$result, "error")) {
      return(list(level = lv, pattern = NULL, missing = 0L, extras = 0L,
                  error = conditionMessage(r$result)))
    }
    m <- attr(r$result, "meta")
    list(level = lv, pattern = as.character(r$result),
         missing = length(m$missing), extras = length(m$extras))
  })

  list(
    ok = TRUE,
    pattern = pattern,
    r_literal = InveRseRegex::as_r_literal(pattern),
    warnings = I(run$warnings),
    missing = I(as.character(meta$missing)),
    extras = I(as.character(meta$extras)),
    examples = lapply(seq_along(text), function(i) {
      list(text = text[[i]], spans = demo_spans(pattern, text[[i]], perl))
    }),
    test = if (nzchar(test_text)) demo_spans(pattern, enc2utf8(test_text), perl) else list(),
    explain = demo_explain(pattern),
    levels = levels,
    snippets = demo_snippets(pattern, flavor)
  )
}

# What the page actually calls: always returns a JSON string.
demo_run_json <- function(...) {
  out <- tryCatch(demo_run(...), error = function(e) {
    list(ok = FALSE, error = paste("Internal error:", conditionMessage(e)))
  })
  demo_json(out)
}
