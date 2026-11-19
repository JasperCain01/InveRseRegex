# demo_run() / demo_run_json(): the single call the page makes.

test_that("a simple run returns the pattern and everything the page draws", {
  r <- demo_run("Call 555-1234 today", "555-1234")
  expect_true(r$ok)
  expect_equal(r$pattern, "\\b(\\d{3}-\\d{4})\\b")
  expect_equal(r$r_literal, "\"\\\\b(\\\\d{3}-\\\\d{4})\\\\b\"")
  expect_equal(r$examples[[1]]$spans[[1]][c("start", "end")], list(start = 5, end = 13))
  expect_equal(vapply(r$levels, `[[`, character(1), "level"),
               c("exact", "class", "compact", "loose"))
  expect_length(r$explain, 7)  # \b ( \d{3} - \d{4} ) \b
  expect_length(r$warnings, 0)
})

test_that("verification warnings and extras are reported, not thrown", {
  r <- demo_run("ab 12 cd 34", "12")
  expect_true(r$ok)
  expect_equal(as.character(r$extras), "34")
  expect_match(r$warnings, "also matches")
})

test_that("bad input comes back as ok = FALSE with a message", {
  r <- demo_run(c("a", "b", "c"), c("a", "b"))
  expect_false(r$ok)
  expect_match(r$error, "same length")
  expect_false(demo_run("abc", "")$ok)
})

test_that("the test text is matched with the generated pattern", {
  r <- demo_run("Call 555-1234 today", "555-1234", test_text = "999-0000 and 12-34")
  expect_length(r$test, 1)
  expect_equal(r$test[[1]][c("start", "end")], list(start = 0, end = 8))
})

test_that("snippets use perl = TRUE only for the PCRE flavour", {
  pc <- demo_run("a 12", "12")$snippets
  px <- demo_run("a 12", "12", flavor = "posix")$snippets
  expect_match(pc[[3]]$code, "perl = TRUE", fixed = TRUE)
  expect_false(grepl("perl", px[[3]]$code))
  expect_match(px[[1]]$note, "ICU")
})

test_that("demo_run_json always returns parseable JSON", {
  skip_if_not_installed("jsonlite")
  ok <- jsonlite::fromJSON(demo_run_json("Call 555-1234", "555-1234"))
  expect_true(ok$ok)
  bad <- jsonlite::fromJSON(demo_run_json(character(0), "x"))
  expect_false(bad$ok)
})
