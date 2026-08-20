ttestisClass <- R6::R6Class(
    "ttestisClass",
    inherit = ttestisBase,
    private = list(
        .tr = function(text) {
            # jamovi never forwards the options protobuf (incl. `.lang`) to addon
            # analyses (only to the host), so self$options$translate() -- what
            # jmvcore::.() uses -- always sees an empty language here. The host's
            # Options object does receive it, so borrow that instead.
            lang <- tryCatch(
                self$parent$options$.__enclos_env__$private$.lang,
                error = function(e) ""
            )
            if (is.null(lang) || lang == "")
                return(jmvcore::.(text))
            jmvcore:::createTranslator("jmvplus", lang)$translate(text)
        },
        .init = function() {
            if (! self$parent$options$eqv)
                return()

            assum <- self$parent$results$assum
            if (! is.null(assum$get("fisher")))
                return()

            # A second row appended directly onto jmv's own Homogeneity table
            # (assum$eqv, rows: (vars)) breaks jamovi's client-side table
            # redraw once `vars` shrinks: the client silently drops rows/
            # columns the compiled jmv schema doesn't declare on some update
            # paths, though a full remount (e.g. toggling the "Homogeneity
            # test" checkbox) repaints correctly. A brand-new table has no
            # such stale schema to conflict with, so it's added as a sibling
            # of eqv instead of merged into it.
            table <- jmvcore::Table$new(
                options = self$parent$options,
                name = "fisher",
                title = private$.tr("Fisher's F-test"),
                rows = 0,
                clearWith = list("group", "miss"))
            table$addColumn(name = "name", title = "", type = "text")
            table$addColumn(name = "f", title = "F", type = "number")
            table$addColumn(name = "df", title = "df", type = "number")
            table$addColumn(name = "df2", title = "df2", type = "number")
            table$addColumn(name = "p", title = "p", type = "number", format = "zto,pvalue")

            assum$add(table)
        },
        .run = function() {
            if (! self$parent$options$eqv)
                return()

            table <- self$parent$results$assum$get("fisher")
            if (is.null(table))
                return()

            vars <- self$parent$options$vars
            group <- self$parent$options$group
            table$deleteRows()
            if (length(vars) == 0 || is.null(group) || ! (group %in% names(self$data)))
                return()

            listwise <- self$parent$options$miss == "listwise"

            for (var in vars) {
                groups <- private$.groupedValues(var, group, if (listwise) vars else NULL)
                fisher <- private$.fisherTest(groups)
                table$addRow(rowKey = var, values = list(
                    name = var, f = fisher$f, df = fisher$df1, df2 = fisher$df2, p = fisher$p
                ))
            }
        },
        .groupedValues = function(var, group, listwiseVars) {
            column <- jmvcore::toNumeric(self$data[[var]])
            grouping <- self$data[[group]]
            keep <- ! is.na(column) & ! is.na(grouping)
            for (other in listwiseVars)
                keep <- keep & ! is.na(jmvcore::toNumeric(self$data[[other]]))

            column <- column[keep]
            grouping <- droplevels(grouping[keep])
            levels <- levels(grouping)
            if (length(levels) != 2)
                return(NULL)

            x <- column[grouping == levels[1]]
            y <- column[grouping == levels[2]]
            if (length(x) < 2 || length(y) < 2)
                return(NULL)

            list(x = x, y = y)
        },
        .fisherTest = function(groups) {
            failure <- list(f = NaN, df1 = NaN, df2 = NaN, p = NaN)
            if (is.null(groups) || var(groups$x) == 0 || var(groups$y) == 0)
                return(failure)

            test <- stats::var.test(groups$x, groups$y)
            list(
                f = unname(test$statistic),
                df1 = unname(test$parameter["num df"]),
                df2 = unname(test$parameter["denom df"]),
                p = test$p.value
            )
        }
    )
)
