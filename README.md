# InveRseRegex

<!-- badges: start -->
[![R-CMD-check](https://github.com/JasperCain01/InveRseRegex/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JasperCain01/InveRseRegex/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

**Regex, backwards.** Instead of writing a pattern to find text, you give
InveRseRegex the text and the value you want, and it hands you back a regular
expression that captures it — verified against your input and ready to drop
into `stringr`, `grepl()`, `regmatches()`, or anything else that takes a
pattern.

```r
regexify("Call 555-1234 today", "555-1234")
#> <regexify>
#>   pattern : \b(\d{3}-\d{4})\b
#>   R source: "\\b(\\d{3}-\\d{4})\\b"
#>   matches : 1 in text (555-1234)
```

## Why

Writing regex is fiddly, and the hardest part is often just remembering the
syntax for "three digits, a dash, four digits". InveRseRegex lets you work from
an example you already have. It is deliberately lightweight: **no runtime
dependencies** (base R only), a single main function, and output you can read.

## Installation

```r
# install.packages("remotes")
remotes::install_github("JasperCain01/InveRseRegex")
```

## Quick start

```r
library(InveRseRegex)

# An identifier: letter then four digits
regexify("order #A1099 shipped", "A1099")
#> <regexify>
#>   pattern : \b([A-Za-z]\d{4})\b
#>   R source: "\\b([A-Za-z]\\d{4})\\b"
#>   matches : 1 in text (A1099)

# Several examples at once -> one template that covers them all
regexify("John:42, Jane:37", c("42", "37"))
#> <regexify>
#>   pattern : \b(\d{2})\b
#>   R source: "\\b(\\d{2})\\b"
#>   matches : 2 in text (42, 37)
```

Use the result directly as a pattern — it is an ordinary character string:

```r
p <- regexify("Call 555-1234 today", "555-1234")

stringr::str_extract("ring 999-0000 now", p)     #> "999-0000"
grepl(p, "888-2222", perl = TRUE)                 #> TRUE
```

### The double-backslash trap

What you see at the console (`\d`) is the pattern's real content, but to write
that same string in an R *script* you need `"\\d"`. `as_r_literal()` gives you
the paste-ready form:

```r
as_r_literal(p)
#> "\\b(\\d{3}-\\d{4})\\b"
```

## How general should it be?

The `generalize` argument controls how much the example is abstracted. For the
value `"555-1234"`:

| `generalize` | Result | Meaning |
|--------------|--------|---------|
| `"exact"` | `555-1234` | The literal value (metacharacters escaped). |
| `"class"` | `\d\d\d-\d\d\d\d` | One character class per character. |
| `"compact"` *(default)* | `\d{3}-\d{4}` | Runs collapsed into `{n}` counts. |
| `"loose"` | `\d+-\d+` | Runs collapsed into `+` (most flexible). |

## Flavors

- `flavor = "pcre"` *(default)* — uses `\d`, `\s`, `\b`. Works with `stringr`
  and with base R when you pass `perl = TRUE`.
- `flavor = "posix"` — uses `[0-9]`, `[[:space:]]`. Works with base R's default
  engine (`grepl()`, `sub()`, …) without `perl = TRUE`.

## Anchoring and verification

- `anchor = "auto"` *(default)* anchors the whole line (`^…$`) when your value
  is the entire text, otherwise adds word boundaries (`\b`) where they are
  consistent with the surrounding text. `"none"`, `"line"` and `"word"` force a
  choice.
- `verify = TRUE` *(default)* runs the generated pattern back over your text and
  **warns** if it fails to match a requested value or if it matches extra
  substrings (a hint that you may want a stricter level or anchoring).

## Limitations / good to know

Inferring a regex from an example is inherently ambiguous — many patterns match
any given string. InveRseRegex makes a sensible, verified guess; treat it as a
strong starting point you can tweak, not an oracle.

- Character classes are **ASCII** (`[A-Za-z]`, `\d`). Non-ASCII characters are
  matched as escaped literals rather than generalised.
- Letters are not case-split: `Abc` generalises to `[A-Za-z]{3}`, not
  `[A-Z][a-z]{2}`.
- Multiple `want` values are merged into one template when they share a
  structure, and fall back to an alternation when they do not.

## License

MIT © InveRseRegex Authors
