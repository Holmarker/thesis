library(dplyr)
library(fixest)
library(readr)
library(stringr)
library(tibble)

source_panel_path <- file.path("data", "panel", "fotmob_analysis_panel_source_league_strict.csv")
all_comps_panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
results_dir <- file.path("results", "fotmob_regressions")

top5_leagues <- c(
  "English Premier League",
  "Spanish LaLiga",
  "German Bundesliga",
  "Italian Serie A",
  "French Ligue 1"
)

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

load_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      ContractExpiryDate = as.Date(ContractExpiryDate),
      Bosman = as.logical(Bosman),
      player_id = as.integer(player_id),
      Age = as.numeric(Age),
      DaysToExpiry = as.numeric(DaysToExpiry),
      season = football_season(Month)
    ) %>%
    group_by(fotmob_source_league, season) %>%
    mutate(
      z_mean_rating_league_season = standardize_within(fotmob_mean_rating),
      z_weighted_rating_league_season = standardize_within(fotmob_minutes_weighted_rating)
    ) %>%
    ungroup() %>%
    mutate(
      age_group = case_when(
        Age < 23 ~ "u23",
        Age < 29 ~ "23_28",
        Age >= 29 ~ "29_plus",
        TRUE ~ NA_character_
      ),
      position_group = if_else(
        fotmob_position_group %in% c("keepers", "defenders", "midfielders", "attackers"),
        fotmob_position_group,
        NA_character_
      ),
      starter_share = if_else(
        !is.na(fotmob_matches) & fotmob_matches > 0,
        fotmob_starts_proxy / fotmob_matches,
        NA_real_
      ),
      squad_role = case_when(
        starter_share >= 0.5 ~ "starter",
        starter_share < 0.5 ~ "rotation_bench",
        TRUE ~ NA_character_
      ),
      league_tier = if_else(fotmob_source_league %in% top5_leagues, "top5", "other")
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
      post_observed_renewal = renewals_before_month > 0
    ) %>%
    ungroup()
}

tidy_fe_model <- function(model, model_name, sample_name, outcome_name, split_var, split_level) {
  out <- as_tibble(coeftable(model), rownames = "term")
  names(out) <- c("term", "estimate", "std_error", "t_value", "p_value")

  out %>%
    mutate(
      model_name = model_name,
      sample_name = sample_name,
      outcome_name = outcome_name,
      split_var = split_var,
      split_level = split_level,
      nobs = nobs(model)
    ) %>%
    select(
      model_name, sample_name, outcome_name, split_var, split_level,
      term, estimate, std_error, t_value, p_value, nobs
    )
}

outcome_vars <- c("z_mean_rating_league_season", "z_weighted_rating_league_season")

run_subgroup_models <- function(df, sample_name, split_var, split_level) {
  subgroup <- df %>% filter(.data[[split_var]] == split_level)

  expiry_df <- subgroup %>%
    mutate(expiry_bin_6m = make_expiry_bin_6m(DaysToExpiry)) %>%
    filter(!is.na(expiry_bin_6m))

  renewal_df <- prepare_renewal_panel(subgroup)

  results <- list()

  for (outcome in outcome_vars) {
    results[[length(results) + 1]] <- tryCatch(
      tidy_fe_model(
        feols(
          as.formula(paste0(outcome, " ~ Bosman | player_id + Month")),
          data = subgroup,
          cluster = ~player_id
        ),
        "bosman_fe", sample_name, outcome, split_var, split_level
      ),
      error = function(e) NULL
    )

    results[[length(results) + 1]] <- tryCatch(
      tidy_fe_model(
        feols(
          as.formula(paste0(outcome, ' ~ i(expiry_bin_6m, ref = "24:30") | player_id + Month')),
          data = expiry_df,
          cluster = ~player_id
        ),
        "expiry_bin_6m_fe", sample_name, outcome, split_var, split_level
      ),
      error = function(e) NULL
    )

    results[[length(results) + 1]] <- tryCatch(
      tidy_fe_model(
        feols(
          as.formula(paste0(outcome, " ~ signed_new_contract + post_observed_renewal | player_id + Month")),
          data = renewal_df,
          cluster = ~player_id
        ),
        "observed_renewal_status_fe", sample_name, outcome, split_var, split_level
      ),
      error = function(e) NULL
    )
  }

  bind_rows(results)
}

splits <- list(
  age_group = c("u23", "23_28", "29_plus"),
  position_group = c("keepers", "defenders", "midfielders", "attackers"),
  squad_role = c("starter", "rotation_bench"),
  league_tier = c("top5", "other")
)

run_all_splits <- function(df, sample_name) {
  bind_rows(lapply(names(splits), function(split_var) {
    bind_rows(lapply(splits[[split_var]], function(split_level) {
      run_subgroup_models(df, sample_name, split_var, split_level)
    }))
  }))
}

subgroup_sizes <- function(df, sample_name) {
  bind_rows(lapply(names(splits), function(split_var) {
    df %>%
      filter(!is.na(.data[[split_var]])) %>%
      group_by(split_level = .data[[split_var]]) %>%
      summarise(
        sample_name = sample_name,
        split_var = split_var,
        n_rows = n(),
        n_players = n_distinct(player_id),
        bosman_rows = sum(Bosman, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      relocate(sample_name, split_var)
  }))
}

panel_source <- load_panel(source_panel_path)
panel_all <- load_panel(all_comps_panel_path)

all_results <- bind_rows(
  run_all_splits(panel_source, "source_league_strict"),
  run_all_splits(panel_all, "all_comps_strict")
)

sizes <- bind_rows(
  subgroup_sizes(panel_source, "source_league_strict"),
  subgroup_sizes(panel_all, "all_comps_strict")
)

write_csv(all_results, file.path(results_dir, "fotmob_heterogeneity_results.csv"), na = "")
write_csv(sizes, file.path(results_dir, "fotmob_heterogeneity_subgroup_sizes.csv"), na = "")

message("Saved heterogeneity results to: ", file.path(results_dir, "fotmob_heterogeneity_results.csv"))
message("Saved subgroup sizes to: ", file.path(results_dir, "fotmob_heterogeneity_subgroup_sizes.csv"))
