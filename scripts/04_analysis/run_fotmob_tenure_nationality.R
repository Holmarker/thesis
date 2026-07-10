library(DBI)
library(RSQLite)
library(dplyr)
library(fixest)
library(ggplot2)
library(readr)
library(stringr)
library(tibble)
library(tidyr)

# Tenure and nationality heterogeneity. Club/league tenure is computed from
# the TM appearance log in the valuation DB (read-only). NOTE: the log only
# starts in 2022, so tenure is LEFT-TRUNCATED at ~4 years — bands measure
# time since first tracked appearance, not true tenure, and long-serving
# players are censored into the lower bands. Tenure and foreign
# status enter as Bosman interactions, never as linear controls: within a
# spell, tenure is a per-player time trend (collinear with spell + month
# FE), and nationality-league match is constant within a spell.

db_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/OTP-PVM-4.0/valuation_db.sqlite"
panel_full_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
panel_strict_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
results_dir <- file.path("results", "fotmob_regressions")
desc_dir <- file.path("results", "fotmob_descriptives")

league_country <- c(
  "English" = "England", "Spanish" = "Spain", "German" = "Germany",
  "French" = "France", "Italian" = "Italy", "Turkish" = "Turkey",
  "Portuguese" = "Portugal", "Saudi" = "Saudi Arabia",
  "Brazilian" = "Brazil", "Belgian" = "Belgium", "Dutch" = "Netherlands",
  "Ukrainian" = "Ukraine", "Greek" = "Greece", "Danish" = "Denmark",
  "Scottish" = "Scotland", "Austrian" = "Austria",
  "Argentine" = "Argentina", "Swiss" = "Switzerland",
  "Serbian" = "Serbia", "Croatian" = "Croatia", "Czech" = "Czech Republic",
  "Norwegian" = "Norway", "Romanian" = "Romania", "Polish" = "Poland",
  "Swedish" = "Sweden", "Bulgarian" = "Bulgaria", "Hungarian" = "Hungary"
)

football_season <- function(month) {
  y <- as.integer(format(month, "%Y"))
  m <- as.integer(format(month, "%m"))
  s <- if_else(m >= 7L, y, y - 1L)
  paste0(s, "/", s + 1L)
}

read_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      ContractExpiryDate = as.Date(ContractExpiryDate),
      Bosman = as.logical(Bosman),
      player_id = as.integer(player_id),
      ClubID = as.integer(ClubID),
      Minutes_tm = as.numeric(Minutes_tm),
      played = coalesce(Minutes_tm, 0) > 0,
      season = football_season(Month),
      league_adj = word(fotmob_source_league, 1),
      league_country = unname(league_country[league_adj]),
      foreign = if_else(
        !is.na(league_country) & !is.na(nationality_new),
        nationality_new != league_country, NA
      )
    ) %>%
    arrange(player_id, Month) %>%
    group_by(player_id) %>%
    mutate(
      jump = as.numeric(ContractExpiryDate - lag(ContractExpiryDate)),
      new_spell = is.na(lag(ContractExpiryDate)) | abs(coalesce(jump, 0)) > 90,
      player_spell = paste0(player_id, "_", cumsum(new_spell))
    ) %>%
    ungroup() %>%
    mutate(league_month = paste0(fotmob_source_league, "_", Month))
}

