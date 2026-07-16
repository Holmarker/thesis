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
    ) %>%
    filter(!is.na(DaysToExpiry), DaysToExpiry >= 0)
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

prepare_threshold_vars <- function(df) {
  df %>%
    mutate(
      final_180 = DaysToExpiry <= 180,
      # final contract year: the treatment definition used by most of the
      # contract-year literature (comparability variant, logged post-freeze)
      final_365 = DaysToExpiry <= 365,
      expiry_window = cut(
        DaysToExpiry,
        breaks = c(0, 180, 360, 720, Inf),
        right = TRUE,
        include.lowest = TRUE,
        labels = c("0-180", "181-360", "361-720", "721+")
      )
    )
}

run_threshold_models <- function(df, sample_name) {
  threshold_df <- prepare_threshold_vars(df) %>%
    arrange(player_id, Month) %>%
    group_by(player_id) %>%
    mutate(
      prev_expiry = lag(ContractExpiryDate),
      new_spell = is.na(prev_expiry) |
        abs(coalesce(as.numeric(ContractExpiryDate - prev_expiry), 0)) > 90,
      player_spell = paste0(player_id, "_", cumsum(new_spell))
    ) %>%
    ungroup() %>%
    mutate(league_month = paste0(fotmob_source_league, "_", Month))

  list(
    tidy_fe_model(
      feols(fotmob_mean_rating ~ final_180 | player_id + Month, data = threshold_df, cluster = ~player_id),
      "final_180_fe",
      sample_name,
      "fotmob_mean_rating"
    ),
    tidy_fe_model(
      feols(fotmob_minutes_weighted_rating ~ final_180 | player_id + Month, data = threshold_df, cluster = ~player_id),
      "final_180_fe",
      sample_name,
      "fotmob_minutes_weighted_rating"
    ),
    tidy_fe_model(
      feols(fotmob_mean_rating ~ final_365 | player_id + Month, data = threshold_df, cluster = ~player_id),
      "final_365_fe",
      sample_name,
      "fotmob_mean_rating"
    ),
    tidy_fe_model(
      feols(fotmob_minutes_weighted_rating ~ final_365 | player_id + Month, data = threshold_df, cluster = ~player_id),
      "final_365_fe",
      sample_name,
      "fotmob_minutes_weighted_rating"
    ),
    tidy_fe_model(
      feols(fotmob_mean_rating ~ final_365 | player_spell + league_month, data = threshold_df, cluster = ~player_id),
      "final_365_spell_lm",
      sample_name,
      "fotmob_mean_rating"
    ) ,
    tidy_fe_model(
      feols(fotmob_mean_rating ~ i(expiry_window, ref = "181-360") | player_id + Month, data = threshold_df, cluster = ~player_id),
      "expiry_window_fe",
      sample_name,
      "fotmob_mean_rating"
    ),
    tidy_fe_model(
      feols(fotmob_minutes_weighted_rating ~ i(expiry_window, ref = "181-360") | player_id + Month, data = threshold_df, cluster = ~player_id),
      "expiry_window_fe",
      sample_name,
      "fotmob_minutes_weighted_rating"
    )
  ) %>%
    bind_rows()
}

make_threshold_summary <- function(df, sample_name) {
  prepare_threshold_vars(df) %>%
    group_by(expiry_window) %>%
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

source_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_source_league.csv")
all_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
results_dir <- resolve_path("results", "fotmob_regressions")

results_path <- file.path(results_dir, "fotmob_threshold_results.csv")
summary_path <- file.path(results_dir, "fotmob_threshold_summary.csv")

dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

panel_source <- load_panel(source_panel_path)
panel_all <- load_panel(all_panel_path)

results <- bind_rows(
  run_threshold_models(panel_source, "source_league"),
  run_threshold_models(panel_all, "all_comps")
)

summary <- bind_rows(
  make_threshold_summary(panel_source, "source_league"),
  make_threshold_summary(panel_all, "all_comps")
)

write_csv(results, results_path)
write_csv(summary, summary_path)

print(results)
print(summary)
