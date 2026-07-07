library(dplyr)
library(ggplot2)
library(lubridate)
library(readr)
library(tidyr)

# Contract-cycle descriptives for the thesis: outcome funnel, raw playing
# profile, renewal timing, expiry-date clustering, contract length by age,
# and the league x season rating-coverage table.

panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
out_dir <- file.path("results", "thesis_contract_descriptives")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

football_season <- function(month) {
  y <- as.integer(format(month, "%Y"))
  m <- as.integer(format(month, "%m"))
  s <- if_else(m >= 7L, y, y - 1L)
  paste0(s, "/", s + 1L)
}

panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(
    Month = as.Date(Month),
    ContractExpiryDate = as.Date(ContractExpiryDate),
    player_id = as.integer(player_id),
    DaysToExpiry = as.numeric(DaysToExpiry),
    Age = as.numeric(Age),
    Minutes_tm = as.numeric(Minutes_tm),
    played = coalesce(Minutes_tm, 0) > 0,
    season = football_season(Month),
    months_to_expiry = pmin(as.integer(floor(DaysToExpiry / 30.44)), 36L)
  ) %>%
  filter(!is.na(DaysToExpiry), DaysToExpiry >= 0) %>%
  arrange(player_id, Month) %>%
  group_by(player_id) %>%
  mutate(
    prev_expiry = lag(ContractExpiryDate),
    expiry_jump_days = as.numeric(ContractExpiryDate - prev_expiry),
    renewed_this_month = !is.na(expiry_jump_days) & expiry_jump_days > 90,
    club_changed = ClubID != lag(ClubID) & !is.na(lag(ClubID)),
    last_obs_month = max(Month)
  ) %>%
  ungroup()

panel_end <- max(panel$Month, na.rm = TRUE)

# ---- 1. contract outcome funnel ----
# Contracts observed entering their final 12 months, excluding spells whose
# expiry lies beyond the panel end (right-censored).
final_year <- panel %>%
  filter(months_to_expiry <= 11, ContractExpiryDate <= panel_end) %>%
  group_by(player_id, ContractExpiryDate) %>%
  summarise(first_seen = min(Month), .groups = "drop")

resolve <- final_year %>%
  left_join(panel, by = "player_id", relationship = "many-to-many") %>%
  filter(Month >= first_seen, Month <= ContractExpiryDate.x %m+% months(3)) %>%
  group_by(player_id, expiry = ContractExpiryDate.x) %>%
  summarise(
    renewed = any(renewed_this_month & Month <= expiry, na.rm = TRUE),
    moved_before_expiry = any(club_changed & Month <= expiry, na.rm = TRUE),
    observed_after_expiry = any(Month > expiry),
    .groups = "drop"
  ) %>%
  mutate(outcome = case_when(
    renewed ~ "renewed",
    moved_before_expiry ~ "transferred_before_expiry",
    observed_after_expiry ~ "new_club_or_free_after_expiry",
    TRUE ~ "exits_panel_at_expiry"
  ))

funnel <- resolve %>%
  count(outcome) %>%
  mutate(share = n / sum(n)) %>%
  arrange(desc(n))
write_csv(funnel, file.path(out_dir, "contract_outcome_funnel.csv"))

# ---- 2. raw playing profile by months-to-expiry ----
raw_profile <- panel %>%
  filter(months_to_expiry <= 36) %>%
  group_by(months_to_expiry) %>%
  summarise(share_played = mean(played), mean_minutes = mean(Minutes_tm, na.rm = TRUE),
            n = n(), .groups = "drop")
write_csv(raw_profile, file.path(out_dir, "raw_playing_by_months_to_expiry.csv"))

p1 <- ggplot(raw_profile, aes(months_to_expiry, share_played)) +
  geom_col(fill = "#00798c") +
  scale_x_reverse(breaks = seq(0, 36, 6)) +
  labs(x = "Months to contract expiry (time runs left)",
       y = "Share of player-months with any minutes",
       title = "Raw playing share over the contract cycle (no controls)") +
  theme_minimal(base_size = 11)
ggsave(file.path(out_dir, "raw_playing_by_months_to_expiry.png"), p1,
       width = 8, height = 4.5, dpi = 150)

# ---- 3. renewal timing ----
renewal_timing <- panel %>%
  filter(renewed_this_month) %>%
  mutate(months_left_on_old = pmin(as.integer(floor(
    as.numeric(prev_expiry - Month) / 30.44)), 36L)) %>%
  filter(!is.na(months_left_on_old), months_left_on_old >= 0) %>%
  count(months_left_on_old) %>%
  mutate(share = n / sum(n))
write_csv(renewal_timing, file.path(out_dir, "renewal_timing_months_left.csv"))

p2 <- ggplot(renewal_timing, aes(months_left_on_old, share)) +
  geom_col(fill = "#00798c") +
  scale_x_reverse(breaks = seq(0, 36, 6)) +
  labs(x = "Months left on old contract when extension signed",
       y = "Share of extensions",
       title = "When do players extend?") +
  theme_minimal(base_size = 11)
ggsave(file.path(out_dir, "renewal_timing.png"), p2, width = 8, height = 4.5, dpi = 150)

# ---- 4. expiry-date clustering ----
expiry_clustering <- panel %>%
  distinct(player_id, ContractExpiryDate) %>%
  mutate(expiry_month = format(ContractExpiryDate, "%m")) %>%
  count(expiry_month) %>%
  mutate(share = n / sum(n))
write_csv(expiry_clustering, file.path(out_dir, "expiry_month_clustering.csv"))

# ---- 5. contract length at signing by age ----
length_by_age <- panel %>%
  filter(renewed_this_month, !is.na(Age)) %>%
  mutate(
    new_length_years = as.numeric(ContractExpiryDate - Month) / 365.25,
    age_group = cut(Age, breaks = c(15, 21, 24, 27, 30, 33, 45),
                    labels = c("<=21", "22-24", "25-27", "28-30", "31-33", "34+"))
  ) %>%
  filter(new_length_years > 0, new_length_years < 8, !is.na(age_group)) %>%
  group_by(age_group) %>%
  summarise(mean_length = mean(new_length_years),
            median_length = median(new_length_years),
            n = n(), .groups = "drop")
write_csv(length_by_age, file.path(out_dir, "contract_length_at_signing_by_age.csv"))

# ---- 6. league x season rating coverage ----
coverage <- panel %>%
  filter(!is.na(fotmob_source_league)) %>%
  mutate(rated = !is.na(fotmob_mean_rating) & fotmob_mean_rating > 0) %>%
  group_by(fotmob_source_league, season) %>%
  summarise(rated_player_months = sum(rated), .groups = "drop") %>%
  pivot_wider(names_from = season, values_from = rated_player_months, values_fill = 0) %>%
  arrange(desc(`2025/2026`))
write_csv(coverage, file.path(out_dir, "league_season_rating_coverage.csv"))

message("Saved contract descriptives to ", out_dir)
