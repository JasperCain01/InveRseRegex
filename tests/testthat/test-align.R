# Stage 9 tests: aligning a non-contiguous `want` to its `text` (exclusions).

test_that("align returns a single segment for a contiguous want", {
  al <- InveRseRegex:::align_want_to_text("call 555-1234 now", "555-1234")
  expect_true(al$ok)
  expect_true(InveRseRegex:::align_is_plain(al))
  expect_equal(InveRseRegex:::align_segments(al), "555-1234")
})

test_that("align splits a non-contiguous want into segments and fillers", {
  al <- InveRseRegex:::align_want_to_text(
    "Margaret Thatcher was born in 1925.", "Margaret Thatcher 1925")
  expect_true(al$ok)
  types <- vapply(al$parts, `[[`, character(1), "type")
  expect_equal(types, c("segment", "fill", "segment"))
  expect_equal(al$parts[[2]]$value, "was born in ")
  expect_equal(InveRseRegex:::align_segments(al),
               c("Margaret Thatcher ", "1925"))
})

test_that("align drops leading filler before the first segment", {
  al <- InveRseRegex:::align_want_to_text("id: ABC123", "ABC123")
  # "id: " precedes the segment but is not emitted as a part.
  expect_equal(vapply(al$parts, `[[`, character(1), "type"), "segment")
  expect_equal(al$parts[[1]]$start, 5L)
})

test_that("align reports ok = FALSE when want is not a subsequence", {
  al <- InveRseRegex:::align_want_to_text("hello world", "xyz")
  expect_false(al$ok)
})

test_that("headline: non-contiguous want yields captured segments + skip", {
  p <- regexify("Margaret Thatcher was born in 1925.",
                "Margaret Thatcher 1925")
  expect_equal(as.character(p),
               "\\b([A-Z][a-z]{7}\\s[A-Z][a-z]{7}\\s).*?(\\d{4})\\b")
  # And it really matches the source text.
  expect_true(grepl(as.character(p),
                    "Margaret Thatcher was born in 1925.", perl = TRUE))
})

test_that("fill = 'literal' keeps the excluded text", {
  p <- regexify("Margaret Thatcher was born in 1925.",
                "Margaret Thatcher 1925", fill = "literal",
                anchor = "none", verify = FALSE)
  expect_equal(as.character(p),
               "([A-Z][a-z]{7}\\s[A-Z][a-z]{7}\\s)was born in (\\d{4})")
})

test_that("fill = 'class' generalises the excluded text", {
  p <- regexify("Margaret Thatcher was born in 1925.",
                "Margaret Thatcher 1925", fill = "class",
                anchor = "none", verify = FALSE)
  expect_equal(as.character(p),
    "([A-Z][a-z]{7}\\s[A-Z][a-z]{7}\\s)[a-z]{3}\\s[a-z]{4}\\s[a-z]{2}\\s(\\d{4})")
})

test_that("a want that is not a subsequence warns and falls back", {
  expect_warning(
    regexify("hello world", "xzq"),
    "not found within its"
  )
})
