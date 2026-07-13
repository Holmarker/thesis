library(dplyr)
library(fixest)
library(readr)
library(tibble)

# Selection-into-playing check: ratings are only observed when a player
# plays, so rating regressions condition on an outcome of treatment.
# This script estimates the extensive margin directly: does Bosman-window
# status / expiry proximity predict whether and how much a player plays?
# Uses the FULL panels (not strict), TM minutes as the always-observed
# outcome, and FotMob minutes within covered league-months.

source_panel_path <- file.path("data", "panel", "fotmob_analysis_panel_source_league.csv")
all_comps_panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
results_dir <- file.path("results", "fotmob_regressions")

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
      DaysToExpiry = as.numeric(DaysToExpiry),
      Minutes_tm = as.numeric(Minutes_tm),
      Matches_tm = as.numeric(Matches_tm),
      fotmob_minutes = as.numeric(fotmob_minutes),
      played_tm = coalesce(Minutes_tm, 0) > 0,
      played_fotmob = coalesce(fotmob_minutes, 0) > 0,
      # combined-evidence outcomes: the TM appearance log misses months a
      # crosswalked player spends in competitions it does not cover, coding
      # real appearances as zeros; FotMob minutes fill those months
      played_any = played_tm | played_fotmob,
      minutes_any = pmax(coalesce(Minutes_tm, 0), coalesce(fotmob_minutes, 0)),
      tm_coverage_gap = !played_tm & played_fotmob
    ) %>%
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
    ungroup() %>%
    group_by(league_month) %>%
    mutate(league_month_rated_rows = sum(played_fotmob, na.rm = TRUE)) %>%
    ungroup() %>%
    mutate(fotmob_covered = league_month_rated_rows >= 50)

}

specs <- tribble(
  ~spec_name, ~fe,
  "player_month", "player_id + Month",
  "player_leaguemonth", "player_id + league_month",
  "spell_month", "player_spell + Month",
  "spell_leaguemonth", "player_spell + league_month"
)

outcomes <- tribble(
  ~outcome, ~restrict_covered,
  "played_any", FALSE,
  "minutes_any", FALSE,
  "played_tm", FALSE,
  "Minutes_tm", FALSE,
  "Matches_tm", FALSE,
  "played_fotmob", TRUE,
  "fotmob_minutes", TRUE
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
      nobs = nobs(model)
    ) %>%
    select(model_name, sample_name, outcome_name, spec_name, term,
           estimate, std_error, t_value, p_value, nobs)
}

run_all <- function(df, sample_name) {
  results <- list()
  for (i in seq_len(nrow(specs))) {
    fe <- specs$fe[i]
    sn <- specs$spec_name[i]
    for (j in seq_len(nrow(outcomes))) {
      oc <- outcomes$outcome[j]
      d <- if (outcomes$restrict_covered[j]) df %>% filter(fotmob_covered) else df
      expiry_d <- d %>% filter(!is.na(expiry_bin_6m))

      results[[length(results) + 1]] <- tryCatch(
        tidy_model(
          feols(as.formula(paste0(oc, " ~ Bosman | ", fe)), data = d, cluster = ~player_id),
          "bosman_selection", sample_name, oc, sn
        ),
        error = function(e) NULL
      )
      results[[length(results) + 1]] <- tryCatch(
        tidy_model(
          feols(as.formula(paste0(oc, ' ~ i(expiry_bin_6m, ref = "24:30") | ', fe)),
                data = expiry_d, cluster = ~player_id),
          "expiry_selection", sample_name, oc, sn
        ),
        error = function(e) NULL
      )
    }
  }
  bind_rows(results)
}

panel_all <- load_panel(all_comps_panel_path)
panel_source <- load_panel(source_panel_path)

all_results <- bind_rows(
  run_all(panel_all, "all_comps_full"),
  run_all(panel_source, "source_league_full")
)

write_csv(all_results, file.path(results_dir, "fotmob_selection_margin_results.csv"), na = "")
message("Saved selection-margin results to: ",
        file.path(results_dir, "fotmob_selection_margin_results.csv"))
