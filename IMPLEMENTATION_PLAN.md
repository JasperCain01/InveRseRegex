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
- [x] **S2 — Tokenizer**: `tokenize()` + character-class inference + unit tests.
- [x] **S3 — Core `regexify`**: all levels + PCRE/POSIX, capture, escaping + tests.
- [x] **S4 — Anchoring, verify, multi-example**: `auto` anchors, verification
      + over-match warnings, vector `want` + tests.
- [x] **S5 — Display helpers**: `as_r_literal()`, `print.regexify` + tests.
- [x] **S6 — POSIX hardening**: end-to-end tests against base R's default engine
      (levels/`posix` translation already delivered in S3).
- [x] **S7 — Docs & infra**: roxygen docs/NAMESPACE, README, GitHub Actions
      `R-CMD-check`, SessionStart hook for web sessions.
- [x] **S8 — Green check**: full `R CMD check` clean; final polish.

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
- **S8 — Green check.** `R CMD check` passes with **0 errors, 0 warnings**. To
  get there: replaced `utils::head` with a tiny internal `take()` so the package
  needs *no* dependency (not even `utils`); made all R/test sources pure ASCII
  (em-dashes -> `--`, the non-ASCII test literal -> `"é"`); and generated
  the `en_US.UTF-8` locale in the sandbox to clear a locale WARNING. One NOTE
  remains -- "unable to verify current time" -- which is purely the sandbox
  proxy blocking the time server and is not a package issue (CRAN ignores it).
  Full suite green.
- **S7 — Docs & infra.** Added `README.md` (with real, captured example output),
  a cross-platform GitHub Actions `R-CMD-check` workflow, and a `SessionStart`
  hook (`.claude/hooks/session-start.sh` + `.claude/settings.json`) that
  provisions R via apt in web sessions. Judgement calls: (a) the hook is
  idempotent and remote-only, installing from apt because CRAN is blocked in the
  sandbox; (b) it runs **synchronously** for now (guarantees R is ready before
  the agent runs, at the cost of slower session start) — worth switching to
  async given the devtools install time; (c) README documents ASCII-only classes
  and the ambiguity caveat so expectations are set. Hook fast-path and a sample
  test file validated.
- **S6 — POSIX hardening.** Since all generalization levels and the POSIX
  translation shipped in S3, this stage validated the POSIX flavor end-to-end.
  Empirically confirmed base R's default TRE engine (`perl = FALSE`) accepts
  everything the POSIX flavor emits — `\b`, `[[:space:]]`, `{m,n}` ranges, and
  even non-capturing `(?:...)` groups — so no code change was needed. Added 5
  tests that run generated POSIX patterns through `grepl(perl = FALSE)` against
  the real engine. 71 total pass.
- **S5 — Display helpers.** `as_r_literal()` (built on `encodeString`) returns
  the paste-ready, double-escaped R source form of a pattern, defusing the
  `\d` vs `"\\d"` confusion. `print.regexify` shows the raw pattern, its R
  source form, and a verification summary (matches / unmatched / also-matched).
  Confirmed a `regexify` result is still an ordinary character that base regex
  functions accept directly. 5 new tests; 66 total pass.
- **S4 — Anchoring, verification, multi-value.** `auto` anchoring now inspects
  how the value sits in the text: whole-text match → `^…$`; otherwise a `\b` is
  added at an edge only when it is both useful and *consistent with the observed
  context*, so an auto-anchor never breaks the match it describes. Verification
  runs the pattern back over the text and warns on (a) requested values it fails
  to match and (b) extra substrings it matches (possible over-generalisation);
  matches are stored for the print method. Multi-value `want` aligns identical
  class-sequences into a merged template with `{min,max}` ranges, and falls back
  to an honest alternation when structures differ. Judgement calls: (a) aligned
  merging requires "other" runs to share the exact literal, so `1-2`/`1/2` do
  not merge; (b) anchor decisions use each value's first occurrence but must
  hold for all values. 24 new tests; 61 total pass.
- **S3 — Core generator.** Added `R/regexify.R` with the per-token renderer and
  the public `regexify()`, plus the package doc and roxygen-generated
  `NAMESPACE`/`man/`. **Deviation from the plan:** all four generalization
  levels *and* the POSIX flavor were implemented now rather than being deferred
  to S6 — they share one small `render_token()`/`base_fragment()` path, so
  splitting them would have been artificial. S6 is therefore reduced to POSIX
  edge-case hardening. Judgement calls: (a) quantifier generalization (`{n}`,
  `+`) applies only to class tokens; repeated literals use `{n}` and never `+`
  (`\-+` would surprise); (b) the return value is a classed character
  (`"regexify"`) so it prints nicely yet still works directly as a pattern;
  (c) multi-`want` and `auto` anchoring are explicitly guarded/stubbed pending
  S4. 12 core tests pass (24 total).
- **S2 — Tokenizer.** Added `R/tokenize.R` (four coarse classes: digit / alpha /
  space / other) and `R/utils.R` (regex-literal escaping). Judgement calls:
  (a) letters of both cases fold into one `alpha` class rendered `[A-Za-z]` —
  case-preserving would over-fit; (b) classification uses explicit ASCII ranges
  rather than locale-sensitive POSIX classes, for reproducibility, which means
  non-ASCII letters fall into `other` and are emitted as escaped literals;
  (c) runs of `other` only merge when the identical character repeats.
  Toolchain: installed R 4.3.3 + dev packages via **apt** (CRAN blocked). 8
  tokenizer tests pass.
- **S1 — Skeleton.** Added `DESCRIPTION` (base-R-only, `stringr`/`testthat` as
  Suggests), MIT `LICENSE`/`LICENSE.md`, `.Rbuildignore`, `.gitignore`, and this
  plan. Judgement calls: (a) package name kept as `InveRseRegex` to match the
  repo — it is a valid R name; (b) placeholder author/email used until the
  requester supplies real metadata; (c) `IMPLEMENTATION_PLAN.md` is
  build-ignored so it does not ship inside the installed package. Toolchain
  provisioning via apt underway in parallel.
<!-- LOG:END -->
