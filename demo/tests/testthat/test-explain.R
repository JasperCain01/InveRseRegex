# demo_explain(): plain-English rows for the patterns InveRseRegex generates.

meanings <- function(p) vapply(demo_explain(p), `[[`, character(1), "meaning")
tokens <- function(p) vapply(demo_explain(p), `[[`, character(1), "token")

test_that("each atom and quantifier form has its own wording", {
  expect_equal(meanings("\\d"), "One digit")
  expect_equal(meanings("\\d{3}"), "Exactly 3 digits")
  expect_equal(meanings("[a-z]{2,5}"), "Between 2 and 5 lowercase letters (a-z)")
  expect_equal(meanings("[A-Z]+"), "One or more uppercase letters (A-Z)")
  expect_equal(meanings("[[:space:]]"), "One whitespace character")
  expect_equal(meanings("[0-9]{1,}"), "At least 1 digits")
  expect_equal(meanings(".*?"), "Zero or more characters of any kind, as few as possible")
})

test_that("anchors, boundaries, alternation and groups are explained", {
  expect_equal(meanings("^$"), c("Start of the text", "End of the text"))
  expect_match(meanings("\\b"), "Word boundary")
  expect_match(meanings("a|b")[2], "^Or")
  m <- meanings("(?:a)(b)(c)")
  expect_equal(m[c(1, 3)], c("Start of a group that is not captured", "End of group"))
  expect_equal(m[c(4, 6, 7, 9)], c("Start of capture group 1 (the part you want back)",
                                   "End of capture group 1",
                                   "Start of capture group 2 (the part you want back)",
                                   "End of capture group 2"))
})

test_that("consecutive literals merge into one row, escapes are unescaped", {
  expect_equal(tokens("Call\\.me"), "Call\\.me")
  expect_equal(meanings("Call\\.me"), "The exact text “Call.me”")
  expect_equal(meanings("-"), "The character “-”")
  # A quantified literal is split off from the run before it.
  expect_equal(meanings("ab\\-{2}"),
               c("The exact text \u201cab\u201d", "Exactly 2 characters \u201c-\u201d"))
})

test_that("syntax outside the generated subset is flagged, not guessed", {
  expect_match(meanings("\\w"), "^Not explained")
  expect_match(meanings("[abc]")[1], "^Not explained")
})

# Every pattern the package can produce for a spread of inputs and options must
# be fully explained. If the package starts emitting new syntax, this fails
# before the demo starts showing "Not explained" to users.
test_that("every generated pattern is fully explained", {
  cases <- list(
    list("Call 555-1234 today", "555-1234"),
    list("order #A1099 shipped", "A1099"),
    list("John:42, Jane:37", c("42", "37")),
    list("Margaret Thatcher was born in 1925.", "Margaret Thatcher 1925"),
    list(c("Tony Blair was born in 1953. ", "John Major was born in 1943. "),
         c("Tony Blair 1953", "John Major 1943")),
    list("a.b*c (x) [y] {z} ^$ | \\ ? +", "a.b*c (x) [y] {z} ^$ | \\ ? +"),
    list("ids: ab-12, XYZ-3", c("ab-12", "XYZ-3")),
    list("café au lait", "café"),
    list("x -- y", "--")
  )
  opts <- expand.grid(generalize = c("exact", "class", "compact", "loose"),
                      flavor = c("pcre", "posix"),
                      fill = c("skip", "literal", "class"),
                      case_sensitive = c(TRUE, FALSE),
                      capture = c(TRUE, FALSE),
                      stringsAsFactors = FALSE)
  for (cs in cases) {
    for (k in seq_len(nrow(opts))) {
      o <- opts[k, ]
      p <- suppressWarnings(InveRseRegex::regexify(
        cs[[1]], cs[[2]], generalize = o$generalize, flavor = o$flavor,
        fill = o$fill, case_sensitive = o$case_sensitive, capture = o$capture))
      p <- as.character(p)
      rows <- demo_explain(p)
      unexplained <- grepl("^Not explained|not explained further",
                           vapply(rows, `[[`, character(1), "meaning"))
      expect_false(any(unexplained),
                   info = paste("pattern:", p))
      # The tokens, joined, reproduce the pattern exactly.
      expect_equal(paste(vapply(rows, `[[`, character(1), "token"), collapse = ""), p,
                   info = paste("pattern:", p))
    }
  }
})
