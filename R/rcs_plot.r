#' Plot ristricted cubic spline
#' @description Plot ristricted cubic spline based on package `rms`. Support both logistic and cox model.
#' @param data A data frame.
#' @param x A character string of the predictor variable.
#' @param y A character string of the outcome variable.
#' @param time A character string of the time variable. If `NULL`, logistic regression is used.
#'   Otherwise, Cox proportional hazards regression is used.
#' @param covs A character vector of covariate names.
#' @param knot The number of knots. If `NULL`, the number of knots is determined by AIC minimum.
#' @param add_hist A logical value. If `TRUE`, add histogram to the plot.
#' @param ref The reference value for the plot. Could be `"x_median"`, `"x_mean"`, `"ratio_min"`, or a numeric value.
#'   If `"x_median"`, the median of the predictor variable is used. If `"ratio_min"`, the value of the
#'   predictor variable that has the minium predicted risk is used. If a numeric value, that value is used.
#' @param ref_digits The number of digits for the reference value.
#' @param group_by_ref A logical value. If `TRUE`, split the histogram at the reference value from `ref` into
#'   two groups.
#' @param group_title A character string of the title for the group. Ignored if `group_by_ref` is `FALSE`.
#' @param group_labels A character vector of the labels for the group. If `NULL`, the labels are generated
#'   automatically. Ignored if `group_by_ref` is `FALSE`.
#' @param group_colors A character vector of colors for the plot. If `NULL`, the default colors are used.
#'   If `group_by_ref` is `FALSE`, the first color is used as fill color.
#' @param breaks The number of breaks for the histogram.
#' @param rcs_color The color for the restricted cubic spline.
#' @param print_p_ph A logical value. If `TRUE`, print the p-value of the proportional hazards test
#'   (`survival::cox.zph()`) in the plot.
#' @param trans The transformation for the y axis in the plot.
#'   Passed to `ggplot2::scale_y_continuous(transform = trans)`.
#' @param save_plot A logical value indicating whether to save the plot.
#' @param filename A character string specifying the filename for the plot. If `NULL`, a default filename is used.
#' @param ratio_max The maximum ratio of the plot. If `NULL`, the maximum ratio is determined automatically.
#' @param hist_max The maximum value for the histogram. If `NULL`, the maximum value is determined automatically.
#' @param xlim The x-axis limits for the plot. If `NULL`, the limits are determined automatically.
#' @param return_details A logical value indicating whether to return the details of the plot.
#'
#' @returns A `ggplot` object, or a list containing the `ggplot` object and other details if `return_details` is `TRUE`.
#' @export
#' @examples
#' data(cancer, package = "survival")
#' # coxph model with time assigned
#' rcs_plot(cancer, x = "age", y = "status", time = "time", covs = "ph.karno")
#'
#' # logistic model with time not assigned
#' cancer$dead <- cancer$status == 2
#' rcs_plot(cancer, x = "age", y = "dead", covs = "ph.karno")
rcs_plot <- function(data, x, y, time = NULL, covs = NULL, knot = 4, add_hist = TRUE, ref = "x_median", ref_digits = 3,
                     group_by_ref = TRUE, group_title = NULL, group_labels = NULL, group_colors = NULL, breaks = 20,
                     rcs_color = "#e23e57", print_p_ph = TRUE, trans = "identity", save_plot = TRUE, filename = NULL,
                     ratio_max = NULL, hist_max = NULL, xlim = NULL, return_details = FALSE) {
  if (!is.null(xlim) && length(xlim) != 2) stop("xlim must be a vector of length 2")
  if (is.null(group_colors)) {
    group_colors <- emp_colors
  }

  analysis_type <- ifelse(is.null(time), "logistic", "cox")
  covs <- remove_conflict(covs, c(y, x, time))
  indf <- dplyr::select(data, all_of(c(y, x, time, covs)))

  nmissing <- sum(!complete.cases(indf))
  if (nmissing > 0) {
    warning(paste0(nmissing, " incomplete cases excluded."))
  }
  indf <- indf[complete.cases(indf), ]

  dd <- rms::datadist(indf)
  .dd_out <<- dd
  old_datadist <- getOption("datadist")
  on.exit(
    {
      options(datadist = old_datadist)
    },
    add = TRUE
  )
  options(datadist = ".dd_out")

  aics <- NULL
  if (is.null(knot)) {
    for (i in 3:7) {
      formula <- create_formula(y, x, time = time, covs = covs, rcs_knots = i)
      if (analysis_type == "cox") {
        fit <- rms::cph(formula,
          data = indf, x = TRUE, y = TRUE, se.fit = TRUE,
          tol = 1e-25, surv = TRUE
        )
      } else {
        fit <- rms::Glm(formula, data = indf, x = TRUE, y = TRUE, family = binomial(link = "logit"))
      }
      aics <- c(aics, AIC(fit))
      kn <- seq(3, 7)[which.min(aics)]
    }
    knot <- kn
  }

  formula <- create_formula(y, x, time = time, covs = covs, rcs_knots = knot)
  phassump <- NULL
  phresidual <- NULL
  if (analysis_type == "cox") {
    fit <- rms::cph(formula,
      data = indf, x = TRUE, y = TRUE, se.fit = TRUE,
      tol = 1e-25, surv = TRUE
    )
    phassump <- survival::cox.zph(fit, transform = "km")
    phresidual <- survminer::ggcoxzph(phassump)
    pvalue_ph <- phassump$table[1, 3]
  } else {
    fit <- rms::Glm(formula, data = indf, x = TRUE, y = TRUE, family = binomial(link = "logit"))
  }

  anova_fit <- anova(fit)
  pvalue_all <- anova_fit[1, 3]
  pvalue_nonlin <- round(anova_fit[2, 3], 3)
  df_pred <- rms::Predict(fit, name = x, fun = exp, type = "predictions", ref.zero = TRUE, conf.int = 0.95, digits = 2)

  df_pred <- data.frame(df_pred)
  if (ref == "ratio_min") {
    ref_val <- df_pred[[x]][which.min(df_pred$yhat)]
  } else if (ref == "x_median") {
    ref_val <- median(indf[[x]])
  } else if (ref == "x_mean") {
    ref_val <- mean(indf[[x]])
  } else {
    ref_val <- ref
  }

  dd[["limits"]]["Adjust to", x] <- ref_val

  if (!is.null(xlim)) {
    dd[["limits"]][c("Low:prediction", "High:prediction"), x] <- xlim
  } else {
    xlim <- dd[["limits"]][c("Low:prediction", "High:prediction"), x]
  }
  .dd_out <<- dd
  fit <- update(fit)
  df_pred <- rms::Predict(fit, name = x, fun = exp, type = "predictions", ref.zero = TRUE, conf.int = 0.95, digits = 2)
  df_rcs <- as.data.frame(dplyr::select(df_pred, all_of(c(x, "yhat", "lower", "upper"))))

  colnames(df_rcs) <- c("x", "y", "lower", "upper")
  if (is.null(ratio_max)) {
    ymax1 <- ceiling(min(max(df_rcs[, "upper"], na.rm = TRUE), max(df_rcs[, "y"], na.rm = TRUE) * 1.5))
  } else {
    ymax1 <- ratio_max
  }
  df_rcs$upper[df_rcs$upper > ymax1] <- ymax1

  xtitle <- x
  if (analysis_type == "cox") {
    ytitle1 <- ifelse(is.null(covs), "Unadjusted HR (95% CI)", "Adjusted HR (95% CI)")
  } else {
    ytitle1 <- ifelse(is.null(covs), "Unadjusted OR (95% CI)", "Adjusted OR (95% CI)")
  }

  ytitle2 <- "Percentage of Population (%)"
  offsetx1 <- (xlim[2] - xlim[1]) * 0.02
  offsety1 <- ymax1 * 0.02
  labelx1 <- xlim[1] + (xlim[2] - xlim[1]) * 0.15
  labely1 <- ymax1 * 0.9
  label1_1 <- "Estimation"
  label1_2 <- "95% CI"
  labelx2 <- xlim[1] + (xlim[2] - xlim[1]) * 0.95
  labely2 <- ymax1 * 0.9
  label2 <- paste0(
    "P-overall ",
    ifelse(pvalue_all < 0.001, "< 0.001", paste0("= ", sprintf("%.3f", pvalue_all))),
    "\nP-non-linear ",
    ifelse(pvalue_nonlin < 0.001, "< 0.001", paste0("= ", sprintf("%.3f", pvalue_nonlin)))
  )
  if (analysis_type == "cox" && print_p_ph) {
    label2 <- paste0(
      label2, "\nP-proportional ",
      ifelse(pvalue_ph < 0.001, "< 0.001", paste0("= ", sprintf("%.3f", pvalue_ph)))
    )
  }

  p <- ggplot2::ggplot()

  if (add_hist) {
    df_hist <- indf[indf[[x]] >= xlim[1] & indf[[x]] <= xlim[2], ]
    if (length(breaks) == 1) {
      breaks <- break_at(xlim, breaks, ref_val)
    }
    h <- hist(df_hist[[x]], breaks = breaks, right = FALSE, plot = FALSE)

    df_hist_plot <- data.frame(x = h[["mids"]], freq = h[["counts"]], pct = h[["counts"]] / sum(h[["counts"]]))

    if (is.null(hist_max)) {
      ymax2 <- ceiling(max(df_hist_plot$pct * 1.5) * 20) * 5
    } else {
      ymax2 <- hist_max
    }
    scale_factor <- ymax2 / ymax1

    if (group_by_ref) {
      df_hist_plot$Group <- cut_by(df_hist_plot$x, ref_val, labels = group_labels, label_type = "LMH")
      tmp_group <- cut_by(indf[[x]], ref_val, labels = group_labels, label_type = "LMH")
      levels(df_hist_plot$Group) <- paste0(levels(df_hist_plot$Group), " (n=", table(tmp_group), ")")
      p <- p +
        geom_bar(
          data = df_hist_plot,
          aes(x = x, y = pct * 100 / scale_factor, fill = Group),
          stat = "identity",
        ) +
        scale_fill_manual(values = group_colors, name = group_title)
    } else {
      p <- p +
        geom_bar(
          data = df_hist_plot,
          aes(x = x, y = pct * 100 / scale_factor, fill = "1"),
          stat = "identity", show.legend = FALSE
        ) +
        scale_fill_manual(values = group_colors)
    }
  }

  p <- p +
    geom_hline(yintercept = 1, linewidth = 1, linetype = 2, color = "grey") +
    geom_ribbon(
      data = df_rcs, aes(x = x, ymin = lower, ymax = upper),
      fill = rcs_color, alpha = 0.1
    ) +
    geom_line(data = df_rcs, aes(x = x, y = y), color = rcs_color, linewidth = 1) +
    geom_point(aes(x = ref_val, y = 1), color = rcs_color, size = 2) +
    geom_segment(
      aes(
        x = c(labelx1 - offsetx1 * 5, labelx1 - offsetx1 * 5),
        xend = c(labelx1 - offsetx1, labelx1 - offsetx1),
        y = c(labely1 + offsety1, labely1 - offsety1),
        yend = c(labely1 + offsety1, labely1 - offsety1)
      ),
      linetype = 1,
      color = rcs_color,
      linewidth = 1,
      alpha = c(1, 0.1)
    ) +
    geom_text(aes(
      x = ref_val, y = 0.9,
      label = paste0("Ref=", format(ref_val, digits = ref_digits))
    )) +
    geom_text(aes(x = labelx1, y = labely1 + offsety1, label = label1_1), hjust = 0) +
    geom_text(aes(x = labelx1, y = labely1 - offsety1, label = label1_2), hjust = 0) +
    geom_text(aes(x = labelx2, y = labely2, label = label2), hjust = 1) +
    scale_x_continuous(xtitle, limits = xlim, expand = c(0.01, 0.01))
  if (add_hist) {
    p <- p +
      scale_y_continuous(
        ytitle1,
        expand = c(0, 0),
        limits = c(0, ymax1),
        transform = trans,
        sec.axis = sec_axis(
          name = ytitle2, transform = ~ . * scale_factor,
        )
      )
  } else {
    p <- p +
      scale_y_continuous(
        ytitle1,
        expand = c(0, 0),
        limits = c(0, ymax1),
        transform = trans
      )
  }
  p <- p +
    annotate("text",
      label = paste0("N = ", nrow(indf)), size = 5,
      x = mean(ggplot_build(p)$layout$panel_params[[1]]$x.range),
      y = max(ggplot_build(p)$layout$panel_params[[1]]$y.range) * 0.9,
      hjust = 0.5, vjust = 0.5
    ) +
    theme_bw() +
    theme(
      axis.line = element_line(),
      panel.grid = element_blank(),
      panel.border = element_blank(),
      legend.position = "top"
    )

  if (save_plot) {
    if (is.null(filename)) {
      filename <- paste0(paste0(c(x, paste0(knot, "knot"), paste0("with_", length(covs), "covs")),
        collapse = "_"
      ), ".png")
    }
    ggsave(filename, p, width = 6, height = 6)
  }

  if (return_details) {
    details <- list(
      aics = aics, knot = knot, n.valid = nrow(indf), n.plot = nrow(df_hist),
      phassump = phassump, phresidual = phresidual,
      pvalue_all = pvalue_all,
      pvalue_nonlin = pvalue_nonlin,
      ref = ref_val, plot = p
    )
    return(details)
  } else {
    return(p)
  }
}

