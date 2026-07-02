library(dplyr)
library(fixest)
library(readr)
library(stringr)
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

source_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_source_league_strict.csv")
all_comps_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
results_dir <- resolve_path("results", "fotmob_regressions")

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

safe_write_csv <- function(df, path) {
  tmp_path <- tempfile(
    pattern = paste0(basename(path), "."),
    tmpdir = dirname(path),
    fileext = ".tmp"
  )

  utils::write.csv(df, tmp_path, row.names = FALSE, na = "")

  if (file.exists(path)) {
    file.remove(path)
  }

  file.rename(tmp_path, path)
}

football_season <- function(month) {
  year <- as.integer(format(month, "%Y"))
  month_num <- as.integer(format(month, "%m"))
  start_year <- if_else(month_num >= 7L, year, year - 1L)
  paste0(start_year, "/", start_year + 1L)
}

standardize_within <- function(x) {
  x <- if_else(!is.na(x) & x > 0, x, NA_real_)
  mu <- mean(x, na.rm = TRUE)
  sigma <- sd(x, na.rm = TRUE)

  if (is.na(sigma) || sigma == 0) {
    return(rep(NA_real_, length(x)))
  }

  (x - mu) / sigma
}

load_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      ContractExpiryDate = as.Date(ContractExpiryDate),
      LastExtensionDate = as.Date(LastExtensionDate),
      Bosman = as.logical(Bosman),
      player_id = as.integer(player_id),
      fotmob_player_id = as.integer(fotmob_player_id),
      Age = as.numeric(Age),
      DaysToExpiry = as.numeric(DaysToExpiry),
      season = football_season(Month),
      has_positive_mean_rating = !is.na(fotmob_mean_rating) & fotmob_mean_rating > 0,
      has_positive_weighted_rating = !is.na(fotmob_minutes_weighted_rating) & fotmob_minutes_weighted_rating > 0
    ) %>%
    group_by(fotmob_source_league, season) %>%
    mutate(
      z_mean_rating_league_season = standardize_within(fotmob_mean_rating),
      z_weighted_rating_league_season = standardize_within(fotmob_minutes_weighted_rating)
    ) %>%
    ungroup() %>%
    group_by(fotmob_source_league, Month) %>%
    mutate(
      z_mean_rating_league_month = standardize_within(fotmob_mean_rating),
      z_weighted_rating_league_month = standardize_within(fotmob_minutes_weighted_rating)
    ) %>%
    ungroup()
}

outcome_vars <- c(
  "fotmob_mean_rating",
  "fotmob_minutes_weighted_rating",
  "z_mean_rating_league_season",
  "z_weighted_rating_league_season",
  "z_mean_rating_league_month",
  "z_weighted_rating_league_month"
)

make_expiry_bin_6m <- function(days_to_expiry) {
  months_to_expiry <- days_to_expiry / 30.44

  cut(
    months_to_expiry,
    breaks = c(0, 6, 12, 18, 24, 30, 36, 48, Inf),
    right = FALSE,
    include.lowest = TRUE,
    labels = c("0:6", "6:12", "12:18", "18:24", "24:30", "30:36", "36:48", "48+")
  )
}

prepare_renewal_panel <- function(df) {
  df %>%
    arrange(player_id, Month) %>%
    group_by(player_id) %>%
    mutate(
      prev_expiry = lag(ContractExpiryDate),
      expiry_jump_days = as.numeric(ContractExpiryDate - prev_expiry),
      signed_new_contract = !is.na(expiry_jump_days) & expiry_jump_days > 90,
      observed_renewals_so_far = cumsum(coalesce(signed_new_contract, FALSE)),
      renewals_before_month = lag(observed_renewals_so_far, default = 0L),
      post_observed_renewal = renewals_before_month > 0,
      renewal_status = case_when(
        signed_new_contract ~ "signing_month",
        post_observed_renewal ~ "post_observed_renewal",
        TRUE ~ "no_observed_renewal_yet"
      )
    ) %>%
    ungroup()
}

tidy_fe_model <- function(model, model_name, sample_name, outcome_name) {
  out <- as_tibble(coeftable(model), rownames = "term")
  names(out) <- c("term", "estimate", "std_error", "t_value", "p_value")

  out %>%
    mutate(
      model_name = model_name,
      sample_name = sample_name,
      outcome_name = outcome_name,
      nobs = nobs(model)
    ) %>%
    select(model_name, sample_name, outcome_name, term, estimate, std_error, t_value, p_value, nobs)
}

