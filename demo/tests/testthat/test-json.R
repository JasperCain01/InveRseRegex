# demo_json(): the hand-rolled encoder the page relies on to read R's output.

test_that("scalars, vectors and NULL encode as JSON values", {
  expect_equal(demo_json(1L), "1")
  expect_equal(demo_json(2.5), "2.5")
  expect_equal(demo_json(TRUE), "true")
  expect_equal(demo_json("a"), "\"a\"")
  expect_equal(demo_json(NULL), "null")
  expect_equal(demo_json(c(1L, 2L)), "[1,2]")
  expect_equal(demo_json(c(NA, TRUE)), "[null,true]")
  expect_equal(demo_json(NA_character_), "null")
})

test_that("I() forces an array even for one value, and empties are []", {
  expect_equal(demo_json(I("a")), "[\"a\"]")
  expect_equal(demo_json(I(character(0))), "[]")
  expect_equal(demo_json(character(0)), "[]")
  expect_equal(demo_json(list()), "[]")
})

test_that("named lists become objects and unnamed lists arrays", {
  expect_equal(demo_json(list(a = 1L, b = list(2L, "x"))),
               "{\"a\":1,\"b\":[2,\"x\"]}")
  expect_equal(demo_json(list(a = NULL)), "{\"a\":null}")
})

test_that("strings are escaped, including backslashes and control characters", {
  expect_equal(demo_json("a\"b"), "\"a\\\"b\"")
  expect_equal(demo_json("\\d"), "\"\\\\d\"")
  expect_equal(demo_json("a\nb\tc"), "\"a\\nb\\tc\"")
  expect_equal(demo_json("x\001y"), "\"x\\u0001y\"")
})

test_that("non-ASCII text passes through as UTF-8", {
  expect_equal(demo_json("café \U0001F600"), "\"café \U0001F600\"")
})

test_that("output round-trips through a real JSON parser", {
  skip_if_not_installed("jsonlite")
  x <- list(s = "q\"\\\né", v = I(c("a", "b")), n = 3L, l = list(TRUE, NULL))
  back <- jsonlite::fromJSON(demo_json(x), simplifyVector = FALSE)
  expect_equal(back$s, x$s)
  expect_equal(unlist(back$v), c("a", "b"))
  expect_equal(back$n, 3L)
  expect_equal(back$l, list(TRUE, NULL))
})
