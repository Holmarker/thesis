library(dplyr)
library(fixest)
library(readr)
library(lubridate)
library(tibble)

# Sub-shrinkage responses: monthly rating outcomes built from
# (a) >=60-minute appearances only ("real outings"), and
# (b) match ratings z-scored within minutes-bin x league-season before
#     aggregation (rescales compressed cameo ratings).
# Both merged onto the strict panel and run through the main Bosman specs.

ratings_path <- file.path("data", "fotmob_ratings_clean.csv")
panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
results_dir <- file.path("results", "fotmob_regressions")

football_season <- function(d) {
  y <- year(d); m <- month(d)
  s <- if_else(m >= 7, y, y - 1)
  paste0(s, "/", s + 1)
}

matches <- read_csv(ratings_path, show_col_types = FALSE) %>%
  mutate(rating = as.numeric(rating), minutes_played = as.numeric(minutes_played),
         fotmob_player_id = as.numeric(fotmob_player_id), match_date = as.Date(match_date)) %>%
  filter(!is.na(rating), rating > 0, rating <= 10,
         !is.na(minutes_played), minutes_played > 0, !is.na(match_date)) %>%
  mutate(Month = floor_date(match_date, "month"),
         season = football_season(match_date),
         min_bin = pmin(minutes_played %/% 15, 6)) %>%
  group_by(source_league_name, season, min_bin) %>%
  mutate(z_bin = (rating - mean(rating)) / sd(rating)) %>%
  ungroup()

monthly <- matches %>%
  group_by(fotmob_player_id, Month) %>%
  summarise(
    rating_starts60 = mean(rating[minutes_played >= 60]),
    n_starts60 = sum(minutes_played >= 60),
    rating_binz = mean(z_bin),
    n_matches = n(),
    .groups = "drop"
  )

panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(Month = as.Date(Month), Bosman = as.logical(Bosman),
         player_id = as.integer(player_id),
         fotmob_player_id = as.numeric(fotmob_player_id),
         ContractExpiryDate = as.Date(ContractExpiryDate),
         season = football_season(Month)) %>%
  left_join(monthly, by = c("fotmob_player_id", "Month")) %>%
  group_by(fotmob_source_league, season) %>%
  mutate(z_starts60 = { x <- rating_starts60
    s <- sd(x, na.rm = TRUE); if (is.na(s) || s == 0) NA_real_ else (x - mean(x, na.rm = TRUE)) / s }) %>%
  ungroup() %>%
  arrange(player_id, Month) %>%
  group_by(player_id) %>%
  mutate(prev_expiry = lag(ContractExpiryDate),
         jump = as.numeric(ContractExpiryDate - prev_expiry),
         new_spell = is.na(prev_expiry) | abs(coalesce(jump, 0)) > 90,
         spell_num = cumsum(new_spell),
         player_spell = paste0(player_id, "_", spell_num)) %>%
  ungroup() %>%
  mutate(league_month = paste0(fotmob_source_league, "_", Month),
         club_month = paste0(ClubID, "_", Month))

tidy_row <- function(model, outcome, spec) {
  ct <- as_tibble(coeftable(model), rownames = "term") %>% filter(term == "BosmanTRUE")
  names(ct) <- c("term", "estimate", "std_error", "t_value", "p_value")
  ct %>% mutate(outcome_name = outcome, spec_name = spec, nobs = nobs(model)) %>%
    select(outcome_name, spec_name, term, estimate, std_error, t_value, p_value, nobs)
}

specs <- tribble(
  ~spec, ~fe, ~cl,
  "player+month", "player_id + Month", "~player_id",
  "spell+league-month", "player_spell + league_month", "~player_id",
  "spell+club-month", "player_spell + club_month", "~ClubID"
)

results <- list()
for (oc in c("z_starts60", "rating_binz")) {
  for (i in seq_len(nrow(specs))) {
    m <- tryCatch(
      feols(as.formula(paste0(oc, " ~ Bosman | ", specs$fe[i])),
            data = panel, cluster = as.formula(specs$cl[i])),
      error = function(e) NULL
    )
    if (!is.null(m)) results[[length(results) + 1]] <- tidy_row(m, oc, specs$spec[i])
  }
}
out <- bind_rows(results)
write_csv(out, file.path(results_dir, "fotmob_sub_adjusted_rating_results.csv"), na = "")
print(as.data.frame(out))
message("coverage: starts60 outcome available for ",
        sum(!is.na(panel$z_starts60)), " rows; bin-z for ", sum(!is.na(panel$rating_binz)), " rows")
