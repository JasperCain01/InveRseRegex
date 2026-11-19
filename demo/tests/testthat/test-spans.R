# demo_spans(): match positions converted to the browser's UTF-16 offsets.

test_that("ASCII matches report 0-based, end-exclusive offsets", {
  s <- demo_spans("\\d{3}", "ab 123 cd 456")
  expect_length(s, 2)
  expect_equal(c(s[[1]]$start, s[[1]]$end), c(3, 6))
  expect_equal(c(s[[2]]$start, s[[2]]$end), c(10, 13))
  expect_equal(s[[1]]$groups, list())
})

test_that("no match gives an empty list", {
  expect_equal(demo_spans("\\d", "abc"), list())
})

test_that("capture groups are reported per match", {
  s <- demo_spans("(\\d+)-(\\d+)", "1-22 333-4")
  expect_length(s, 2)
  expect_equal(s[[1]]$groups[[2]], list(start = 2, end = 4))
  expect_equal(s[[2]]$groups[[1]], list(start = 5, end = 8))
})

test_that("a group that does not take part in the match is NULL", {
  s <- demo_spans("a(x)?(b)", "ab", perl = TRUE)
  expect_null(s[[1]]$groups[[1]])
  expect_equal(s[[1]]$groups[[2]], list(start = 1, end = 2))
})

test_that("characters outside the BMP count as two UTF-16 units", {
  txt <- "\U0001F600 x 42 \U0001F600\U0001F600 y 7"
  s <- demo_spans("\\d+", txt)
  # Naive code-point counting would give 4 and 13; UTF-16 gives 5 and 15.
  expect_equal(s[[1]]$start, 5)
  expect_equal(s[[2]]$start, 15)
})

test_that("offsets slice out exactly what R matched, for any script", {
  texts <- c("plain 123 text",
             "café 123 naïve 45",
             "\U0001F600 123 \U0001F680 45 中文 6",
             "line one 1\nline two 22")
  for (txt in texts) {
    for (perl in c(TRUE, FALSE)) {
      pat <- if (perl) "\\d+" else "[0-9]+"
      s <- demo_spans(pat, txt, perl = perl)
      want <- regmatches(txt, gregexpr(pat, txt, perl = perl))[[1]]
      got <- vapply(s, function(m) utf16_slice(txt, m$start, m$end), character(1))
      expect_equal(got, want)
    }
  }
})

test_that("byte-wise matching gives the same offsets as character-wise", {
  txt <- "caf\u00e9 12 \U0001F600 (345) \u4e2d 6"
  for (perl in c(TRUE, FALSE)) {
    pat <- "\\(?([0-9]+)\\)?"
    expect_equal(demo_spans(pat, txt, perl = perl, use_bytes = TRUE),
                 demo_spans(pat, txt, perl = perl, use_bytes = FALSE))
  }
})

test_that("POSIX (TRE) groups are converted too", {
  txt <- "éé ab 12"
  s <- demo_spans("([a-z]+)[[:space:]]([0-9]+)", txt, perl = FALSE)
  expect_equal(utf16_slice(txt, s[[1]]$groups[[2]]$start, s[[1]]$groups[[2]]$end), "12")
})

test_that("the number of matches is capped", {
  s <- demo_spans("a", strrep("a", 20), limit = 5L)
  expect_length(s, 5)
})
