# Stage 4 tests: generalising across several `want` values.

test_that("aligned values with equal lengths share one template", {
  p <- regexify("John:42, Jane:37", c("42", "37"),
                capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "\\d{2}")
})

test_that("aligned values with differing lengths yield a range quantifier", {
  p <- regexify("x", c("42", "1234"),
                capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "\\d{2,4}")
})

test_that("aligned 'other' runs must share the literal character", {
  # Same class sequence but different separators -> NOT aligned -> alternation.
  p <- regexify("x", c("1-2", "1/2"),
                capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "(?:\\d-\\d|\\d/\\d)")
})

test_that("structurally different values fall back to an alternation", {
  p <- regexify("x", c("42", "abc"),
                capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "(?:\\d{2}|[a-z]{3})")
})

test_that("alternation is wrapped in a single capture group when capturing", {
  p <- regexify("x", c("42", "abc"),
                capture = TRUE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "(\\d{2}|[a-z]{3})")
})

test_that("multi-value with auto anchor and verify matches all values", {
  p <- regexify("John:42, Jane:37", c("42", "37"))
  expect_equal(as.character(p), "\\b(\\d{2})\\b")
  meta <- attr(p, "meta")
  expect_equal(meta$matches, c("42", "37"))
  expect_equal(meta$missing, character(0))
  expect_equal(meta$extras, character(0))
})

test_that("values from one text are not counted twice or as extras of each other", {
  expect_no_warning(p <- regexify("John:42, Jane:37", c("42", "37")))
  out <- capture.output(print(p))
  expect_true(any(grepl("matches : 2 in text (42, 37)", out, fixed = TRUE)))
  expect_false(any(grepl("also matched", out, fixed = TRUE)))
})

test_that("an unwanted match in a shared text is still reported", {
  expect_warning(p <- regexify("John:42, Jane:37, Bob:55", c("42", "37")),
                 "also matches 1 other")
  meta <- attr(p, "meta")
  expect_equal(meta$matches, c("42", "37", "55"))
  expect_equal(meta$extras, "55")
})
