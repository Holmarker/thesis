library(dplyr)
library(fixest)
library(readr)
library(tibble)

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
      player_id = as.integer(player_id),
      fotmob_mean_rating = as.numeric(fotmob_mean_rating),
      fotmob_minutes_weighted_rating = as.numeric(fotmob_minutes_weighted_rating)
    )
}

fit_threshold_model <- function(df, outcome, cutoff_days, bandwidth_days, donut_days = 0, month_fe = TRUE) {
  local_df <- df %>%
    filter(
      !is.na(DaysToExpiry),
      !is.na(.data[[outcome]]),
      abs(DaysToExpiry - cutoff_days) <= bandwidth_days,
      abs(DaysToExpiry - cutoff_days) > donut_days
    ) %>%
    mutate(
      running = DaysToExpiry - cutoff_days,
      inside_cutoff = DaysToExpiry <= cutoff_days
    )

  if (nrow(local_df) == 0 || dplyr::n_distinct(local_df$inside_cutoff) < 2) {
    return(tibble(
      estimate = NA_real_,
      std_error = NA_real_,
      t_value = NA_real_,
      p_value = NA_real_,
      nobs = nrow(local_df),
      n_players = dplyr::n_distinct(local_df$player_id),
      n_above = sum(local_df$DaysToExpiry > cutoff_days, na.rm = TRUE),
      n_inside = sum(local_df$DaysToExpiry <= cutoff_days, na.rm = TRUE),
      specification = ifelse(month_fe, "month_fe", "no_fe")
    ))
  }

  fml <- if (month_fe) {
    as.formula(paste0(outcome, " ~ inside_cutoff + running + inside_cutoff:running | Month"))
  } else {
    as.formula(paste0(outcome, " ~ inside_cutoff + running + inside_cutoff:running"))
  }

  model <- feols(fml, data = local_df, cluster = ~player_id)
  ct <- as.data.frame(coeftable(model))
  row <- ct["inside_cutoffTRUE", , drop = FALSE]

  tibble(
    estimate = row[["Estimate"]],
    std_error = row[["Std. Error"]],
    t_value = row[["t value"]],
    p_value = row[["Pr(>|t|)"]],
    nobs = nobs(model),
    n_players = dplyr::n_distinct(local_df$player_id),
    n_above = sum(local_df$DaysToExpiry > cutoff_days, na.rm = TRUE),
    n_inside = sum(local_df$DaysToExpiry <= cutoff_days, na.rm = TRUE),
    specification = ifelse(month_fe, "month_fe", "no_fe")
  )
}

source_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_source_league.csv")
all_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
results_dir <- resolve_path("results", "fotmob_regressions")
out_path <- file.path(results_dir, "fotmob_rdd_robustness.csv")

dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

panels <- list(
  source_league = load_panel(source_panel_path),
  all_comps = load_panel(all_panel_path)
)
outcomes <- c("fotmob_mean_rating", "fotmob_minutes_weighted_rating")

main_specs <- expand.grid(
  outcome = outcomes,
  cutoff_days = c(180),
  bandwidth_days = c(45, 60, 90, 120, 180),
  donut_days = c(0, 7, 14),
  month_fe = c(TRUE),
  stringsAsFactors = FALSE
)

placebo_specs <- expand.grid(
  outcome = outcomes,
  cutoff_days = c(120, 150, 210, 240),
  bandwidth_days = c(90),
  donut_days = c(0),
  month_fe = c(TRUE),
  stringsAsFactors = FALSE
)

fe_compare_specs <- expand.grid(
  outcome = outcomes,
  cutoff_days = c(180),
  bandwidth_days = c(90),
  donut_days = c(0),
  month_fe = c(TRUE, FALSE),
  stringsAsFactors = FALSE
)

all_specs <- bind_rows(
  mutate(main_specs, check_type = "bandwidth_donut"),
  mutate(placebo_specs, check_type = "placebo_cutoff"),
  mutate(fe_compare_specs, check_type = "fe_compare")
) %>%
  distinct()

results <- bind_rows(lapply(names(panels), function(sample_name) {
  split(all_specs, seq_len(nrow(all_specs))) %>%
    lapply(function(spec) {
      fit_threshold_model(
        df = panels[[sample_name]],
        outcome = spec$outcome[[1]],
        cutoff_days = spec$cutoff_days[[1]],
        bandwidth_days = spec$bandwidth_days[[1]],
        donut_days = spec$donut_days[[1]],
        month_fe = spec$month_fe[[1]]
      ) %>%
        mutate(
          sample_name = sample_name,
          outcome_name = spec$outcome[[1]],
          check_type = spec$check_type[[1]],
          cutoff_days = spec$cutoff_days[[1]],
          bandwidth_days = spec$bandwidth_days[[1]],
          donut_days = spec$donut_days[[1]]
        ) %>%
        select(
          sample_name, outcome_name, check_type, cutoff_days, bandwidth_days,
          donut_days, specification, estimate, std_error, t_value, p_value,
          nobs, n_players, n_above, n_inside
        )
    }) %>%
    bind_rows()
})) %>%
  bind_rows()

write_csv(results, out_path)
print(results)
