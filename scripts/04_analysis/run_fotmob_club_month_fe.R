library(dplyr)
library(fixest)
library(readr)
library(tibble)

# Club x month FE: compare a player to his own teammates in the same
# month. Motivated by the finding that ~31% of rating variance is at
# the team-match level (ratings co-move with team results). Also adds
# club clustering and a regular-player (270+ min) restriction where the
# mechanical minutes-rating gradient is flat.

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
    played = coalesce(Minutes_tm, 0) > 0,
    season = football_season(Month)
  ) %>%
  filter(!is.na(DaysToExpiry), DaysToExpiry >= 0) %>%
  group_by(fotmob_source_league, season) %>%
  mutate(
    z_mean = standardize_within(fotmob_mean_rating),
    z_weighted = standardize_within(fotmob_minutes_weighted_rating)
  ) %>%
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
  mutate(club_month = paste0(ClubID, "_", Month))

regular <- panel %>% filter(coalesce(fotmob_minutes, 0) >= 270)

tidy_row <- function(model, outcome, variant) {
  ct <- as_tibble(coeftable(model), rownames = "term") %>% filter(term == "BosmanTRUE")
  names(ct) <- c("term", "estimate", "std_error", "t_value", "p_value")
  ct %>%
    mutate(outcome_name = outcome, variant = variant, nobs = nobs(model)) %>%
    select(variant, outcome_name, term, estimate, std_error, t_value, p_value, nobs)
}

results <- list()
runs <- list(
  list(d = quote(panel), oc = "played", v = "played, spell + club-month FE, cluster club"),
  list(d = quote(panel), oc = "Minutes_tm", v = "minutes, spell + club-month FE, cluster club"),
  list(d = quote(panel), oc = "z_mean", v = "z mean rating, spell + club-month FE, cluster club"),
  list(d = quote(panel), oc = "z_weighted", v = "z weighted rating, spell + club-month FE, cluster club"),
  list(d = quote(regular), oc = "z_mean", v = "z mean rating, regulars 270+ min, spell + club-month FE"),
  list(d = quote(regular), oc = "z_weighted", v = "z weighted rating, regulars 270+ min, spell + club-month FE")
)

for (r in runs) {
  m <- tryCatch(
    feols(as.formula(paste0(r$oc, " ~ Bosman | player_spell + club_month")),
          data = eval(r$d), cluster = ~ClubID),
    error = function(e) NULL
  )
  if (!is.null(m)) results[[length(results) + 1]] <- tidy_row(m, r$oc, r$v)
}

out <- bind_rows(results)
write_csv(out, file.path(results_dir, "fotmob_club_month_fe_results.csv"), na = "")
print(as.data.frame(out))
message("Saved to ", file.path(results_dir, "fotmob_club_month_fe_results.csv"))