#' Generate breaks for histogram
#' @description Generate breaks for histogram that covers xlim and includes a ref_val.
#' @param xlim A vector of length 2.
#' @param breaks The number of breaks.
#' @param ref_val The reference value to include in breaks.
#'
#' @returns A vector of breaks of length `breaks + 1`.
#' @export
#' @examples
#' break_at(xlim = c(0, 10), breaks = 12, ref_val = 3.12)
break_at <- function(xlim, breaks, ref_val) {
  if (length(xlim) != 2) stop("xlim must be a vector of length 2")
  bks <- seq(xlim[1], xlim[2], length.out = breaks + 1)
  if (!ref_val %in% bks) {
    bks <- seq(xlim[1], xlim[2], length.out = breaks)
    h <- (xlim[2] - xlim[1]) / (breaks - 1)
    bks <- c(bks[1] - h, bks)
    tmp <- ref_val - bks
    tmp <- tmp[tmp > 0]
    bks <- bks + tmp[length(tmp)]
  }
  bks
}

#' Filter predictors for RCS
#' @description Filter predictors that can be used to fit for RCS models.
#' @param data A data frame.
#' @param predictors A vector of predictor names to be filtered.
#'
#' @returns A vector of predictor names. These variables are numeric and have more than 5 unique values.
#' @export
filter_rcs_predictors <- function(data, predictors = NULL) {
  if (is.null(predictors)) {
    predictors <- colnames(data)
  }
  res <- c()
  for (x in predictors) {
    if (is.numeric(data[[x]]) && length(na.omit(unique(data[[x]]))) > 5) {
      res <- union(res, x)
    }
  }
  return(res)
}
