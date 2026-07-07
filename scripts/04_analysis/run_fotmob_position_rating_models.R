library(dplyr)
library(fixest)
library(readr)
library(tibble)

# Position-aware rating models. The rating anatomy shows the FotMob rating
# is a different instrument per position (attackers ~ goal involvement,
# keepers ~ team outcome), so pooled rating models mix incomparable
# measures. Here: (a) outcomes standardized within league x season x
# position group, run through the main FE specs; (b) fully separate models
# per position group (own FE, own estimate); both for Bosman and the
# months-to-expiry event margin.

panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
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

positions <- c("keepers", "defenders", "midfielders", "attackers")

panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(
    Month = as.Date(Month),
    ContractExpiryDate = as.Date(ContractExpiryDate),
    Bosman = as.logical(Bosman),
    player_id = as.integer(player_id),
    DaysToExpiry = as.numeric(DaysToExpiry),
    fotmob_minutes = as.numeric(fotmob_minutes),
    season = football_season(Month),
    position_group = if_else(fotmob_position_group %in% positions,
                             fotmob_position_group, NA_character_)
  ) %>%
  filter(!is.na(position_group)) %>%
  group_by(fotmob_source_league, season, position_group) %>%
  mutate(
    zp_mean = standardize_within(fotmob_mean_rating),
    zp_weighted = standardize_within(fotmob_minutes_weighted_rating)
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
  mutate(
    league_month = paste0(fotmob_source_league, "_", Month),
    club_month = paste0(ClubID, "_", Month)
  )

tidy_row <- function(model, model_name, outcome, group, spec) {
  ct <- as_tibble(coeftable(model), rownames = "term") %>%
    filter(term == "BosmanTRUE")
  names(ct) <- c("term", "estimate", "std_error", "t_value", "p_value")
  ct %>%
    mutate(model_name = model_name, outcome_name = outcome,
           position_group = group, spec_name = spec, nobs = nobs(model),
           mde_80pct = 2.8 * std_error) %>%
    select(model_name, outcome_name, position_group, spec_name, term,
           estimate, std_error, t_value, p_value, nobs, mde_80pct)
}

results <- list()

# (a) position-standardized outcomes, pooled across positions
for (oc in c("zp_mean", "zp_weighted")) {
  for (sp in list(c("spell_leaguemonth", "player_spell + league_month", "~player_id"),
                  c("spell_clubmonth", "player_spell + club_month", "~ClubID"))) {
    m <- tryCatch(
      feols(as.formula(paste0(oc, " ~ Bosman | ", sp[2])),
            data = panel, cluster = as.formula(sp[3])),
      error = function(e) NULL
    )
    if (!is.null(m)) results[[length(results) + 1]] <-
        tidy_row(m, "pooled_position_standardized", oc, "all", sp[1])
  }
}

# (b) fully separate models per position group
for (g in positions) {
  d <- panel %>% filter(position_group == g)
  for (oc in c("zp_mean", "zp_weighted")) {
    m <- tryCatch(
      feols(as.formula(paste0(oc, " ~ Bosman | player_spell + league_month")),
            data = d, cluster = ~player_id),
      error = function(e) NULL
    )
    if (!is.null(m)) results[[length(results) + 1]] <-
        tidy_row(m, "by_position", oc, g, "spell_leaguemonth")
  }
}

out <- bind_rows(results)
write_csv(out, file.path(results_dir, "fotmob_position_rating_results.csv"), na = "")
print(as.data.frame(out), digits = 3)
message("Saved to ", file.path(results_dir, "fotmob_position_rating_results.csv"))
