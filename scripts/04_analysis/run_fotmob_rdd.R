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
      ContractExpiryDate = as.Date(ContractExpiryDate),
      DaysToExpiry = as.numeric(DaysToExpiry),
      player_id = as.integer(player_id),
      Bosman = as.logical(Bosman),
      fotmob_mean_rating = as.numeric(fotmob_mean_rating),
      fotmob_minutes_weighted_rating = as.numeric(fotmob_minutes_weighted_rating)
    )
}

run_local_linear_rdd <- function(df, outcome, sample_name, bandwidth_days, cutoff_days = 180) {
  local_df <- df %>%
    filter(
      !is.na(DaysToExpiry),
      !is.na(.data[[outcome]]),
      abs(DaysToExpiry - cutoff_days) <= bandwidth_days
    ) %>%
    mutate(
      running = DaysToExpiry - cutoff_days,
      post_cutoff = DaysToExpiry <= cutoff_days
    )

  if (nrow(local_df) == 0 || dplyr::n_distinct(local_df$post_cutoff) < 2) {
    return(tibble(
      sample_name = sample_name,
      outcome_name = outcome,
      cutoff_days = cutoff_days,
      bandwidth_days = bandwidth_days,
      specification = NA_character_,
      estimate = NA_real_,
      std_error = NA_real_,
      t_value = NA_real_,
      p_value = NA_real_,
      nobs = nrow(local_df),
      n_players = dplyr::n_distinct(local_df$player_id),
      n_left = sum(local_df$DaysToExpiry > cutoff_days, na.rm = TRUE),
      n_right = sum(local_df$DaysToExpiry <= cutoff_days, na.rm = TRUE)
    ))
  }

  model <- tryCatch(
    feols(
      as.formula(paste0(outcome, " ~ post_cutoff + running + post_cutoff:running | Month")),
      data = local_df,
      cluster = ~player_id
    ),
    error = function(e) NULL
  )

  specification <- "month_fe"

  if (is.null(model)) {
    model <- feols(
      as.formula(paste0(outcome, " ~ post_cutoff + running + post_cutoff:running")),
      data = local_df,
      cluster = ~player_id
    )
    specification <- "no_fe"
  }

  coefs <- as.data.frame(coeftable(model))
  row <- coefs["post_cutoffTRUE", , drop = FALSE]

  tibble(
    sample_name = sample_name,
    outcome_name = outcome,
    cutoff_days = cutoff_days,
    bandwidth_days = bandwidth_days,
    specification = specification,
    estimate = row[["Estimate"]],
    std_error = row[["Std. Error"]],
    t_value = row[["t value"]],
    p_value = row[["Pr(>|t|)"]],
    nobs = nobs(model),
    n_players = dplyr::n_distinct(local_df$player_id),
    n_left = sum(local_df$DaysToExpiry > cutoff_days, na.rm = TRUE),
    n_right = sum(local_df$DaysToExpiry <= cutoff_days, na.rm = TRUE)
  )
}

run_sample <- function(path, sample_name, bandwidths = c(30, 60, 90, 180), cutoff_days = 180) {
  df <- load_panel(path)
  outcomes <- c("fotmob_mean_rating", "fotmob_minutes_weighted_rating")

  expand.grid(
    outcome = outcomes,
    bandwidth = bandwidths,
    stringsAsFactors = FALSE
  ) %>%
    split(seq_len(nrow(.))) %>%
    lapply(function(spec) {
      run_local_linear_rdd(
        df = df,
        outcome = spec$outcome[[1]],
        sample_name = sample_name,
        bandwidth_days = spec$bandwidth[[1]],
        cutoff_days = cutoff_days
      )
    }) %>%
    bind_rows()
}

source_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_source_league.csv")
all_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
results_dir <- resolve_path("results", "fotmob_regressions")
out_path <- file.path(results_dir, "fotmob_rdd_results.csv")

dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

results <- bind_rows(
  run_sample(source_panel_path, "source_league"),
  run_sample(all_panel_path, "all_comps")
)

write_csv(results, out_path)
print(results)
