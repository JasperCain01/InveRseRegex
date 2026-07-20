# This file is the entry point testthat uses when running `R CMD check` or
# `testthat::test_check()`. It simply loads the package and runs every test
# under tests/testthat/.
library(testthat)
library(InveRseRegex)

test_check("InveRseRegex")
