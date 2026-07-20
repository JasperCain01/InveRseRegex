# Tests for the tokenizer and character-class inference. These functions are
# internal, so we reach them with the `:::` operator.

test_that("char_class recognises the four coarse classes", {
  expect_equal(InveRseRegex:::char_class("7"), "digit")
  expect_equal(InveRseRegex:::char_class("q"), "alpha")
  expect_equal(InveRseRegex:::char_class("Q"), "alpha")
  expect_equal(InveRseRegex:::char_class(" "), "space")
  expect_equal(InveRseRegex:::char_class("\t"), "space")
  expect_equal(InveRseRegex:::char_class("-"), "other")
  expect_equal(InveRseRegex:::char_class("."), "other")
})

test_that("a non-ASCII letter is treated as 'other', not 'alpha'", {
  # This documents the deliberate ASCII-only scope of the alpha/digit classes.
  expect_equal(InveRseRegex:::char_class("é"), "other")  # e-acute
})

test_that("tokenize merges runs of the same class", {
  toks <- InveRseRegex:::tokenize("abc123")
  expect_equal(length(toks), 2L)
  expect_equal(toks[[1]]$class, "alpha")
  expect_equal(toks[[1]]$n, 3L)
  expect_equal(toks[[2]]$class, "digit")
  expect_equal(toks[[2]]$n, 3L)
})

test_that("tokenize folds mixed-case letters into a single alpha run", {
  toks <- InveRseRegex:::tokenize("AbcDef")
  expect_equal(length(toks), 1L)
  expect_equal(toks[[1]]$class, "alpha")
  expect_equal(toks[[1]]$n, 6L)
})

test_that("tokenize splits identical vs differing punctuation", {
  # "--" is one run of the same char; "->" is two runs.
  dashes <- InveRseRegex:::tokenize("--")
  expect_equal(length(dashes), 1L)
  expect_equal(dashes[[1]]$n, 2L)

  arrow <- InveRseRegex:::tokenize("->")
  expect_equal(length(arrow), 2L)
  expect_equal(arrow[[1]]$char, "-")
  expect_equal(arrow[[2]]$char, ">")
})

test_that("tokenize handles a phone-number-like string", {
  toks <- InveRseRegex:::tokenize("555-1234")
  expect_equal(vapply(toks, `[[`, character(1), "class"),
               c("digit", "other", "digit"))
  expect_equal(vapply(toks, `[[`, integer(1), "n"), c(3L, 1L, 4L))
})

test_that("tokenize handles single-character and empty strings", {
  one <- InveRseRegex:::tokenize("x")
  expect_equal(length(one), 1L)
  expect_equal(one[[1]]$class, "alpha")

  expect_equal(length(InveRseRegex:::tokenize("")), 0L)
})

test_that("escape helpers escape regex metacharacters", {
  expect_equal(InveRseRegex:::escape_regex_char("."), "\\.")
  expect_equal(InveRseRegex:::escape_regex_char("a"), "a")
  expect_equal(InveRseRegex:::escape_regex("a.b+c"), "a\\.b\\+c")
})
