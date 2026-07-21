# align.R -----------------------------------------------------------------
#
# Aligning a `want` value against the `text` it was drawn from. This is what
# lets `regexify()` describe a value that is NOT a single contiguous slice of
# the text -- e.g. from
#
#     text = "Margaret Thatcher was born in 1925. "
#     want = "Margaret Thatcher 1925"
#
# the user actually wants the two capitalised words and the year, *excluding*
# the "was born in " that sits between them in the source. Tokenising `want`
# directly cannot express that (it would demand a single space between
# "Thatcher" and "1925"). Instead we align `want` to `text` and split it into:
#
#   * SEGMENTS -- maximal runs of `want` that appear contiguously in `text`.
#     Each becomes a generalised (and, when capturing, captured) sub-pattern.
#   * FILLERS  -- the stretches of `text` that fall *between* segments. These
#     are the excluded middle; they are rendered as a skip (`.*?`) or, at the
#     caller's option, the learned literal / a class.
#
# The alignment is a simple, predictable greedy longest-substring match: at each
# step we consume the longest prefix of the remaining `want` that is a substring
# of the remaining `text`. For a contiguous `want` this yields a single segment
# and no fillers, so the whole feature is invisible (and the output identical to
# before) in the common case.

# Find the 1-based index of the first occurrence of `needle` in `haystack`,
# matched literally (no regex). Returns -1L when absent. A tiny wrapper around
# gregexpr(fixed = TRUE) so intent is clear at the call sites below.
first_index_fixed <- function(needle, haystack) {
  if (!nzchar(needle)) return(1L)
  m <- regexpr(needle, haystack, fixed = TRUE)
  as.integer(m)
}

# Align `want` to `text`.
#
# Returns a list with:
#   ok    : TRUE if every character of `want` was placed (i.e. `want` is a
#           subsequence of `text`); FALSE if some tail could not be matched
#           (typically a typo -- `want` is not really drawn from `text`).
#   parts : an ordered list of parts, each a list with
#             type  : "segment" or "fill"
#             value : the literal substring
#             start : 1-based start position in `text` (segments only)
#             end   : 1-based end position in `text`   (segments only)
#           Leading filler (text before the first segment) is dropped -- the
#           pattern begins at the first thing the user asked for. A `fill` part
#           only ever appears *between* two segments.
#   leftover : the unplaced tail of `want` when ok is FALSE (for diagnostics).
align_want_to_text <- function(text, want) {
  parts <- list()
  if (!nzchar(want)) {
    return(list(ok = TRUE, parts = parts, leftover = ""))
  }

  pos <- 1L                     # current cursor into `text` (1-based)
  rem <- want                   # unconsumed tail of `want`
  ntext <- nchar(text)
  have_segment <- FALSE

  while (nzchar(rem)) {
    sub_text <- substr(text, pos, ntext)
    # Longest prefix of `rem` that is a substring of the remaining text.
    k <- nchar(rem)
    while (k > 0L &&
           first_index_fixed(substr(rem, 1L, k), sub_text) == -1L) {
      k <- k - 1L
    }
    if (k == 0L) {
      # The next `want` character does not occur in the remaining text: `want`
      # is not a subsequence of `text`. Stop and report the unplaced tail.
      return(list(ok = FALSE, parts = parts, leftover = rem))
    }

    seg <- substr(rem, 1L, k)
    rel <- first_index_fixed(seg, sub_text)      # offset within sub_text
    seg_start <- pos + rel - 1L
    seg_end <- seg_start + k - 1L

    # Text skipped to reach this segment is filler -- but only emit it when it
    # sits *between* segments (drop any leading filler).
    gap <- substr(text, pos, seg_start - 1L)
    if (nzchar(gap) && have_segment) {
      parts[[length(parts) + 1L]] <- list(type = "fill", value = gap)
    }
    parts[[length(parts) + 1L]] <- list(
      type = "segment", value = seg, start = seg_start, end = seg_end
    )

    have_segment <- TRUE
    pos <- seg_end + 1L
    rem <- substr(rem, k + 1L, nchar(rem))
  }

  list(ok = TRUE, parts = parts, leftover = "")
}

# Convenience predicates over an alignment result.

# Structural signature of an alignment: the ordered sequence of part types
# (segment/fill). Two alignments merge into one template only if these match.
align_structure <- function(al) {
  if (length(al$parts) == 0L) return("")
  paste(vapply(al$parts, `[[`, character(1), "type"), collapse = ">")
}

# TRUE when the alignment is a single segment with no fillers -- i.e. `want`
# was a contiguous slice of `text`. This is the common case, and it lets
# `regexify()` fall straight through to its original (pre-alignment) code path.
align_is_plain <- function(al) {
  length(al$parts) == 1L && al$parts[[1]]$type == "segment"
}

# Pull just the segment values (in order) out of an alignment.
align_segments <- function(al) {
  keep <- Filter(function(p) p$type == "segment", al$parts)
  vapply(keep, `[[`, character(1), "value")
}
