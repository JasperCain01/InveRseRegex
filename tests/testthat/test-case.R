# Stage 10 tests: case-aware generalization.

test_that("case-aware default renders a capitalised word as [A-Z][a-z]+", {
  p <- regexify("x", "Abc", capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[A-Z][a-z]+")
  p <- regexify("x", "Margaret", capture = FALSE, anchor = "none",
                verify = FALSE)
  expect_equal(as.character(p), "[A-Z][a-z]+")
})

test_that("an all-caps run renders as [A-Z]{n}", {
  p <- regexify("x", "NASA", capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[A-Z]{4}")
})

test_that("case_sensitive = FALSE folds to [A-Za-z] (legacy behaviour)", {
  p <- regexify("x", "Abc", capture = FALSE, anchor = "none", verify = FALSE,
                case_sensitive = FALSE)
  expect_equal(as.character(p), "[A-Za-z]+")
})

test_that("case-aware merging across examples keeps the case structure", {
  p <- regexify("x", c("Margaret", "John", "Tony"),
                capture = FALSE, anchor = "none", verify = FALSE)
  # all are Title-case -> upper(1) + a lower word run
  expect_equal(as.character(p), "[A-Z][a-z]+")
})

test_that("upper and lower do not merge across examples", {
  # "AB" (all upper) vs "ab" (all lower) are structurally different.
  p <- regexify("x", c("AB", "ab"),
                capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "(?:[A-Z]{2}|[a-z]+)")
})

test_that("compact pins digits, capitals and punctuation but not word runs", {
  p <- regexify("x", "INV-0042 Paid", capture = FALSE, anchor = "none",
                verify = FALSE)
  expect_equal(as.character(p), "[A-Z]{3}-\\d{4}\\s[A-Z][a-z]+")
})

test_that("a single letter stays a single letter at compact", {
  p <- regexify("x", "5a", capture = FALSE, anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "\\d[a-z]")
  p <- regexify("x", "A1099", capture = FALSE, anchor = "none", verify = FALSE,
                case_sensitive = FALSE)
  expect_equal(as.character(p), "[A-Za-z]\\d{4}")
})

test_that("across examples, a word run is unbounded only if some run is 2+ long", {
  p <- regexify("x", c("Jo", "Al"), capture = FALSE, anchor = "none",
                verify = FALSE)
  expect_equal(as.character(p), "[A-Z][a-z]")
  p <- regexify("x", c("Jo", "Tom"), capture = FALSE, anchor = "none",
                verify = FALSE)
  expect_equal(as.character(p), "[A-Z][a-z]+")
})

test_that("a name learned from one example matches names of other lengths", {
  # The motivating case: under the old rule this pattern was
  # [A-Z][a-z]{7}\s[A-Z][a-z]{7}, which fitted only eight-letter names.
  p <- suppressWarnings(regexify("Margaret Thatcher was born in 1925.",
                                 "Margaret Thatcher 1925"))
  m <- regmatches("Clement Attlee was born in 1883.",
                  regexec(as.character(p), "Clement Attlee was born in 1883.",
                          perl = TRUE))[[1]]
  expect_equal(m[-1], c("Clement Attlee ", "1883"))
})

test_that("loose applies + to every run, including the leading capital", {
  # loose is uniform: each run (here upper(1) and lower(7)) gets a `+`.
  p <- regexify("x", "Margaret", generalize = "loose", capture = FALSE,
                anchor = "none", verify = FALSE)
  expect_equal(as.character(p), "[A-Z]+[a-z]+")
})
