# Stage 5 tests: the display helpers.

test_that("as_r_literal doubles backslashes and adds quotes", {
  # Content '\d{3}' must become the R source literal "\\d{3}".
  expect_equal(as_r_literal("\\d{3}"), "\"\\\\d{3}\"")
})

test_that("as_r_literal works on a regexify object and is vectorised", {
  p <- regexify("Call 555-1234 today", "555-1234")
  expect_equal(as_r_literal(p), "\"\\\\b(\\\\d{3}-\\\\d{4})\\\\b\"")
  expect_length(as_r_literal(c("\\d", "\\s")), 2L)
})

test_that("print shows the pattern, source form and match summary", {
  p <- regexify("Call 555-1234 today", "555-1234")
  out <- paste(capture.output(print(p)), collapse = "\n")
  expect_match(out, "pattern")
  expect_match(out, "R source")
  expect_match(out, "555-1234")
})

test_that("print returns its input invisibly", {
  p <- regexify("42", "42", verify = FALSE)
  expect_invisible(print(p))
})

test_that("a regexify result is still usable directly as a pattern", {
  p <- regexify("Call 555-1234 today", "555-1234")
  # It is an ordinary character underneath, so base regex functions accept it.
  expect_true(grepl(p, "555-1234", perl = TRUE))
  expect_equal(regmatches("call 999-0000", regexpr(p, "call 999-0000",
                          perl = TRUE)), "999-0000")
})
