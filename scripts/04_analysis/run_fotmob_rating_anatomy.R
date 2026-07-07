library(dplyr)
library(fixest)
library(readr)
library(tibble)
library(tidyr)

# Rating anatomy: consolidated measurement diagnostics for the FotMob
# match rating. Reproduces every number cited in
# results/fotmob_descriptives/RATING_ANATOMY.md.

ratings_path <- file.path("data", "fotmob_ratings_clean.csv")
panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
out_dir <- file.path("results", "fotmob_descriptives", "rating_anatomy")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

pos_lookup <- read_csv(panel_path, show_col_types = FALSE) %>%
  filter(!is.na(fotmob_player_id), !is.na(fotmob_position_group)) %>%
  distinct(fotmob_player_id, fotmob_position_group)

raw <- read_csv(ratings_path, show_col_types = FALSE) %>%
  mutate(
    rating = as.numeric(rating),
    minutes_played = as.numeric(minutes_played),
    goals = as.numeric(goals),
    assists = as.numeric(assists),
    yellow_cards = as.numeric(yellow_cards),
    red_cards = as.numeric(red_cards),
    is_home_team = as.logical(is_home_team),
    fotmob_player_id = as.numeric(fotmob_player_id),
    match_date = as.Date(match_date)
  )

out_of_range <- raw %>% filter(!is.na(rating), (rating <= 0 | rating > 10))

df <- raw %>%
  filter(!is.na(rating), rating > 0, rating <= 10,
         !is.na(minutes_played), minutes_played > 0)

# ---- 1. distribution basics ----
dist_summary <- df %>%
  summarise(
    n = n(),
    mean = mean(rating), sd = sd(rating),
    p05 = quantile(rating, .05), p25 = quantile(rating, .25),
    p50 = quantile(rating, .50), p75 = quantile(rating, .75),
    p95 = quantile(rating, .95),
    distinct_values = n_distinct(round(rating, 1)),
    n_at_10 = sum(rating == 10),
    n_out_of_range_in_raw = nrow(out_of_range)
  )
write_csv(dist_summary, file.path(out_dir, "distribution_summary.csv"))

# ---- 2. within/between player variance ----
var_decomp <- df %>%
  group_by(fotmob_player_id) %>%
  filter(n() >= 5) %>%
  mutate(player_mean = mean(rating)) %>%
  ungroup() %>%
  summarise(
    players = n_distinct(fotmob_player_id),
    between_sd = sd(unique(player_mean)),
    within_sd = sd(rating - player_mean)
  )
write_csv(var_decomp, file.path(out_dir, "variance_decomposition.csv"))

# ---- 3. team co-movement ----
team_match <- df %>%
  filter(!is.na(match_id), !is.na(fotmob_team_id)) %>%
  group_by(match_id, fotmob_team_id) %>%
  filter(n() >= 5) %>%
  mutate(cell_mean = mean(rating)) %>%
  ungroup()
icc_match <- team_match %>%
  summarise(
    var_between = var(unique(cell_mean)),
    var_within = var(rating - cell_mean)
  ) %>%
  mutate(icc = var_between / (var_between + var_within), level = "team_match")
write_csv(icc_match, file.path(out_dir, "team_comovement.csv"))

# ---- 4. R2 ladder + full-model coefficients ----
decomp_df <- team_match %>%
  group_by(match_id, fotmob_team_id) %>%
  mutate(team_loo = (sum(rating) - rating) / (n() - 1)) %>%
  ungroup()

specs <- list(
  minutes = rating ~ minutes_played,
  goals_assists = rating ~ goals + assists,
  minutes_goals_assists = rating ~ minutes_played + goals + assists,
  plus_cards_home = rating ~ minutes_played + goals + assists + yellow_cards + red_cards + is_home_team,
  plus_team_day = rating ~ minutes_played + goals + assists + yellow_cards + red_cards + is_home_team + team_loo,
  team_day_only = rating ~ team_loo
)
ladder <- bind_rows(lapply(names(specs), function(nm) {
  tibble(spec = nm, r2 = r2(feols(specs[[nm]], data = decomp_df), "r2"))
}))
write_csv(ladder, file.path(out_dir, "r2_ladder.csv"))

full_m <- feols(specs$plus_team_day, data = decomp_df)
full_coefs <- as_tibble(coeftable(full_m), rownames = "term")
names(full_coefs) <- c("term", "estimate", "std_error", "t_value", "p_value")
write_csv(full_coefs, file.path(out_dir, "full_model_coefficients.csv"))

# ---- 5. position-specific decomposition ----
pos_decomp <- decomp_df %>%
  inner_join(pos_lookup, by = "fotmob_player_id") %>%
  filter(fotmob_position_group %in% c("keepers", "defenders", "midfielders", "attackers")) %>%
  group_by(fotmob_position_group) %>%
  group_modify(function(d, key) {
    mf <- feols(rating ~ minutes_played + goals + assists + yellow_cards + red_cards + team_loo, data = d)
    mg <- feols(rating ~ goals + assists, data = d)
    ct <- coeftable(mf)
    coef_or_na <- function(term) {
      if (term %in% rownames(ct)) ct[term, 1] else NA_real_
    }
    tibble(
      n = nrow(d),
      r2_full = r2(mf, "r2"),
      r2_goals_assists_only = r2(mg, "r2"),
      coef_goal = coef_or_na("goals"),
      coef_assist = coef_or_na("assists"),
      coef_red = coef_or_na("red_cards"),
      coef_per_90min = 90 * coef_or_na("minutes_played"),
      team_passthrough = coef_or_na("team_loo")
    )
  }) %>%
  ungroup()
write_csv(pos_decomp, file.path(out_dir, "position_decomposition.csv"))

# ---- 6. minutes gradient + shrinkage ----
shrinkage <- df %>%
  mutate(bin = pmin(minutes_played %/% 15, 6)) %>%
  group_by(bin) %>%
  summarise(
    minutes = paste0(first(bin) * 15, "-", if_else(first(bin) < 6, first(bin) * 15 + 14, 120)),
    mean_rating = mean(rating),
    sd_rating = sd(rating),
    share_below_5_5 = mean(rating < 5.5),
    share_above_7_5 = mean(rating > 7.5),
    n = n(),
    .groups = "drop"
  ) %>%
  select(-bin)
write_csv(shrinkage, file.path(out_dir, "minutes_gradient_shrinkage.csv"))

# ---- 7. event-free within-player minutes effect ----
noev <- df %>% filter(goals == 0, assists == 0, yellow_cards == 0, red_cards == 0)
m_all <- feols(rating ~ minutes_played | fotmob_player_id, data = noev, cluster = ~fotmob_player_id)
m_starters <- feols(rating ~ minutes_played | fotmob_player_id,
                    data = noev %>% filter(minutes_played >= 60), cluster = ~fotmob_player_id)
eventfree <- tibble(
  sample = c("event_free_all", "event_free_starters_60plus"),
  coef_per_minute = c(coef(m_all)["minutes_played"], coef(m_starters)["minutes_played"]),
  per_90 = 90 * coef_per_minute,
  n = c(nobs(m_all), nobs(m_starters))
)
write_csv(eventfree, file.path(out_dir, "eventfree_minutes_effect.csv"))

message("Rating anatomy tables written to ", out_dir)
