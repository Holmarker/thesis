library(dplyr)
library(fixest)
library(readr)
library(tibble)

# Three additional robustness exercises for the intensive-margin null:
#  (a) two-way clustering (player and month) on the main Bosman models;
#  (b) ratings standardized within league x season x position group
#      (keeper ratings distribute differently from outfield ratings);
#  (c) Lee-style trimming bounds: Bosman-window players play ~5pp less,
#      so the observed (conditional-on-playing) treated sample is more
#      positively selected than the control sample. Within each league-
#      month cell the over-observed group is trimmed at the top/bottom
#      of its rating distribution to equalize observation shares,
#      bounding the Bosman rating gap from below/above.

panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
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

panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(
    Month = as.Date(Month),
    ContractExpiryDate = as.Date(ContractExpiryDate),
    Bosman = as.logical(Bosman),
    player_id = as.integer(player_id),
    DaysToExpiry = as.numeric(DaysToExpiry),
    Minutes_tm = as.numeric(Minutes_tm),
    fotmob_minutes = as.numeric(fotmob_minutes),
    fotmob_goals = as.numeric(fotmob_goals),
    fotmob_assists = as.numeric(fotmob_assists),
    fotmob_win_share = as.numeric(fotmob_win_share),
    played = coalesce(Minutes_tm, 0) > 0,
    season = football_season(Month)
  ) %>%
  filter(!is.na(DaysToExpiry), DaysToExpiry >= 0) %>%
  group_by(fotmob_source_league, season) %>%
  mutate(
    z_ls = standardize_within(fotmob_mean_rating),
    z_weighted_ls = standardize_within(fotmob_minutes_weighted_rating)
  ) %>%
  ungroup() %>%
  group_by(fotmob_source_league, season, fotmob_position_group) %>%
  mutate(z_lsp = standardize_within(fotmob_mean_rating)) %>%
  ungroup() %>%
  arrange(player_id, Month) %>%
  group_by(player_id) %>%
  mutate(
    prev_expiry = lag(ContractExpiryDate),
    jump = as.numeric(ContractExpiryDate - prev_expiry),
    new_spell = is.na(prev_expiry) | abs(coalesce(jump, 0)) > 90,
    spell_num = cumsum(new_spell),
    player_spell = paste0(player_id, "_", spell_num)
  ) %>%
  ungroup() %>%
  mutate(league_month = paste0(fotmob_source_league, "_", Month))

tidy_row <- function(model, exercise, outcome, note) {
  ct <- as_tibble(coeftable(model), rownames = "term") %>%
    filter(term == "BosmanTRUE")
  names(ct) <- c("term", "estimate", "std_error", "t_value", "p_value")
  ct %>% mutate(exercise = exercise, outcome_name = outcome, note = note, nobs = nobs(model)) %>%
    select(exercise, outcome_name, note, term, estimate, std_error, t_value, p_value, nobs)
}

results <- list()

# (a) two-way clustering
m <- feols(z_ls ~ Bosman | player_id + Month, data = panel, cluster = ~player_id + Month)
results[[length(results) + 1]] <- tidy_row(m, "twoway_cluster", "z_ls", "player+Month FE, cluster player & Month")
m <- feols(z_ls ~ Bosman | player_spell + league_month, data = panel, cluster = ~player_id + Month)
results[[length(results) + 1]] <- tidy_row(m, "twoway_cluster", "z_ls", "spell+league-month FE, cluster player & Month")

# (b) position-standardized outcome
m <- feols(z_lsp ~ Bosman | player_id + Month, data = panel, cluster = ~player_id)
results[[length(results) + 1]] <- tidy_row(m, "position_standardized", "z_lsp", "player+Month FE")
m <- feols(z_lsp ~ Bosman | player_spell + league_month, data = panel, cluster = ~player_id)
results[[length(results) + 1]] <- tidy_row(m, "position_standardized", "z_lsp", "spell+league-month FE")

# (c) Lee-style bounds on the raw Bosman rating gap
lee_cells <- panel %>%
  filter(!is.na(fotmob_source_league)) %>%
  group_by(league_month) %>%
  filter(any(Bosman) & any(!Bosman)) %>%
  ungroup()

