# Browser demo

A one-page demo of InveRseRegex that runs entirely in the browser: R itself is
compiled to WebAssembly by [webR](https://docs.r-wasm.org/webr/latest/), and the
page calls `regexify()` as you type. It is deployed to GitHub Pages by
`.github/workflows/demo.yml` on every push to `main`.

## Layout

| Path | What it is |
|------|------------|
| `site/index.html`, `site/style.css` | The page. |
| `site/app.js` | Page behaviour only: reading inputs, drawing results, the URL state. No regex work happens in JavaScript. |
| `site/demo.R` | The R side. `demo_run_json()` calls `regexify()` and returns everything the page draws as one JSON string: the pattern, match positions, explanation, level comparison and snippets. |
| `scripts/build.sh` | Assembles `_site/` from the page, a copy of the webR runtime and a binary build of the package. |
| `tests/testthat/` | testthat tests for `demo.R`. |
| `tests/webr-suite.mjs` | Runs the package's tests and the `demo.R` tests inside webR, to check that the browser's R behaves like native R. |
| `tests/e2e.mjs` | Loads the built site in headless Chromium and checks the page end to end. |

## Working on it locally

You need R (with testthat and the package's own dependencies) and Node 22 or later.

```sh
cd demo
npm install                 # webR and Playwright, pinned in package.json
Rscript -e 'testthat::test_dir("tests/testthat")'   # glue tests, native R
npm run build               # writes _site/
npm run serve               # http://127.0.0.1:8000/
npm run test:webr           # package and glue tests inside webR
npx playwright install chromium   # once
npm run test:e2e            # browser tests
```

The build installs the package from the working tree, so changes under `R/`
show up in the demo after the next `npm run build`.

## Things worth knowing

- The package binary is built by native R (`R CMD INSTALL --build`) and loaded
  into webR as-is. That only works because InveRseRegex is pure R. If it ever
  gains compiled code, the build has to move to the r-wasm `rwasm` tooling.
- CI builds the package under the same R version webR runs (pinned in
  `.github/workflows/demo.yml`). When upgrading webR in `package.json`, move
  that pin to match; `npm run test:webr` fails if the package was built under
  a newer R than webR's.
- The explanation table only understands the regex syntax the package
  generates. `tests/testthat/test-explain.R` runs every option combination over
  a set of inputs and fails if any piece comes back "not explained", so a
  change to the package's output will show up there first.
- Match positions are converted from R's character counts to the UTF-16 units
  JavaScript uses. Without that, highlights drift after any emoji.
- GitHub Pages cannot send the headers webR's fastest channel needs, so a
  runaway match cannot be interrupted; the page restarts R after 15 seconds instead.
