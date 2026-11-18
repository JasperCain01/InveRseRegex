# Stage 10 tests: case-aware generalization.

test_that("case-aware default renders a capitalised word as [A-Z][a-z]{n}", {
  p <- regexify("x", "Abc", capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[A-Z][a-z]{2}")
  p <- regexify("x", "Margaret", capture = FALSE, anchor = "none",
                verify = FALSE)
  expect_equal(as.character(p), "[A-Z][a-z]{7}")
})

test_that("an all-caps run renders as [A-Z]{n}", {
  p <- regexify("x", "NASA", capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[A-Z]{4}")
})

test_that("case_sensitive = FALSE folds to [A-Za-z] (legacy behaviour)", {
  p <- regexify("x", "Abc", capture = FALSE, anchor = "none", verify = FALSE,
                case_sensitive = FALSE)
  expect_equal(as.character(p), "[A-Za-z]{3}")
})

test_that("case-aware merging across examples keeps the case structure", {
  p <- regexify("x", c("Margaret", "John", "Tony"),
                capture = FALSE, anchor = "none", verify = FALSE)
  # all are Title-case -> upper(1) + lower run merged into a range
  expect_equal(as.character(p), "[A-Z][a-z]{3,7}")
})

test_that("upper and lower do not merge across examples", {
  # "AB" (all upper) vs "ab" (all lower) are structurally different.
  p <- regexify("x", c("AB", "ab"),
                capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "(?:[A-Z]{2}|[a-z]{2})")
})

test_that("loose applies + to every run, including the leading capital", {
  # loose is uniform: each run (here upper(1) and lower(7)) gets a `+`.
  p <- regexify("x", "Margaret", generalize = "loose", capture = FALSE,
                anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[A-Z]+[a-z]+")
})
