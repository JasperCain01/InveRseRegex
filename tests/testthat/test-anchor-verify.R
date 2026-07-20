# Stage 4 tests: automatic anchoring inference and verification warnings.

test_that("auto anchors the whole line when want IS the entire text", {
  p <- regexify("42", "42", anchor = "auto", verify = FALSE)
  expect_equal(as.character(p), "^(\\d{2})$")
})

test_that("auto adds word boundaries at non-word edges", {
  p <- regexify("Call 555-1234 today", "555-1234", anchor = "auto",
                verify = FALSE)
  expect_equal(as.character(p), "\\b(\\d{3}-\\d{4})\\b")
})

test_that("auto omits a boundary where the value is glued to a word char", {
  # "1234" is embedded inside letters, so neither edge gets a boundary.
  p <- regexify("a1234b", "1234", anchor = "auto", verify = FALSE)
  expect_equal(as.character(p), "(\\d{4})")
})

test_that("verify is silent when the pattern matches exactly", {
  expect_no_warning(regexify("Call 555-1234 today", "555-1234"))
})

test_that("verify warns when a requested value is not matched", {
  expect_warning(
    regexify("hello world", "xyz", generalize = "exact"),
    "does not match"
  )
})

test_that("verify warns when the pattern over-matches", {
  # A lone digit with no boundary also matches the other digit in the text.
  expect_warning(
    regexify("a1 b2", "1", anchor = "none"),
    "other substring"
  )
})

test_that("match information is stored for the print method", {
  p <- regexify("Call 555-1234 today", "555-1234")
  meta <- attr(p, "meta")
  expect_equal(meta$matches, "555-1234")
  expect_equal(meta$missing, character(0))
})
