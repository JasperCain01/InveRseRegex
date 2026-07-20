# Core generation tests (stage 3): tokenising a single value into a pattern at
# each generalization level, capture groups, and the PCRE/POSIX flavors.
# Anchoring inference, verification and multi-value support are tested
# separately (stage 4).

test_that("compact is the default and merges runs into {n}", {
  p <- regexify("Call 555-1234 today", "555-1234", anchor = "none",
                verify = FALSE)
  expect_equal(as.character(p), "(\\d{3}-\\d{4})")
})

test_that("capture can be switched off", {
  p <- regexify("x", "555-1234", capture = FALSE, anchor = "none",
                verify = FALSE)
  expect_equal(as.character(p), "\\d{3}-\\d{4}")
})

test_that("class level emits one atom per character", {
  p <- regexify("x", "ab12", generalize = "class", capture = FALSE,
                anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[A-Za-z][A-Za-z]\\d\\d")
})

test_that("loose level uses + quantifiers for class tokens", {
  p <- regexify("x", "ab12", generalize = "loose", capture = FALSE,
                anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[A-Za-z]+\\d+")
})

test_that("exact level escapes the literal value", {
  p <- regexify("x", "a.b+c", generalize = "exact", capture = FALSE,
                anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "a\\.b\\+c")
})

test_that("posix flavor swaps in POSIX atoms", {
  p <- regexify("x", "5 a", generalize = "compact", flavor = "posix",
                capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[0-9][[:space:]][A-Za-z]")
})

test_that("other-run of a repeated literal uses {n}, not +", {
  p <- regexify("x", "a--b", generalize = "loose", capture = FALSE,
                anchor = "none", verify = FALSE)
  # letters become +, but the repeated '-' stays a literal with {2}
  # ('-' is not escaped: it is not special outside a character class)
  expect_equal(as.character(p), "[A-Za-z]+-{2}[A-Za-z]+")
})

test_that("explicit anchors wrap correctly outside the capture group", {
  line <- regexify("42", "42", anchor = "line", verify = FALSE)
  expect_equal(as.character(line), "^(\\d{2})$")

  word <- regexify("x 42 y", "42", anchor = "word", verify = FALSE)
  expect_equal(as.character(word), "\\b(\\d{2})\\b")
})

test_that("input validation rejects bad arguments", {
  expect_error(regexify(c("a", "b"), "a"), "single string")
  expect_error(regexify("a", character(0)), "at least one value")
  expect_error(regexify("a", "a", generalize = "nope"))
})
