scatClass <- R6::R6Class(
    "scatClass",
    inherit = scatBase,
    private = list(
        .init = function() {
            parentPrivate <- self$parent$.__enclos_env__$private
            original <- parentPrivate$.scatterPlot

            # scatr owns the Image result, so wrap its renderer to add the
            # prediction ribbon without replacing the built-in plot.
            unlockBinding(".scatterPlot", parentPrivate)
            parentPrivate$.scatterPlot <- function(image, ggtheme, theme, ...) {
                plot <- original(image, ggtheme, theme, ...)
                interval <- private$.predictionInterval(image$state)
                if (is.null(interval))
                    return(plot)

                ribbon <- if ("group" %in% names(interval)) {
                    ggplot2::geom_ribbon(
                        data = interval,
                        mapping = ggplot2::aes(x = x, ymin = lwr, ymax = upr, group = group),
                        inherit.aes = FALSE,
                        fill = "#F48FB1",
                        alpha = 0.30,
                        colour = NA
                    )
                } else {
                    ggplot2::geom_ribbon(
                        data = interval,
                        mapping = ggplot2::aes(x = x, ymin = lwr, ymax = upr),
                        inherit.aes = FALSE,
                        fill = "#F48FB1",
                        alpha = 0.30,
                        colour = NA
                    )
                }

                plot$layers <- c(list(ribbon), plot$layers)
                plot
            }
            lockBinding(".scatterPlot", parentPrivate)
        },
        .run = function() {
        },
        .predictionInterval = function(data) {
            options <- self$parent$options
            if (! options$regLine || ! options$lineSE || options$lineMethod != "lm")
                return(NULL)

            if ("group" %in% names(data)) {
                intervals <- lapply(split(data, data$group, drop = TRUE), private$.intervalForData)
                intervals <- Filter(Negate(is.null), intervals)
                if (length(intervals) == 0)
                    return(NULL)
                return(do.call(rbind, intervals))
            }

            private$.intervalForData(data)
        },
        .intervalForData = function(data) {
            group <- if ("group" %in% names(data)) as.character(data$group[1]) else NULL
            data <- data[stats::complete.cases(data[c("x", "y")]), c("x", "y"), drop = FALSE]
            if (nrow(data) < 3 || length(unique(data$x)) < 2)
                return(NULL)

            fit <- try(stats::lm(y ~ x, data = data), silent = TRUE)
            if (inherits(fit, "try-error"))
                return(NULL)

            grid <- data.frame(x = seq(min(data$x), max(data$x), length.out = 100))
            prediction <- try(stats::predict(fit, newdata = grid, interval = "prediction"), silent = TRUE)
            if (inherits(prediction, "try-error"))
                return(NULL)

            interval <- cbind(grid, as.data.frame(prediction[, c("lwr", "upr"), drop = FALSE]))
            if (! is.null(group))
                interval$group <- group
            interval
        }
    )
)
