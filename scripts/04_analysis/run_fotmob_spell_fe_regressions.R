library(dplyr)
library(fixest)
library(readr)
library(tibble)

# Contract-spell FE design: within a player x contract spell, DaysToExpiry
# moves deterministically with calendar time, so expiry proximity is not a
# chosen state. Compared against the baseline player FE design, and with
# league x month FE to absorb league-time composition shocks.

source_panel_path <- file.path("data", "panel", "fotmob_analysis_panel_source_league_strict.csv")
all_comps_panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
results_dir <- file.path("results", "fotmob_regressions")

football_season <- function(month) {
  y <- as.integer(format(month, "%Y"))
  m <- as.integer(format(month, "%m"))
  s <- if_else(m >= 7L, y, y - 1L)
  paste0(s, "/", s + 1L)
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

source(file.path("scripts", "04_analysis", "apply_sample_restrictions.R"))

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
    group_by(fotmob_source_league, season) %>%
    mutate(
      z_mean_rating_league_season = standardize_within(fotmob_mean_rating),
      z_weighted_rating_league_season = standardize_within(fotmob_minutes_weighted_rating)
    ) %>%
    ungroup() %>%
    arrange(player_id, Month) %>%
    group_by(player_id) %>%
    mutate(
      prev_expiry = lag(ContractExpiryDate),
      expiry_jump_days = as.numeric(ContractExpiryDate - prev_expiry),
      new_spell = is.na(prev_expiry) | abs(coalesce(expiry_jump_days, 0)) > 90,
      spell_num = cumsum(new_spell),
      player_spell = paste0(player_id, "_", spell_num),
      expiry_bin_6m = make_expiry_bin_6m(DaysToExpiry),
      league_month = paste0(fotmob_source_league, "_", Month)
    ) %>%
    ungroup()
}

outcome_vars <- c("z_mean_rating_league_season", "z_weighted_rating_league_season")
rating_control_rhs <- "fotmob_goals + fotmob_assists + fotmob_win_share"
win_control_rhs <- "fotmob_win_share"

control_specs <- tribble(
  ~control_set, ~suffix, ~rhs,
  "none", "", "",
  "win", "_win_control", win_control_rhs,
  "events", "_event_controls", rating_control_rhs
)

specs <- tribble(
  ~spec_name, ~fe,
  "player_month", "player_id + Month",
  "player_leaguemonth", "player_id + league_month",
  "spell_month", "player_spell + Month",
  "spell_leaguemonth", "player_spell + league_month"
)

tidy_model <- function(model, model_name, sample_name, outcome_name, spec_name) {
  out <- as_tibble(coeftable(model), rownames = "term")
  names(out) <- c("term", "estimate", "std_error", "t_value", "p_value")
  out %>%
    mutate(
      model_name = model_name,
      sample_name = sample_name,
      outcome_name = outcome_name,
      spec_name = spec_name,
      nobs = nobs(model),
      # approx minimum detectable effect at 80% power, 5% two-sided
      mde_80pct = 2.8 * std_error
    ) %>%
    select(model_name, sample_name, outcome_name, spec_name, term,
           estimate, std_error, t_value, p_value, nobs, mde_80pct)
}

fit_rating_model <- function(formula, df, weight_by_minutes) {
  if (weight_by_minutes) {
    feols(formula, data = df, cluster = ~player_id, weights = ~fotmob_minutes)
  } else {
    feols(formula, data = df, cluster = ~player_id)
  }
}

run_specs <- function(df, sample_name) {
  results <- list()
  expiry_df <- df %>% filter(!is.na(expiry_bin_6m))

  for (i in seq_len(nrow(specs))) {
    fe <- specs$fe[i]
    sn <- specs$spec_name[i]
    for (outcome in outcome_vars) {
      for (j in seq_len(nrow(control_specs))) {
        controls <- if (nzchar(control_specs$rhs[j])) paste0(" + ", control_specs$rhs[j]) else ""
        suffix <- control_specs$suffix[j]
        for (weight_by_minutes in c(FALSE, TRUE)) {
          weight_suffix <- if_else(weight_by_minutes, "_minute_weighted", "")
          results[[length(results) + 1]] <- tryCatch(
            tidy_model(
              fit_rating_model(
                as.formula(paste0(outcome, " ~ Bosman", controls, " | ", fe)),
                df,
                weight_by_minutes
              ),
              paste0("bosman", suffix, weight_suffix), sample_name, outcome, sn
            ),
            error = function(e) NULL
          )
          results[[length(results) + 1]] <- tryCatch(
            tidy_model(
              fit_rating_model(
                as.formula(paste0(outcome, ' ~ i(expiry_bin_6m, ref = "24:30")', controls, ' | ', fe)),
                expiry_df,
                weight_by_minutes
              ),
              paste0("expiry_bin_6m", suffix, weight_suffix), sample_name, outcome, sn
            ),
            error = function(e) NULL
          )
        }
      }
    }
  }
  bind_rows(results)
}

spell_summary <- function(df, sample_name) {
  df %>%
    group_by(player_id) %>%
    summarise(n_spells = n_distinct(spell_num), .groups = "drop") %>%
    summarise(
      sample_name = sample_name,
      players = n(),
      players_with_multiple_spells = sum(n_spells > 1),
      total_spells = sum(n_spells)
    )
}

panel_source <- load_panel(source_panel_path) %>% apply_sample_restrictions(margin = "rating")
panel_all <- load_panel(all_comps_panel_path) %>% apply_sample_restrictions(margin = "rating")

all_results <- bind_rows(
  run_specs(panel_source, "source_league_strict"),
  run_specs(panel_all, "all_comps_strict")
)

spells <- bind_rows(
  spell_summary(panel_source, "source_league_strict"),
  spell_summary(panel_all, "all_comps_strict")
)

write_csv(all_results, file.path(results_dir, "fotmob_spell_fe_results.csv"), na = "")
write_csv(spells, file.path(results_dir, "fotmob_spell_fe_spell_counts.csv"), na = "")

message("Saved spell-FE results to: ", file.path(results_dir, "fotmob_spell_fe_results.csv"))
message("Saved spell counts to: ", file.path(results_dir, "fotmob_spell_fe_spell_counts.csv"))
