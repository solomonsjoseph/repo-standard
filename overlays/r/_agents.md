
### R package

| Task | Command |
|---|---|
| Lint | `Rscript -e "lintr::lint_package()"` |
| Format | `Rscript -e "styler::style_pkg()"` |
| Test | `Rscript -e "devtools::test()"` |
| Coverage | `Rscript -e "covr::package_coverage()"` |
| Check | `R CMD build . && R CMD check *.tar.gz` |

Document functions with roxygen2 comments and run
`Rscript -e "devtools::document()"` before committing.
