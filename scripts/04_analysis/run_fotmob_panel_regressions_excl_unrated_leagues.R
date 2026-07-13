library(dplyr)
library(fixest)
library(readr)
library(tibble)

# Variant of run_fotmob_panel_regressions.R that drops the eight leagues with no
# scraped FotMob ratings in 2022/23-2023/24 (dropped in ALL seasons, so the league
# composition is constant over time) and runs only the raw rating outcomes, i.e.
# without the league-standardized z-score terms.

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates) | dir.exists(candidates)]
  if (length(existing) > 0) {
    return(existing[[1]])
  }
  candidates[[1]]
}

excluded_leagues <- c(
  "Ukrainian Premier Liga",
  "Serbian Super Liga",
  "Czech First League",
  "Romanian Liga 1",
  "Bulgarian Parva Liga",
  "Hungarian Nemzeti Bajnoksag",
  "Turkish 1.Lig",
  "Belgian Challenger Pro League"
)

source_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_source_league_strict.csv")
all_comps_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
results_dir <- resolve_path("results", "fotmob_regressions")

if (!dir.exists(results_dir)) {
  dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
}

football_season <- function(month) {
  year <- as.integer(format(month, "%Y"))
  month_num <- as.integer(format(month, "%m"))
  start_year <- if_else(month_num >= 7L, year, year - 1L)
  paste0(start_year, "/", start_year + 1L)
}

load_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      ContractExpiryDate = as.Date(ContractExpiryDate),
      Bosman = as.logical(Bosman),
      player_id = as.integer(player_id),
      DaysToExpiry = as.numeric(DaysToExpiry),
      fotmob_goals = as.numeric(fotmob_goals),
      fotmob_assists = as.numeric(fotmob_assists),
      fotmob_minutes = as.numeric(fotmob_minutes),
      fotmob_win_share = as.numeric(fotmob_win_share),
      season = football_season(Month)
    ) %>%
    filter(!fotmob_source_league %in% excluded_leagues)
}

outcome_vars <- c("fotmob_mean_rating", "fotmob_minutes_weighted_rating")

rating_control_rhs <- "fotmob_goals + fotmob_assists + fotmob_win_share"
win_control_rhs <- "fotmob_win_share"

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

control_suffix <- function(control_set) {
  case_when(
    control_set == "win" ~ "_win_control",
    control_set == "events" ~ "_event_controls",
    TRUE ~ ""
  )
}

control_rhs <- function(control_set) {
  case_when(
    control_set == "win" ~ win_control_rhs,
    control_set == "events" ~ rating_control_rhs,
    TRUE ~ ""
  )
}

weight_suffix <- function(weight_by_minutes) {
  if_else(weight_by_minutes, "_minute_weighted", "")
}

fit_rating_model <- function(formula, df, weight_by_minutes) {
  if (weight_by_minutes) {
    feols(formula, data = df, cluster = ~player_id, weights = ~fotmob_minutes)
  } else {
    feols(formula, data = df, cluster = ~player_id)
  }
}

run_models_for_outcomes <- function(df, model_name, sample_name, rhs,
                                    control_set = "none", weight_by_minutes = FALSE) {
  controls <- control_rhs(control_set)
  rhs_full <- if (nzchar(controls)) paste(rhs, controls, sep = " + ") else rhs

  lapply(outcome_vars, function(outcome) {
    tidy_fe_model(
      fit_rating_model(
        as.formula(paste0(outcome, " ~ ", rhs_full, " | player_id + Month")),
        df = df,
        weight_by_minutes = weight_by_minutes
      ),
      paste0(model_name, control_suffix(control_set), weight_suffix(weight_by_minutes)),
      sample_name,
      outcome
    )
  }) %>%
    bind_rows()
}

run_all_specs <- function(df, model_name, sample_name, rhs) {
  bind_rows(
    run_models_for_outcomes(df, model_name, sample_name, rhs),
    run_models_for_outcomes(df, model_name, sample_name, rhs, control_set = "win"),
    run_models_for_outcomes(df, model_name, sample_name, rhs, control_set = "events"),
    run_models_for_outcomes(df, model_name, sample_name, rhs, weight_by_minutes = TRUE),
    run_models_for_outcomes(df, model_name, sample_name, rhs, control_set = "win", weight_by_minutes = TRUE),
    run_models_for_outcomes(df, model_name, sample_name, rhs, control_set = "events", weight_by_minutes = TRUE)
  )
}

run_bosman_models <- function(df, sample_name) {
  run_all_specs(df, "bosman_fe", sample_name, "Bosman")
}

run_expiry_bin_models <- function(df, sample_name) {
  expiry_df <- df %>%
    mutate(expiry_bin_6m = make_expiry_bin_6m(DaysToExpiry)) %>%
    filter(!is.na(expiry_bin_6m))
  run_all_specs(expiry_df, "expiry_bin_6m_fe", sample_name, 'i(expiry_bin_6m, ref = "24:30")')
}

panel_source <- load_panel(source_panel_path)
panel_all <- load_panel(all_comps_panel_path)

message("Rows after excluding 8 unrated leagues (source): ", nrow(panel_source))
message("Rows after excluding 8 unrated leagues (all comps): ", nrow(panel_all))

all_results <- bind_rows(
  run_bosman_models(panel_source, "source_league_strict_excl8"),
  run_bosman_models(panel_all, "all_comps_strict_excl8"),
  run_expiry_bin_models(panel_source, "source_league_strict_excl8"),
  run_expiry_bin_models(panel_all, "all_comps_strict_excl8")
)

out_path <- file.path(results_dir, "fotmob_regression_results_excl_unrated_leagues.csv")
utils::write.csv(all_results, out_path, row.names = FALSE, na = "")
message("Saved regression results to: ", out_path)