panel_full <- read_panel(panel_full_path)
panel_strict <- read_panel(panel_strict_path) %>%
  group_by(fotmob_source_league, season) %>%
  mutate(z_rating = {
    x <- if_else(!is.na(fotmob_mean_rating) & fotmob_mean_rating > 0,
                 fotmob_mean_rating, NA_real_)
    (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
  }) %>%
  ungroup()

# ---- tenure from the full appearance log (pull-only) ----
con <- dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
appearances <- dbGetQuery(con, "
  SELECT PlayerID AS player_id, ClubID, CompID, Date, Minutes
  FROM playerstats_processed
") %>%
  filter(player_id %in% unique(panel_full$player_id)) %>%
  mutate(Date = lubridate::dmy(Date)) %>%
  filter(!is.na(Date))
dbDisconnect(con)

first_at_club <- appearances %>%
  group_by(player_id, ClubID) %>%
  summarise(first_club_app = min(Date), .groups = "drop") %>%
  mutate(player_id = as.integer(player_id), ClubID = as.integer(ClubID))

# competition tenure: for each player-month, the player's modal competition
# over the surrounding season (by minutes); league tenure is years since the
# first appearance in that competition
first_in_comp <- appearances %>%
  group_by(player_id, CompID) %>%
  summarise(first_comp_app = min(Date), .groups = "drop") %>%
  mutate(player_id = as.integer(player_id))

modal_comp <- appearances %>%
  mutate(
    Month = lubridate::floor_date(Date, "month"),
    season = football_season(Month),
    player_id = as.integer(player_id)
  ) %>%
  group_by(player_id, season, CompID) %>%
  summarise(minutes = sum(Minutes, na.rm = TRUE), .groups = "drop") %>%
  group_by(player_id, season) %>%
  slice_max(minutes, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(player_id, season, CompID)

add_tenure <- function(panel) {
  panel %>%
    left_join(first_at_club, by = c("player_id", "ClubID")) %>%
    left_join(modal_comp, by = c("player_id", "season")) %>%
    left_join(first_in_comp, by = c("player_id", "CompID")) %>%
    mutate(
      club_tenure_years = pmax(as.numeric(Month - first_club_app) / 365.25, 0),
      league_tenure_years = pmax(as.numeric(Month - first_comp_app) / 365.25, 0),
      club_tenure_band = cut(
        club_tenure_years, breaks = c(-Inf, 1, 3, 6, Inf),
        labels = c("<1y", "1-3y", "3-6y", "6y+")
      ),
      league_tenure_band = cut(
        league_tenure_years, breaks = c(-Inf, 1, 3, 6, Inf),
        labels = c("<1y", "1-3y", "3-6y", "6y+")
      )
    )
}

panel_full <- add_tenure(panel_full)
panel_strict <- add_tenure(panel_strict)

# ---- regressions: Bosman interactions, spell + league-month FE ----
tidy_interactions <- function(model, outcome, split) {
  as_tibble(coeftable(model), rownames = "term") %>%
    setNames(c("term", "estimate", "std_error", "t_value", "p_value")) %>%
    filter(str_detect(term, "Bosman")) %>%
    mutate(outcome_name = outcome, split_var = split, nobs = nobs(model)) %>%
    select(outcome_name, split_var, term, estimate, std_error, p_value, nobs)
}

run_split <- function(data, outcome, split) {
  d <- data %>% filter(!is.na(.data[[split]]))
  m <- tryCatch(
    feols(as.formula(paste0(outcome, " ~ Bosman * ", split,
                            " | player_spell + league_month")),
          data = d, cluster = ~player_id),
    error = function(e) NULL
  )
  if (is.null(m)) return(NULL)
  tidy_interactions(m, outcome, split)
}

results <- bind_rows(
  run_split(panel_full, "played", "foreign"),
  run_split(panel_full, "played", "club_tenure_band"),
  run_split(panel_full, "played", "league_tenure_band"),
  run_split(panel_strict, "z_rating", "foreign"),
  run_split(panel_strict, "z_rating", "club_tenure_band"),
  run_split(panel_strict, "z_rating", "league_tenure_band")
)
write_csv(results, file.path(results_dir, "fotmob_tenure_nationality_results.csv"), na = "")

# group sizes for context
sizes <- bind_rows(
  panel_full %>% filter(!is.na(foreign)) %>% count(split = "foreign", level = as.character(foreign)),
  panel_full %>% filter(!is.na(club_tenure_band)) %>% count(split = "club_tenure", level = as.character(club_tenure_band)),
  panel_full %>% filter(!is.na(league_tenure_band)) %>% count(split = "league_tenure", level = as.character(league_tenure_band))
)
write_csv(sizes, file.path(results_dir, "fotmob_tenure_nationality_group_sizes.csv"))

# ---- descriptive: tenure vs playing time curve ----
# off-season months (June/July) produce a sawtooth because debuts cluster
# at season starts; drop them. Truncation caps observable tenure at ~4y.
curve <- panel_full %>%
  filter(!is.na(club_tenure_years), club_tenure_years <= 4,
         !format(Month, "%m") %in% c("06", "07")) %>%
  mutate(tenure_bin = floor(club_tenure_years * 4) / 4) %>%
  group_by(tenure_bin) %>%
  summarise(
    share_played = mean(played),
    mean_minutes = mean(Minutes_tm, na.rm = TRUE),
    n = n(), .groups = "drop"
  ) %>%
  filter(n >= 200)
write_csv(curve, file.path(desc_dir, "tenure_playing_curve.csv"))

top5_leagues <- c("English Premier League", "Spanish LaLiga",
                  "German Bundesliga", "Italian Serie A", "French Ligue 1")

curve_top5 <- panel_full %>%
  filter(fotmob_source_league %in% top5_leagues,
         !is.na(club_tenure_years), club_tenure_years <= 4,
         !format(Month, "%m") %in% c("06", "07")) %>%
  mutate(tenure_bin = floor(club_tenure_years * 4) / 4) %>%
  group_by(tenure_bin) %>%
  summarise(
    share_played = mean(played),
    mean_minutes = mean(Minutes_tm, na.rm = TRUE),
    n = n(), .groups = "drop"
  ) %>%
  filter(n >= 100)
write_csv(curve_top5, file.path(desc_dir, "tenure_playing_curve_top5.csv"))

# two stacked panels sharing the x axis: playing share on top, the number
# of player-months per bin below (one axis per panel, no dual axis)
plot_tenure_curve <- function(curve, title, outfile) {
  curve_long <- bind_rows(
    curve %>% transmute(tenure_bin,
                        panel = "Share of player-months with any minutes",
                        value = share_played),
    curve %>% transmute(tenure_bin, panel = "N (player-months per bin)",
                        value = n)
  ) %>%
    mutate(panel = factor(panel, levels = c(
      "Share of player-months with any minutes",
      "N (player-months per bin)")))

  p <- ggplot(curve_long, aes(tenure_bin, value)) +
    geom_col(data = ~filter(.x, panel == "N (player-months per bin)"),
             fill = "#9db8c9", width = 0.2) +
    geom_line(data = ~filter(.x, panel != "N (player-months per bin)"),
              color = "#00798c", linewidth = 0.9) +
    geom_point(data = ~filter(.x, panel != "N (player-months per bin)"),
               color = "#00798c", size = 1.6) +
    facet_grid(panel ~ ., scales = "free_y", switch = "y") +
    scale_x_continuous(breaks = 0:4) +
    scale_y_continuous(labels = scales::label_comma()) +
    labs(x = "Years at current club (tracked window, truncated at 2022)",
         y = NULL, title = title) +
    theme_minimal(base_size = 11) +
    theme(strip.placement = "outside",
          strip.text.y.left = element_text(size = 9))
  ggsave(outfile, p, width = 8, height = 6, dpi = 150)
}

plot_tenure_curve(curve, "Club tenure and playing time (raw)",
                  file.path(desc_dir, "tenure_playing_curve.png"))
plot_tenure_curve(curve_top5, "Club tenure and playing time, top-5 leagues (raw)",
                  file.path(desc_dir, "tenure_playing_curve_top5.png"))

print(as.data.frame(results), digits = 3)
message("Saved tenure/nationality results and playing-time curve.")
