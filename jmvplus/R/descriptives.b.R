descriptivesClass <- R6::R6Class(
    "descriptivesClass",
    inherit = descriptivesBase,
    private = list(
        .init = function() {
            if (! self$parent$options$sd)
                return()

            # The built-in results table is dynamic, so append CV after it has
            # created the selected descriptives structure.
            if (self$parent$options$desc == "columns")
                private$.initColumns()
            else
                private$.initRows()
        },
        .run = function() {
            if (! self$parent$options$sd)
                return()

            if (self$parent$options$desc == "columns")
                private$.populateColumns()
            else
                private$.populateRows()
        },
        .initColumns = function() {
            table <- self$parent$results$descriptives
            vars <- self$parent$options$vars
            splitBy <- self$parent$options$splitBy
            grid <- private$.splitGrid()

            if (length(splitBy) > 0) {
                for (i in seq_len(nrow(grid))) {
                    suffix <- private$.suffix(grid[i, ])
                    table$addColumn(
                        name = paste0("stat[cv", suffix, "]"), title = "",
                        type = "text", value = "Coefficient of variation (%)",
                        combineBelow = TRUE
                    )
                    for (var in vars) {
                        table$addColumn(
                            name = paste0(var, "[cv", suffix, "]"), title = var,
                            type = "number"
                        )
                    }
                }
            } else {
                table$addColumn(
                    name = "stat[cv]", title = "", type = "text",
                    value = "Coefficient of variation (%)", combineBelow = TRUE
                )
                for (var in vars) {
                    table$addColumn(name = paste0(var, "[cv]"), title = var, type = "number")
                }
            }
        },
        .initRows = function() {
            table <- self$parent$results$descriptivesT
            table$addColumn(name = "cv", title = "CV (%)", type = "number")
        },
        .populateColumns = function() {
            table <- self$parent$results$descriptives
            vars <- self$parent$options$vars
            splitBy <- self$parent$options$splitBy
            grid <- private$.splitGrid()
            values <- list()

            if (length(splitBy) > 0) {
                for (i in seq_len(nrow(grid))) {
                    suffix <- private$.suffix(grid[i, ])
                    for (var in vars)
                        values[[paste0(var, "[cv", suffix, "]")]] <- private$.cv(var, grid[i, ])
                }
            } else {
                for (var in vars)
                    values[[paste0(var, "[cv]")]] <- private$.cv(var)
            }

            table$setRow(rowNo = 1, values = values)
        },
        .populateRows = function() {
            table <- self$parent$results$descriptivesT
            vars <- self$parent$options$vars
            splitBy <- self$parent$options$splitBy
            grid <- private$.splitGrid()
            row <- 1

            for (var in vars) {
                if (length(splitBy) > 0) {
                    for (i in seq_len(nrow(grid))) {
                        table$setRow(rowNo = row, values = list(cv = private$.cv(var, grid[i, ])))
                        row <- row + 1
                    }
                } else {
                    table$setRow(rowNo = row, values = list(cv = private$.cv(var)))
                    row <- row + 1
                }
            }
        },
        .splitGrid = function() {
            splitBy <- self$parent$options$splitBy
            if (length(splitBy) == 0)
                return(NULL)

            levels <- lapply(self$data[splitBy], levels)
            rev(expand.grid(rev(levels)))
        },
        .suffix = function(values) {
            paste0(as.character(values), collapse = "")
        },
        .cv = function(var, group = NULL) {
            column <- jmvcore::toNumeric(self$data[[var]])
            numeric <- jmvcore::canBeNumeric(column)
            weights <- attr(self$data, "jmv-weights")

            if (! numeric)
                return("")

            if (! is.null(group)) {
                splitBy <- self$parent$options$splitBy
                keep <- rep(TRUE, length(column))
                for (i in seq_along(splitBy)) {
                    split <- self$data[[splitBy[i]]]
                    keep <- keep & ! is.na(split) & split == group[i]
                }
                column <- column[keep]
                if (! is.null(weights))
                    weights <- weights[keep]
            }

            if (is.null(weights)) {
                column <- column[! is.na(column)]
                if (length(column) < 2)
                    return(NaN)

                meanValue <- mean(column)
                if (meanValue == 0)
                    return(NaN)
                return(100 * sd(column) / meanValue)
            }

            keep <- ! is.na(column) & ! is.na(weights)
            column <- column[keep]
            weights <- weights[keep]
            if (length(column) < 2 || sum(weights) <= 1)
                return(NaN)

            meanValue <- sum(column * weights) / sum(weights)
            if (meanValue == 0)
                return(NaN)

            100 * sqrt(sum(weights * (column - meanValue)^2) / (sum(weights) - 1)) / meanValue
        }
    )
)
