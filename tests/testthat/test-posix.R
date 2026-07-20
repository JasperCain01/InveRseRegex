# Stage 6 tests: harden the POSIX flavor by confirming the patterns it emits
# actually work with base R's DEFAULT regex engine (perl = FALSE, i.e. TRE) --
# that is the whole point of offering a POSIX flavor, so it is worth asserting
# against the real engine rather than just string-comparing the output.

# Helper: build a pattern and check it matches `value` under the base engine.
posix_matches <- function(text, want, value = want, ...) {
  p <- regexify(text, want, flavor = "posix", verify = FALSE, ...)
  grepl(as.character(p), value, perl = FALSE)
}

test_that("posix digit/space/alpha atoms match under the default engine", {
  expect_true(posix_matches("id 5 a", "5 a"))
})

test_that("posix compact quantifiers match under the default engine", {
  expect_true(posix_matches("call 555-1234 now", "555-1234"))
})

test_that("posix word-boundary auto anchor works under the default engine", {
  p <- regexify("call 555-1234 now", "555-1234", flavor = "posix",
                anchor = "auto", verify = FALSE)
  expect_match(as.character(p), "^\\\\b")            # begins with a \b
  expect_true(grepl(as.character(p), "call 555-1234 now", perl = FALSE))
})

test_that("posix alternation (non-capturing group) works under the default engine", {
  p <- regexify("x", c("42", "abc"), flavor = "posix", capture = FALSE,
                anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "(?:[0-9]{2}|[A-Za-z]{3})")
  expect_true(grepl(as.character(p), "abc", perl = FALSE))
  expect_true(grepl(as.character(p), "42", perl = FALSE))
})

test_that("posix verification uses the default engine and stays silent on a good match", {
  expect_no_warning(
    regexify("call 555-1234 now", "555-1234", flavor = "posix")
  )
})
