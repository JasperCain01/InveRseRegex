# What the tests protect

The suite has 57 `test_that()` blocks in `tests/testthat/`. Run it with `devtools::test()`; it also runs under `R CMD check` in CI.

Most tests pin the exact pattern string `regexify()` returns. That's deliberate: the pattern *is* the product, and users paste it straight into their own code, so a silent change in what comes back is the most damaging failure the package can have. The cost is that a deliberate change of house style (for example `\d` → `[0-9]`) will fail a large share of the suite at once. When that happens, update the expected strings; don't weaken the assertions.

Severity describes what goes wrong for a user if the guarded behaviour breaks:

- **Critical**: the package can't be used.
- **High**: a pattern looks right but matches the wrong things.
- **Medium**: a feature visibly misbehaves.
- **Low**: a message or display is wrong.

## `test-tokenize.R`: splitting a value into character-class runs

Every pattern is built from these runs, so a tokeniser fault reaches every output.

| Test | Purpose | Severity |
|---|---|---|
| char_class recognises the four coarse classes | Digits, letters, whitespace and everything else are classified correctly, including tab as whitespace and `.` as "other". | High |
| a non-ASCII letter is treated as 'other', not 'alpha' | Pins the deliberate ASCII-only scope: `é` is a literal, not `[a-z]`. If this changes, accented text would start being generalised. | Medium |
| tokenize merges runs of the same class | Adjacent characters of one class become one run with a count, and a separator between two same-class runs keeps them apart (`555-1234` → digit 3, other 1, digit 4). This is what makes `\d{3}` rather than `\d\d\d` possible. | High |
| case-aware tokenize splits letter runs by case | `AbcDef` becomes upper/lower/upper/lower, which is what lets the default output tell capitals from lower case. | High |
| case-insensitive tokenize folds letters into one alpha run | `case_sensitive = FALSE` restores the older single-letter-class behaviour. | Medium |
| tokenize splits identical vs differing punctuation | `--` is one run of two; `->` is two runs. Prevents a pattern treating different punctuation as interchangeable. | High |
| tokenize handles single-character and empty strings | The boundary inputs don't error and give the obvious result. | Medium |

## `test-regexify-core.R`: turning a single value into a pattern

| Test | Purpose | Severity |
|---|---|---|
| compact is the default and merges runs into {n} | The default level produces `(\d{3}-\d{4})` for a phone number, the canonical README example. | High |
| capture can be switched off | `capture = FALSE` omits the group. | Medium |
| class level emits one atom per character | `class` gives `[a-z][a-z]\d\d` with no quantifiers. | High |
| loose level uses + quantifiers for class tokens | `loose` gives `[a-z]+\d+`. | High |
| exact level escapes the literal value | `exact` escapes metacharacters, so `a.b+c` matches only itself. | High |
| metacharacters in the value are escaped at the default compact level | A value containing `+`, `(` or `.` is escaped at `compact`, and `3.50` doesn't match `3x50`. Added because escaping was only tested at `exact`, and most users never change the level. | High |
| posix flavor swaps in POSIX atoms | `flavor = "posix"` emits `[0-9]` and `[[:space:]]`. | High |
| other-run of a repeated literal uses {n}, not + | `--` becomes `-{2}`, never `-+`, which would surprisingly match any number of dashes. | High |
| explicit anchors wrap correctly outside the capture group | `anchor = "line"` and `"word"` put `^…$` / `\b…\b` outside the group, so the captured value has no anchor in it. | Medium |
| input validation rejects bad arguments | Incompatible vector lengths, empty input and an unknown level all fail with an error rather than an odd pattern. | Medium |

## `test-case.R`: upper/lower-case awareness

| Test | Purpose | Severity |
|---|---|---|
| case-aware default renders a capitalised word as [A-Z][a-z]{n} | `Abc` and `Margaret` keep their leading capital in the pattern. | High |
| an all-caps run renders as [A-Z]{n} | `NASA` → `[A-Z]{4}`. | High |
| case_sensitive = FALSE folds to [A-Za-z] (legacy behaviour) | The opt-out still produces the case-insensitive class. | Medium |
| case-aware merging across examples keeps the case structure | Several title-case names merge into `[A-Z][a-z]{3,7}`, not a mixed-case class. | High |
| upper and lower do not merge across examples | `AB` and `ab` give an alternation rather than one pattern that would also match `aB`. Guards against over-generalisation. | High |
| loose applies + to every run, including the leading capital | Documents that `loose` is uniform: `[A-Z]+[a-z]+`. | Medium |

## `test-anchor-verify.R`: automatic anchoring and the verification safety net

