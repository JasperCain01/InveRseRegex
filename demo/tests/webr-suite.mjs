// Run the package's test suite AND the demo glue tests inside webR (R compiled
// to WebAssembly), under Node. This is the check that the browser's copy of R
// behaves like native R: same PCRE / TRE regex engines, same results.
//
// Uses the package binary from demo/_site/pkg (run `npm run build` first) and
// installs testthat from the webR package repository (repo.r-wasm.org, or the
// URL in the WEBR_REPO environment variable, e.g. a local mirror when working
// behind a proxy that webR's downloader cannot use).
// Exits non-zero if any test fails or errors.
import { WebR } from 'webr';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEMO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ROOT = path.resolve(DEMO, '..');
const PKG = path.join(DEMO, '_site', 'pkg', 'InveRseRegex.tar.gz');
if (!fs.existsSync(PKG)) {
  console.error(`Package binary not found at ${PKG}; run 'npm run build' first.`);
  process.exit(1);
}

const webR = new WebR({ interactive: false });
await webR.init();

// Copy a host directory into webR's virtual filesystem.
async function copyDir(from, to) {
  await webR.FS.mkdir(to);
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const src = path.join(from, entry.name);
    const dst = `${to}/${entry.name}`;
    if (entry.isDirectory()) await copyDir(src, dst);
    else await webR.FS.writeFile(dst, fs.readFileSync(src));
  }
}

// Mirror the repository layout the tests expect.
await webR.FS.mkdir('/repo');
await webR.FS.mkdir('/repo/demo');
await webR.FS.mkdir('/repo/demo/tests');
await copyDir(path.join(ROOT, 'tests'), '/repo/tests');
await copyDir(path.join(DEMO, 'site'), '/repo/demo/site');
await copyDir(path.join(DEMO, 'tests', 'testthat'), '/repo/demo/tests/testthat');
await webR.FS.writeFile('/repo/pkg.tar.gz', fs.readFileSync(PKG));

console.log('Installing testthat into webR...');
const repos = [process.env.WEBR_REPO || 'https://repo.r-wasm.org/'];
await webR.installPackages(['testthat'], { quiet: true, repos });

const shelter = await new webR.Shelter();
const { output, result } = await shelter.captureR(`
  cat(R.version.string, "| PCRE", as.character(extSoftVersion()["PCRE"]),
      "| locale", Sys.getlocale("LC_CTYPE"), "\\n")
  lib <- "/repo/lib"
  dir.create(lib)
  untar("/repo/pkg.tar.gz", exdir = lib, tar = "internal")
  .libPaths(c(lib, .libPaths()))
  library(testthat)
  library(InveRseRegex)
  summarise <- function(res) {
    df <- as.data.frame(res)
    c(tests = nrow(df), failed = sum(df$failed > 0), errors = sum(df$error))
  }
  cat("\\n== Package tests ==\\n")
  pkg <- test_dir("/repo/tests/testthat", package = "InveRseRegex",
                  load_package = "installed", reporter = "summary",
                  stop_on_failure = FALSE)
  cat("\\n== Demo glue tests ==\\n")
  demo <- test_dir("/repo/demo/tests/testthat", reporter = "summary",
                   stop_on_failure = FALSE)
  totals <- summarise(pkg) + summarise(demo)
  cat("\\nTotal:", totals[["tests"]], "tests,", totals[["failed"]], "failed,",
      totals[["errors"]], "errored\\n")
  totals[["failed"]] + totals[["errors"]]
`);
for (const line of output) {
  if (line.type === 'stdout' || line.type === 'stderr') console.log(line.data);
}
const bad = await result.toNumber();
await shelter.purge();
webR.close();
process.exit(bad === 0 ? 0 : 1);
