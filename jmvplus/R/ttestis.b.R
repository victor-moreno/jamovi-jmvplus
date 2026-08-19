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
            table$addColumn(name = "test", index = 2, title = "", type = "text")
            private$.setTitle(table, private$.tr("Homogeneity of Variances Test"))
        },
        .run = function() {
            if (! self$parent$options$eqv)
                return()

            vars <- self$parent$options$vars
            group <- self$parent$options$group
            if (length(vars) == 0 || is.null(group) || ! (group %in% names(self$data)))
                return()

            table <- self$parent$results$assum$eqv
            listwise <- self$parent$options$miss == "listwise"

            # The host's own "rows: (vars)" table is rebuilt automatically
            # whenever `vars`/`group` change, but our added Fisher rows are
            # not covered by that mechanism, so on re-run (e.g. the user
            # toggles an option) they'd either be left stale or duplicated.
            # Rebuilding both rows from scratch on every run keeps them in
            # sync and puts each variable's two rows next to each other.
            table$deleteRows()

            for (var in vars) {
                groups <- private$.groupedValues(var, group, if (listwise) vars else NULL)

                levene <- private$.leveneTest(groups)
                table$addRow(rowKey = var, values = list(
                    name = var,
                    test = private$.tr("Levene's"),
                    f = levene$f, df = levene$df1, df2 = levene$df2, p = levene$p
                ))

                fisher <- private$.fisherTest(groups)
                table$addRow(rowKey = paste0(var, "_fisher"), values = list(
                    name = var,
                    test = private$.tr("Fisher's F-test"),
                    f = fisher$f, df = fisher$df1, df2 = fisher$df2, p = fisher$p
                ))
            }
        },
        .setTitle = function(table, title) {
            # jmvcore doesn't expose a public setter for a table's title, so an
            # addon can't officially rename a host table -- reach into the
            # private field directly. We replace it outright (rather than
            # editing jmv's own "(Levene's)" wording) so the new title is
            # correctly translated too. Degrades gracefully (title stays
            # unchanged) if a future jmvcore renames the field.
            tryCatch(
                table$.__enclos_env__$private$.titleValue <- title,
                error = function(e) NULL
            )
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
        .leveneTest = function(groups) {
            failure <- list(f = NaN, df1 = NaN, df2 = NaN, p = NaN)
            if (is.null(groups))
                return(failure)

            absDev <- c(abs(groups$x - mean(groups$x)), abs(groups$y - mean(groups$y)))
            grouping <- factor(rep(c("x", "y"), c(length(groups$x), length(groups$y))))

            result <- tryCatch(summary(stats::aov(absDev ~ grouping))[[1]], error = function(e) NULL)
            if (is.null(result) || anyNA(result[1, c("F value", "Pr(>F)")]))
                return(failure)

            list(f = result[1, "F value"], df1 = result[1, "Df"], df2 = result[2, "Df"], p = result[1, "Pr(>F)"])
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
