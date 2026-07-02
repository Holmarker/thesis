library(dplyr)
library(ggplot2)
library(readr)
library(scales)

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates) | dir.exists(candidates)]

  if (length(existing) > 0) {
    return(existing[[1]])
  }

  candidates[[1]]
}

load_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      DaysToExpiry = as.numeric(DaysToExpiry),
      fotmob_mean_rating = as.numeric(fotmob_mean_rating),
      fotmob_minutes_weighted_rating = as.numeric(fotmob_minutes_weighted_rating)
    )
}

make_rdd_plot <- function(df, sample_name, outcome, outcome_label,
                          cutoff_days = 180, bandwidth_days = 180, binwidth_days = 30) {
  local_df <- df %>%
    filter(
      !is.na(DaysToExpiry),
      !is.na(.data[[outcome]]),
      abs(DaysToExpiry - cutoff_days) <= bandwidth_days
    ) %>%
    mutate(
      running = DaysToExpiry - cutoff_days,
      side = if_else(running <= 0, "At or below cutoff", "Above cutoff"),
      bin = floor(running / binwidth_days) * binwidth_days
    )

  binned <- local_df %>%
    group_by(bin) %>%
    summarise(
      side = first(side),
      x = mean(running, na.rm = TRUE),
      mean_outcome = mean(.data[[outcome]], na.rm = TRUE),
      n = n(),
      .groups = "drop"
    )

  left_n <- sum(local_df$DaysToExpiry > cutoff_days, na.rm = TRUE)
  right_n <- sum(local_df$DaysToExpiry <= cutoff_days, na.rm = TRUE)

  ggplot() +
    geom_smooth(
      data = filter(binned, x <= 0),
      method = "loess",
      formula = y ~ x,
      span = 0.9,
      se = FALSE,
      level = NULL,
      aes(x = x, y = mean_outcome),
      color = "#6a6a6a",
      linewidth = 1
    ) +
    geom_smooth(
      data = filter(binned, x > 0),
      method = "loess",
      formula = y ~ x,
      span = 0.9,
      se = FALSE,
      level = NULL,
      aes(x = x, y = mean_outcome),
      color = "#6a6a6a",
      linewidth = 1
    ) +
    geom_point(
      data = binned,
      aes(x = x, y = mean_outcome),
      shape = 21,
      size = 3.2,
      stroke = 1,
      fill = "white",
      color = "#4a4a4a"
    ) +
    geom_vline(xintercept = 0, linetype = "solid", color = "#8a8a8a", linewidth = 0.9) +
    labs(
      title = paste0(sample_name, ": estimated discontinuity at 180-day cutoff"),
      subtitle = paste0(
        outcome_label, " | bandwidth +/- ", bandwidth_days, " days | bin width ", binwidth_days, " days"
      ),
      x = "Days to expiry relative to cutoff",
      y = outcome_label
    ) +
    coord_cartesian(xlim = c(-bandwidth_days, bandwidth_days)) +
    scale_x_continuous(breaks = c(-180, -120, -60, 0, 60, 120, 180)) +
    theme_minimal(base_size = 14) +
    theme(
      panel.background = element_rect(fill = "white", color = "#cfcfcf", linewidth = 0.8),
      plot.background = element_rect(fill = "white", color = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = "#e3e3e3", linewidth = 0.5),
      legend.position = "none",
      plot.title = element_text(face = "plain", size = 18, hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5),
      axis.title = element_text(size = 14),
      axis.text = element_text(size = 12, color = "#4a4a4a")
    )
}

make_support_plot <- function(df, sample_name, cutoff_days = 180, bandwidth_days = 180, binwidth_days = 30) {
  local_df <- df %>%
    filter(!is.na(DaysToExpiry), abs(DaysToExpiry - cutoff_days) <= bandwidth_days) %>%
    mutate(running = DaysToExpiry - cutoff_days)

  ggplot(local_df, aes(x = running)) +
    geom_histogram(
      binwidth = binwidth_days,
      boundary = 0,
      fill = "#b8b8b8",
      color = "white",
      linewidth = 0.3
    ) +
    geom_vline(xintercept = 0, linetype = "solid", color = "#8a8a8a", linewidth = 0.9) +
    labs(
      title = paste0(sample_name, ": support around 180-day cutoff"),
      subtitle = "Histogram of observations in the +/- 180 day window",
      x = "Days to expiry relative to 180-day cutoff",
      y = "Observations"
    ) +
    coord_cartesian(xlim = c(-bandwidth_days, bandwidth_days)) +
    scale_x_continuous(breaks = c(-180, -120, -60, 0, 60, 120, 180)) +
    theme_minimal(base_size = 14) +
    theme(
      panel.background = element_rect(fill = "white", color = "#cfcfcf", linewidth = 0.8),
      plot.background = element_rect(fill = "white", color = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = "#e3e3e3", linewidth = 0.5),
      plot.title = element_text(face = "plain", size = 18, hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5),
      axis.title = element_text(size = 14),
      axis.text = element_text(size = 12, color = "#4a4a4a")
    )
}

source_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_source_league.csv")
all_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
results_dir <- resolve_path("results", "fotmob_regressions")

dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

panel_source <- load_panel(source_panel_path)
panel_all <- load_panel(all_panel_path)

plots <- list(
  list(
    data = panel_source,
    sample = "source_league",
    outcome = "fotmob_mean_rating",
    label = "FotMob mean rating",
    file = "fotmob_rdd_source_league_mean_rating.png"
  ),
  list(
    data = panel_source,
    sample = "source_league",
    outcome = "fotmob_minutes_weighted_rating",
    label = "FotMob minutes-weighted rating",
    file = "fotmob_rdd_source_league_weighted_rating.png"
  ),
  list(
    data = panel_source,
    sample = "source_league",
    outcome = "support",
    label = "Support",
    file = "fotmob_rdd_source_league_support.png"
  )
)

for (spec in plots) {
  if (spec$outcome == "support") {
    p <- make_support_plot(
      df = spec$data,
      sample_name = spec$sample
    )
  } else {
    p <- make_rdd_plot(
      df = spec$data,
      sample_name = spec$sample,
      outcome = spec$outcome,
      outcome_label = spec$label
    )
  }

  ggsave(
    filename = file.path(results_dir, spec$file),
    plot = p,
    width = 11,
    height = 7,
    dpi = 300
  )
}
