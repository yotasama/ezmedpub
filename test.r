rcs_plot <- function(data, x, y, time = NULL, covs = NULL, knot = 4, add_hist = TRUE, ref = "median", ref_digits = 3,
                     group_by_ref = TRUE, group_title = NULL, group_labels = NULL, group_colors = NULL, breaks = 20,
                     rcs_color = "#e23e57", print_p_ph = T, trans = "identity", save_plot = TRUE, filename = NULL,
                     ratio_max = NULL, hist_max = NULL, xlim = NULL, return_details = FALSE) {
  if (!is.null(xlim) && length(xlim) != 2) stop("xlim must be a vector of length 2")
  if (is.null(group_colors)) {
    group_colors <- .color_panel
  }
  
  analysis_type <- ifelse(is.null(time), "logistic", "cox")
  covs <- remove_conflict(covs, c(y, x, time))
  indf <- dplyr::select(data, all_of(c(y, x, time, covs)))
  if (".x" %in% setdiff(colnames(indf), x)) stop("Colname '.x' is reserved.")
  colnames(indf)[2] <- ".x"
  
  nmissing <- sum(!complete.cases(indf))
  if (nmissing > 0) {
    warning(paste0(nmissing, " incomplete cases excluded."))
  }
  indf <- indf[complete.cases(indf), ]
  dd <- NULL
  dd <<- rms::datadist(indf)
  old <- options()
  on.exit(options(old))
  options(datadist = "dd")
  
  aics <- NULL
  if (is.null(knot)) {
    for (i in 3:7) {
      formula <- create_formula(y, ".x", time = time, covs = covs, rcs_knots = i)
      if (analysis_type == "cox") {
        fit <- rms::cph(formula, data = indf, x = TRUE, y = TRUE, se.fit = TRUE,
                        tol = 1e-25, surv = TRUE)
      } else {
        fit <- rms::Glm(formula, data = indf, x = TRUE, y = TRUE, family = binomial(link = "logit"))
      }
      aics <- c(aics, AIC(fit))
      kn <- seq(3, 7)[which.min(aics)]
    }
    knot <- kn
  }
  
  formula <- create_formula(y, ".x", time = time, covs = covs, rcs_knots = knot)
  phassump <- NULL
  phresidual <- NULL
  if (analysis_type == "cox") {
    fit <- rms::cph(formula, data = indf, x = TRUE, y = TRUE, se.fit = TRUE,
                    tol = 1e-25, surv = TRUE)
    phassump <- survival::cox.zph(fit, transform = "km")
    phresidual <- survminer::ggcoxzph(phassump)
    pvalue_ph <- phassump$table[1, 3]
  } else {
    fit <- rms::Glm(formula, data = indf, x = TRUE, y = TRUE, family = binomial(link = "logit"))
  }
  
  anova_fit <- anova(fit)
  pvalue_all <- anova_fit[1, 3]
  pvalue_nonlin <- round(anova_fit[2, 3], 3)
  df_pred <- rms::Predict(fit, .x, fun = exp, type = "predictions", ref.zero = T, conf.int = 0.95, digits = 2)
  
  df_pred <- data.frame(df_pred)
  if (ref == "min") {
    ref_val <- ushap$x[which.min(ushap$yhat)]
  } else if (ref == "median") {
    ref_val <- median(indf$x)
  } else {
    ref_val <- ref
  }
  
  dd[["limits"]]["Adjust to", "x"] <<- ref_val
  
  # Predict 重写
  fit <- update(fit)
  df_pred <- rms::Predict(fit, .x, fun = exp, type = "predictions", ref.zero = T, conf.int = 0.95, digits = 2)
  df_rcs <- as.data.frame(dplyr::select(df_pred, all_of(c("x", "yhat", "lower", "upper"))))
  if (!is.null(xlim)) {
    df_rcs <- filter(df_rcs, (x >= xlim[1]) & (x <= xlim[2]))
  }else {
    xlim = c(min(df_rcs$x), max(df_rcs$x))
  }
  colnames(df_rcs) <- c("x", "y", "lower", "upper")
  if (is.null(ratio_max)) {
    ymax1 <- ceiling(min(max(df_rcs[, "upper"], na.rm = T), max(df_rcs[, "y"], na.rm = T) * 1.5))
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
    df_hist <- indf[indf[, "x"] >= xlim[1] & indf[, "x"] <= xlim[2], ]
    if (length(breaks) == 1) {
      breaks <- break_at(xlim, breaks, ref_val)
    }
    h <- hist(df_hist$x, breaks = breaks, right = FALSE, plot = F)
    
    df_hist_plot <- data.frame(x = h[["mids"]], freq = h[["counts"]], pct = h[["counts"]] / sum(h[["counts"]]))
    
    if (is.null(hist_max)) {
      ymax2 <- ceiling(max(df_hist_plot$pct * 1.5) * 20) * 5
    } else {
      ymax2 <- hist_max
    }
    scale_factor <- ymax2 / ymax1
    
    if (group_by_ref) {
      df_hist_plot$Group <- cut_by(df_hist_plot$x, ref_val, labels = group_labels, label_type = "LMH")
      tmp_group <- cut_by(indf$x, ref_val, labels = group_labels, label_type = "LMH")
      levels(df_hist_plot$Group) <- paste0(levels(df_hist_plot$Group), " (n=", table(tmp_group), ")")
      p <- p +
        geom_bar(
          data = df_hist_plot,
          aes(x = x, y = pct * 100 / scale_factor, fill = Group),
          stat = "identity",
        ) +
        scale_fill_manual(values = group_colors, name = group_title)
    }else {
      p <- p +
        geom_bar(
          data = df_hist_plot,
          aes(x = x, y = pct * 100 / scale_factor, fill = "1"),
          stat = "identity", show.legend = F
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
        limit = c(0, ymax1),
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
        limit = c(0, ymax1),
        transform = trans
      )
  }
  p <- p +
    annotate("text", label = paste0("N = ", nrow(indf)), size = 5,
             x = mean(ggplot_build(p)$layout$panel_params[[1]]$x.range), # x轴中点
             y = max(ggplot_build(p)$layout$panel_params[[1]]$y.range) * 0.9,  # y轴最大值
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
      filename = paste0(paste0(c(x, paste0(knot, "knot"), paste0("with_", length(covs), "covs")),
                               collapse = "_"), ".png")
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
  }else {
    return(p)
  }
}