| Test | Purpose | Severity |
|---|---|---|
| auto anchors the whole line when want IS the entire text | `regexify("42", "42")` gives `^(\d{2})$`. | Medium |
| auto adds word boundaries at non-word edges | A value surrounded by spaces gets `\b…\b`, so it won't match inside a longer number. | High |
| auto omits a boundary where the value is glued to a word char | `1234` inside `a1234b` gets no `\b`, which would otherwise make the pattern miss its own example. | High |
| verify is silent when the pattern matches exactly | No false alarm on a correct result. | Medium |
| verify warns when a requested value is not matched | The safety net fires when the pattern misses what was asked for. | High |
| verify warns when the pattern over-matches | The safety net fires when the pattern also matches unrequested text. | High |

## `test-multi-value.R`: several wanted values from one text

| Test | Purpose | Severity |
|---|---|---|
| aligned values with equal lengths share one template | `42` and `37` → `\d{2}`. | High |
| aligned values with differing lengths yield a range quantifier | `42` and `1234` → `\d{2,4}`. | High |
| aligned 'other' runs must share the literal character | `1-2` and `1/2` give an alternation, not a pattern that accepts either separator anywhere. | High |
| structurally different values fall back to an alternation | `42` and `abc` → `(?:\d{2}\|[a-z]{3})`. | High |
| alternation is wrapped in a single capture group when capturing | The alternation is one group, so callers get one capture per match. | Medium |
| multi-value with auto anchor and verify matches all values | End to end, with anchoring and verification on: both values are matched, each match is listed once, and nothing is reported as an extra. | High |
| values from one text are not counted twice or as extras of each other | No warning, and `print()` shows `2 in text (42, 37)`. Guards a bug where each match was counted once per wanted value and each value was flagged as an "extra" of the other. | Medium |
| an unwanted match in a shared text is still reported | The fix above must not hide genuine over-matching: a third number in the same text still triggers the warning and is listed in `extras`. | High |

## `test-align.R`: values that skip part of the text

| Test | Purpose | Severity |
|---|---|---|
| align returns a single segment for a contiguous want | The simple case stays simple. | Medium |
| align splits a non-contiguous want into segments and fillers | `Margaret Thatcher 1925` against the full sentence yields two segments and one filler, with the right filler text. | High |
| align drops leading filler before the first segment | Text before the first wanted part isn't emitted as a filler. | Medium |
| headline: non-contiguous want yields captured segments + skip | The README's showcase example, checked against the exact output and against the source text. If this breaks, the README is wrong. | High |
| fill = 'literal' keeps the excluded text | The `literal` option keeps `was born in`. | Medium |
| fill = 'class' generalises the excluded text | The `class` option generalises it. | Medium |
| a want that is not a subsequence warns and falls back | When the wanted text can't be found in order, alignment reports failure and the user gets a warning rather than a misleading pattern. | High |

## `test-multi-example.R`: learning one pattern from several (text, want) pairs

| Test | Purpose | Severity |
|---|---|---|
| parallel text/want vectors learn a shared template | Three biographies give one pattern with range quantifiers that verifies against all three. | High |
| the learned pattern extracts segments from every example | The capture groups pull the right pieces out of each example. | High |
| a single want recycled across several texts still verifies | Length-one `want` recycles. | Medium |
| structurally different examples fall back to an alternation | Unrelated example shapes give an alternation rather than an error. | Medium |
| extras are judged against the wanted values for the same text | A value wanted from one text counts as an extra when it is matched in a different text where it was not asked for. | Medium |

## `test-posix.R`: the POSIX flavour under R's default engine

These tests run patterns through `grepl(perl = FALSE)` (the TRE engine) rather than comparing strings. That's the only way to catch a pattern that looks right but that the engine rejects or reads differently.

| Test | Purpose | Severity |
|---|---|---|
| posix atoms and compact quantifiers match under the default engine | Basic POSIX output works in TRE. | High |
| posix word-boundary auto anchor works under the default engine | `\b` from auto-anchoring is accepted by TRE. | High |
| posix alternation (non-capturing group) works under the default engine | `(?:…)` is where PCRE and TRE syntax most often disagree. | High |
| posix verification stays silent on a good match | No false alarm for a correct POSIX pattern. | Medium |
| verification runs a posix pattern through the default engine, not PCRE | Uses a pattern (`\<…\>`) that only matches under TRE, and shows posix verification passes while PCRE verification warns. Without this, a POSIX pattern could be reported as verified when it fails in the user's code. | High |

## `test-display.R`: output for humans

| Test | Purpose | Severity |
|---|---|---|
| as_r_literal doubles backslashes, adds quotes, and is vectorised | The R-source form users copy into scripts is correctly escaped. | Medium |
| print shows the pattern, source form and match summary | Smoke test of the print method. | Low |
| a regexify result is still usable directly as a pattern | The returned object's class and attributes don't stop `grepl()` and `regmatches()` from accepting it. If this broke, the README's usage would fail outright. | Critical |
