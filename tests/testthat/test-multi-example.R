# Stage 11 tests: learning one pattern from several (text, want) examples.

test_that("parallel text/want vectors learn a shared template", {
  texts <- c("Margaret Thatcher was born in 1925. ",
             "John Major was born in 1943. ",
             "Tony Blair was born in 1953. ")
  wants <- c("Margaret Thatcher 1925",
             "John Major 1943",
             "Tony Blair 1953")
  p <- regexify(texts, wants)
  expect_equal(as.character(p),
               "\\b([A-Z][a-z]{3,7}\\s[A-Z][a-z]{4,7}\\s).*?(\\d{4})\\b")
  meta <- attr(p, "meta")
  expect_length(meta$matches, 3L)
  expect_equal(meta$missing, character(0))
})

test_that("the learned pattern extracts segments from every example", {
  texts <- c("Tony Blair was born in 1953. ",
             "John Major was born in 1943. ")
  wants <- c("Tony Blair 1953", "John Major 1943")
  p <- regexify(texts, wants, verify = FALSE)
  g1 <- regmatches(texts[1], regexec(as.character(p), texts[1], perl = TRUE))[[1]]
  expect_equal(g1[-1], c("Tony Blair ", "1953"))
  g2 <- regmatches(texts[2], regexec(as.character(p), texts[2], perl = TRUE))[[1]]
  expect_equal(g2[-1], c("John Major ", "1943"))
})

test_that("a single want recycled across several texts still verifies", {
  p <- regexify(c("code=AB12", "code=AB12 again"), "AB12", verify = FALSE)
  expect_true(grepl(as.character(p), "code=AB12", perl = TRUE))
})

test_that("structurally different examples fall back to an alternation", {
  # One want is contiguous (a bare year), the other is a two-field name+year.
  p <- regexify(c("year 1990", "Ada Lovelace in 1815"),
                c("1990", "Ada Lovelace 1815"),
                capture = FALSE, verify = FALSE, anchor = "none")
  expect_match(as.character(p), "\\|")   # an alternation
})