expiry_bin_summary <- function(df, sample_name) {
  df %>%
    mutate(expiry_bin_6m = make_expiry_bin_6m(DaysToExpiry)) %>%
    filter(!is.na(expiry_bin_6m)) %>%
    group_by(expiry_bin_6m) %>%
    summarise(
      sample_name = sample_name,
      n_rows = n(),
      n_players = n_distinct(player_id),
      mean_rating_raw = mean(fotmob_mean_rating, na.rm = TRUE),
      weighted_rating_raw = mean(fotmob_minutes_weighted_rating, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    relocate(sample_name)
}

observed_renewal_summary <- function(df, sample_name) {
  df %>%
    prepare_renewal_panel() %>%
    group_by(renewal_status) %>%
    summarise(
      sample_name = sample_name,
      n_rows = n(),
      n_players = n_distinct(player_id),
      observed_signing_events = sum(signed_new_contract, na.rm = TRUE),
      mean_rating_raw = mean(fotmob_mean_rating, na.rm = TRUE),
      weighted_rating_raw = mean(fotmob_minutes_weighted_rating, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    relocate(sample_name)
}

regression_sample_coverage <- function(df, sample_name) {
  df %>%
    group_by(season) %>%
    summarise(
      sample_name = sample_name,
      n_rows = n(),
      n_players = n_distinct(player_id),
      n_clubs = n_distinct(ClubID),
      bosman_rows = sum(Bosman, na.rm = TRUE),
      positive_mean_rating_rows = sum(has_positive_mean_rating, na.rm = TRUE),
      positive_weighted_rating_rows = sum(has_positive_weighted_rating, na.rm = TRUE),
      min_month = min(Month, na.rm = TRUE),
      max_month = max(Month, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    relocate(sample_name)
}

run_models_for_outcomes <- function(df, model_name, sample_name, rhs) {
  lapply(outcome_vars, function(outcome) {
    tidy_fe_model(
      feols(
        as.formula(paste0(outcome, " ~ ", rhs, " | player_id + Month")),
        data = df,
        cluster = ~player_id
      ),
      model_name,
      sample_name,
      outcome
    )
  }) %>%
    bind_rows()
}

run_bosman_models <- function(df, sample_name) {
  run_models_for_outcomes(df, "bosman_fe", sample_name, "Bosman")
}

run_expiry_bin_models <- function(df, sample_name) {
  expiry_df <- df %>%
    mutate(expiry_bin_6m = make_expiry_bin_6m(DaysToExpiry)) %>%
    filter(!is.na(expiry_bin_6m))

  run_models_for_outcomes(
    expiry_df,
    "expiry_bin_6m_fe",
    sample_name,
    'i(expiry_bin_6m, ref = "24:30")'
  )
}

run_observed_renewal_models <- function(df, sample_name) {
  renewal_df <- prepare_renewal_panel(df)

  run_models_for_outcomes(
    renewal_df,
    "observed_renewal_status_fe",
    sample_name,
    "signed_new_contract + post_observed_renewal"
  )
}

ensure_dir(results_dir)

panel_source <- load_panel(source_panel_path)
panel_all <- load_panel(all_comps_panel_path)

all_results <- bind_rows(
  run_bosman_models(panel_source, "source_league_strict"),
  run_bosman_models(panel_all, "all_comps_strict"),
  run_expiry_bin_models(panel_source, "source_league_strict"),
  run_expiry_bin_models(panel_all, "all_comps_strict"),
  run_observed_renewal_models(panel_all, "all_comps_strict")
)

expiry_summary <- bind_rows(
  expiry_bin_summary(panel_source, "source_league_strict"),
  expiry_bin_summary(panel_all, "all_comps_strict")
)

renewal_summary <- observed_renewal_summary(panel_all, "all_comps_strict")
sample_coverage <- bind_rows(
  regression_sample_coverage(panel_source, "source_league_strict"),
  regression_sample_coverage(panel_all, "all_comps_strict")
)

safe_write_csv(all_results, file.path(results_dir, "fotmob_regression_results.csv"))
safe_write_csv(expiry_summary, file.path(results_dir, "fotmob_expiry_6m_summary.csv"))
safe_write_csv(renewal_summary, file.path(results_dir, "fotmob_observed_renewal_summary.csv"))
safe_write_csv(renewal_summary, file.path(results_dir, "fotmob_renewal_6m_summary.csv"))
safe_write_csv(sample_coverage, file.path(results_dir, "fotmob_regression_sample_coverage.csv"))

message("Saved regression results to: ", file.path(results_dir, "fotmob_regression_results.csv"))
message("Saved expiry-bin summary to: ", file.path(results_dir, "fotmob_expiry_6m_summary.csv"))
message("Saved observed-renewal summary to: ", file.path(results_dir, "fotmob_observed_renewal_summary.csv"))
message("Saved legacy observed-renewal copy to: ", file.path(results_dir, "fotmob_renewal_6m_summary.csv"))
message("Saved regression sample coverage to: ", file.path(results_dir, "fotmob_regression_sample_coverage.csv"))
