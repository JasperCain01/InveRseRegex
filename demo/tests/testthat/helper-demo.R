# Load the demo glue. testthat runs helpers with the working directory set to
# this folder, both natively and inside webR (tests/webr-suite.mjs mirrors the
# repository layout).
source(file.path("..", "..", "site", "demo.R"), local = FALSE)

# Slice `text` by UTF-16 code-unit offsets, the way the browser will. Used to
# check that the offsets demo_spans() reports pick out the right characters.
utf16_slice <- function(text, start, end) {
  raw <- iconv(enc2utf8(text), from = "UTF-8", to = "UTF-16LE", toRaw = TRUE)[[1]]
  if (end <= start) return("")
  piece <- raw[(2 * start + 1):(2 * end)]
  iconv(list(piece), from = "UTF-16LE", to = "UTF-8")
}