# Standard Lee logic under monotone selection (Bosman reduces playing):
# the control group is over-observed, so trim the control group's rating
# distribution by the differential observation share. Trimming control's
# BEST ratings lowers the control mean -> UPPER bound on the Bosman gap;
# trimming control's WORST -> LOWER bound. Cells violating monotonicity
# (treated observed more) are left untrimmed.
trim_cell <- function(d, bound) {
  obs <- d %>% filter(played, !is.na(z_ls))
  p_t <- mean(d$played[d$Bosman])
  p_c <- mean(d$played[!d$Bosman])
  if (is.na(p_t) || is.na(p_c) || p_c <= p_t) return(obs)
  trim_frac <- (p_c - p_t) / p_c
  ctrl <- obs %>% filter(!Bosman)
  trt <- obs %>% filter(Bosman)
  n_trim <- floor(nrow(ctrl) * trim_frac)
  if (n_trim > 0) {
    ctrl <- if (bound == "upper") {
      ctrl %>% arrange(desc(z_ls)) %>% slice(-(1:n_trim))
    } else {
      ctrl %>% arrange(z_ls) %>% slice(-(1:n_trim))
    }
  }
  bind_rows(ctrl, trt)
}

lee_bound <- function(bound) {
  trimmed <- lee_cells %>%
    group_by(league_month) %>%
    group_modify(~ trim_cell(.x, bound)) %>%
    ungroup()
  m <- feols(z_ls ~ Bosman | league_month, data = trimmed, cluster = ~player_id)
  tidy_row(m, "lee_bound", "z_ls",
           paste0(bound, " bound (trim control group, league-month FE)"))
}

results[[length(results) + 1]] <- lee_bound("lower")
results[[length(results) + 1]] <- lee_bound("upper")

# untrimmed comparison for reference
m <- feols(z_ls ~ Bosman | league_month, data = lee_cells %>% filter(played, !is.na(z_ls)), cluster = ~player_id)
results[[length(results) + 1]] <- tidy_row(m, "lee_bound", "z_ls", "untrimmed reference (league-month FE)")

out <- bind_rows(results)
write_csv(out, file.path(results_dir, "fotmob_additional_robustness.csv"), na = "")
print(as.data.frame(out))
message("Saved to ", file.path(results_dir, "fotmob_additional_robustness.csv"))

cluster_specs <- tribble(
  ~cluster_name, ~cluster_formula,
  "player", ~player_id,
  "club", ~ClubID,
  "player_club", ~player_id + ClubID
)

model_specs <- tribble(
  ~spec_name, ~fe,
  "player_month", "player_id + Month",
  "spell_leaguemonth", "player_spell + league_month"
)

control_specs <- tribble(
  ~control_name, ~rhs,
  "none", "Bosman",
  "win_control", "Bosman + fotmob_win_share",
  "event_controls", "Bosman + fotmob_goals + fotmob_assists + fotmob_win_share"
)

tidy_cluster_row <- function(model, spec_name, control_name, cluster_name, weighted) {
  ct <- as_tibble(coeftable(model), rownames = "term") %>%
    filter(term == "BosmanTRUE")
  names(ct) <- c("term", "estimate", "std_error", "t_value", "p_value")
  ct %>%
    mutate(
      spec_name = spec_name,
      control_name = control_name,
      cluster_name = cluster_name,
      minute_weighted = weighted,
      outcome_name = "z_weighted_ls",
      nobs = nobs(model)
    ) %>%
    select(spec_name, control_name, cluster_name, minute_weighted, outcome_name,
           term, estimate, std_error, t_value, p_value, nobs)
}

fit_cluster_model <- function(fml, data, cluster_formula, weighted) {
  if (weighted) {
    feols(fml, data = data, cluster = cluster_formula, weights = ~fotmob_minutes)
  } else {
    feols(fml, data = data, cluster = cluster_formula)
  }
}

cluster_results <- list()

for (i in seq_len(nrow(model_specs))) {
  for (j in seq_len(nrow(control_specs))) {
    for (k in seq_len(nrow(cluster_specs))) {
      for (weighted in c(FALSE, TRUE)) {
        fml <- as.formula(paste0("z_weighted_ls ~ ", control_specs$rhs[j], " | ", model_specs$fe[i]))
        model <- tryCatch(
          fit_cluster_model(fml, panel, cluster_specs$cluster_formula[[k]], weighted),
          error = function(e) NULL
        )
        if (!is.null(model)) {
          cluster_results[[length(cluster_results) + 1]] <- tidy_cluster_row(
            model,
            model_specs$spec_name[i],
            control_specs$control_name[j],
            cluster_specs$cluster_name[k],
            weighted
          )
        }
      }
    }
  }
}

cluster_out <- bind_rows(cluster_results)
write_csv(cluster_out, file.path(results_dir, "fotmob_cluster_robustness.csv"), na = "")
print(as.data.frame(cluster_out))
message("Saved to ", file.path(results_dir, "fotmob_cluster_robustness.csv"))
