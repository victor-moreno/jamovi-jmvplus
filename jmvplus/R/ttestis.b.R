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

            table <- self$parent$results$assum$eqv
            if ("fisherF" %in% names(table$.__enclos_env__$private$.columns))
                return()

            # Both a second row (rowKey beyond what the host's own
            # "rows: (vars)" table declares) and a brand-new sibling table
            # were tried here first; both left jamovi's client rendering the
            # new content unreliably (rows vanishing / never appearing) once
            # anything beyond the host's own declared row/column set was
            # involved. Adding columns to jmv's *own* existing rows -- the
            # same pattern the CV addon already uses on Descriptives -- is
            # the one variant that's proven reliable, so Fisher's results
            # live alongside Levene's on the same row instead of as a
            # second row or a separate table.
            superTitle <- private$.tr("Fisher's F-test")
            table$addColumn(name = "fisherF", title = "F", superTitle = superTitle, type = "number")
            table$addColumn(name = "fisherDf", title = "df", superTitle = superTitle, type = "number")
            table$addColumn(name = "fisherDf2", title = "df2", superTitle = superTitle, type = "number")
            table$addColumn(name = "fisherP", title = "p", superTitle = superTitle, type = "number", format = "zto,pvalue")
        },
        .run = function() {
            if (! self$parent$options$eqv)
                return()

            vars <- self$parent$options$vars
            group <- self$parent$options$group
            if (length(vars) == 0)
                return()

            table <- self$parent$results$assum$eqv
            listwise <- self$parent$options$miss == "listwise"

            for (var in vars) {
                groups <- if (is.null(group) || ! (group %in% names(self$data)))
                    NULL
                else
                    private$.groupedValues(var, group, if (listwise) vars else NULL)

                fisher <- private$.fisherTest(groups)
                table$setRow(rowKey = var, values = list(
                    fisherF = fisher$f, fisherDf = fisher$df1, fisherDf2 = fisher$df2, fisherP = fisher$p
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
