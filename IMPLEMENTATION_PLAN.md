# InveRseRegex — Master Implementation Plan

A lightweight R package that infers a regular expression from an example
string plus the value(s) you want to extract from it. You hand it text and
the substrings you care about; it hands you back a verified regex you can
drop into `stringr`, `grepl()`, `regmatches()`, etc.

This document is the single source of truth for scope, decisions, and
progress. It is updated at **every stage commit** so the history of *what*
was built and *why* is captured alongside the code.

---

## 1. Locked design decisions

These were agreed with the requester before any code was written.

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Primary behaviour | **Generalize from example** | The most useful mode: give a string + the substring you want, get a pattern that describes it. |
| Default regex flavor | **PCRE / stringr-compatible** | Uses `\d`, `\b`, etc. Works with `stringr`/`str_*` and base R when `perl = TRUE`. |
| Default generalization | **Compact** | Merges runs of a class into `{n}` quantifiers (`"123"` → `\d{3}`). Reads naturally; stricter/looser still available via an argument. |
| Runtime dependencies | **None (base R only)** | Keeps the package genuinely lightweight. Verification uses base `gregexpr(perl = TRUE)`. `stringr`/`testthat` are `Suggests` only. |

## 2. Public API

```r
regexify(text, want,
         generalize = c("compact", "class", "loose", "exact"),
         flavor     = c("pcre", "posix"),
         capture    = TRUE,
         anchor     = c("auto", "none", "line", "word"),
         verify     = TRUE)

as_r_literal(x)          # paste-ready R source form of a pattern
print(<regexify>)        # shows raw pattern + R-literal + match summary
```

- `want` may be a single substring **or several**; the inferred template must
  cover all of them. If their structures differ, we fall back to an honest
  alternation of the per-example patterns rather than pretending to a single
  template.

### Generalization levels
| Level | `"555-1234"` becomes | Notes |
|-------|----------------------|-------|
| `exact` | `555\-1234` | Literal, metacharacters escaped. Baseline. |
| `class` | `\d\d\d-\d\d\d\d` | One token per character, no quantifier merging. |
| `compact` (default) | `\d{3}-\d{4}` | Runs merged into `{n}` (or `{min,max}` across examples). |
| `loose` | `\d+-\d+` | Runs merged into `+`. Flexible, higher over-match risk. |

## 3. "Gotchas" being actively managed

1. **Non-uniqueness of regex synthesis** — infinitely many regexes match any
   example. Mitigated by the `generalize` knob + always verifying the result.
2. **R's two regex engines** — base default (POSIX/TRE) vs PCRE vs ICU
   (`stringr`). `\d`/`\b` need `perl = TRUE` in base. We target PCRE by default
   and offer a `posix` translation.
3. **Double-backslash display trap** — a returned pattern's real content is
   `\d`; it only looks like `\\d` in R source. `as_r_literal()` + the print
   method defuse this.
4. **Over-generalization** — `verify` runs the pattern against `text` and warns
   when it matches more than the requested value(s).
5. **Anchoring** — `auto` adds `^…$` for whole-string matches and `\b` at
   word boundaries otherwise, to reduce accidental over-matching.

## 4. Build stages (each ends in a commit)

- [x] **S1 — Skeleton**: DESCRIPTION, LICENSE, .Rbuildignore, .gitignore, this plan.
- [ ] **S2 — Tokenizer**: `tokenize()` + character-class inference + unit tests.
- [ ] **S3 — Core `regexify`**: compact/PCRE path, capture, escaping + tests.
- [ ] **S4 — Anchoring, verify, multi-example**: `auto` anchors, verification
      + over-match warnings, vector `want` + tests.
- [ ] **S5 — Display helpers**: `as_r_literal()`, `print.regexify` + tests.
- [ ] **S6 — Other levels & POSIX flavor**: `class`/`loose`/`exact`, `posix`
      translation + tests.
- [ ] **S7 — Docs & infra**: roxygen docs/NAMESPACE, README, GitHub Actions
      `R-CMD-check`, SessionStart hook for web sessions.
- [ ] **S8 — Green check**: full `R CMD check` clean; final polish.

## 5. Testing expectations (this cloud sandbox)

- CRAN is blocked through the proxy (403), so dependencies are installed via
  **apt** (`r-base-core`, `r-cran-testthat`, `r-cran-stringr`,
  `r-cran-roxygen2`, `r-cran-devtools`), not `install.packages()`/`pak`.
- Every stage runs: `roxygen2::roxygenise()` → `testthat` suite →
  (from S8) `R CMD check`.
- A `SessionStart` hook re-provisions R automatically in future web sessions.

## 6. Progress log

Newest entries at the top. Each entry records the stage, the commit, and any
deviation or judgement call made along the way.

<!-- LOG:START -->
- **S1 — Skeleton.** Added `DESCRIPTION` (base-R-only, `stringr`/`testthat` as
  Suggests), MIT `LICENSE`/`LICENSE.md`, `.Rbuildignore`, `.gitignore`, and this
  plan. Judgement calls: (a) package name kept as `InveRseRegex` to match the
  repo — it is a valid R name; (b) placeholder author/email used until the
  requester supplies real metadata; (c) `IMPLEMENTATION_PLAN.md` is
  build-ignored so it does not ship inside the installed package. Toolchain
  provisioning via apt underway in parallel.
<!-- LOG:END -->
