library(dplyr)
library(ggplot2)
library(lubridate)
library(openxlsx)
library(readr)
library(tidyr)

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates) | dir.exists(candidates)]

  if (length(existing) > 0) {
    return(existing[[1]])
  }

  candidates[[1]]
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

football_season <- function(month) {
  year <- as.integer(format(month, "%Y"))
  month_num <- as.integer(format(month, "%m"))
  start_year <- if_else(month_num >= 7L, year, year - 1L)
  paste0(start_year, "/", start_year + 1L)
}

prepare_renewal_panel <- function(df) {
  df %>%
    arrange(player_id, Month) %>%
    group_by(player_id) %>%
    mutate(
      prev_expiry = lag(ContractExpiryDate),
      expiry_jump_days = as.numeric(ContractExpiryDate - prev_expiry),
      signed_new_contract = !is.na(expiry_jump_days) & expiry_jump_days > 90,
      ever_signed_new_contract = any(signed_new_contract, na.rm = TRUE),
      first_sign_month = if (any(signed_new_contract, na.rm = TRUE)) {
        first(Month[signed_new_contract])
      } else {
        as.Date(NA)
      },
      post_new_contract = !is.na(first_sign_month) & Month >= first_sign_month,
      months_from_sign = ifelse(
        !is.na(first_sign_month),
        as.numeric(Month - first_sign_month) / 30.44,
        NA_real_
      ),
      sign_bin_6m = cut(
        months_from_sign,
        breaks = c(-24, -18, -12, -6, 0, 6, 12, 18, 24),
        include.lowest = TRUE,
        right = FALSE,
        labels = c("-24:-18", "-18:-12", "-12:-6", "-6:0", "0:6", "6:12", "12:18", "18:24")
      )
    ) %>%
    ungroup()
}

numeric_summary <- function(df, variables) {
  df %>%
    select(all_of(variables)) %>%
    pivot_longer(everything(), names_to = "variable", values_to = "value") %>%
    group_by(variable) %>%
    summarise(
      n = sum(!is.na(value)),
      mean = mean(value, na.rm = TRUE),
      sd = sd(value, na.rm = TRUE),
      min = min(value, na.rm = TRUE),
      p25 = quantile(value, 0.25, na.rm = TRUE),
      median = median(value, na.rm = TRUE),
      p75 = quantile(value, 0.75, na.rm = TRUE),
      max = max(value, na.rm = TRUE),
      .groups = "drop"
    )
}

t_test_row <- function(df, variable) {
  test_df <- df %>%
    filter(!is.na(.data[[variable]]), !is.na(Bosman))

  bosman_values <- test_df %>%
    filter(Bosman) %>%
    pull(all_of(variable))
  outside_values <- test_df %>%
    filter(!Bosman) %>%
    pull(all_of(variable))

  test <- t.test(bosman_values, outside_values)

  tibble(
    variable = variable,
    n_bosman = length(bosman_values),
    mean_bosman = mean(bosman_values),
    sd_bosman = sd(bosman_values),
    n_outside = length(outside_values),
    mean_outside = mean(outside_values),
    sd_outside = sd(outside_values),
    difference_bosman_minus_outside = mean_bosman - mean_outside,
    t_statistic = unname(test$statistic),
    p_value = test$p.value
  )
}

fmt <- function(x, digits = 2) {
  format(round(x, digits), nsmall = digits, trim = TRUE)
}

bios_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller data.xlsx"
panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
crosswalk_path <- resolve_path("data", "fotmob_transfermarkt_crosswalk_confirmed.csv")
historical_checkpoint_ratings_dir <- resolve_path("data", "historical", "checkpoints", "ratings")
results_dir <- resolve_path("results", "thesis_descriptive_statistics")
ensure_dir(results_dir)

parse_mixed_date <- function(x) {
  if (inherits(x, "Date")) {
    return(as.Date(x))
  }

  x_chr <- as.character(x)
  parsed_dmy <- suppressWarnings(dmy(x_chr))
  parsed_ymd <- suppressWarnings(ymd(x_chr))
  parsed_excel <- suppressWarnings(as.Date(as.numeric(x_chr), origin = "1899-12-30"))
  coalesce(parsed_dmy, parsed_ymd, parsed_excel)
}

panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(
    sample_name = "all_comps",
    Month = as.Date(Month),
    ContractExpiryDate = as.Date(ContractExpiryDate),
    LastExtensionDate = as.Date(LastExtensionDate),
    player_id = as.integer(player_id),
    ClubID = as.integer(ClubID),
    fotmob_player_id = as.integer(fotmob_player_id),
    Bosman = as.logical(Bosman),
    season = football_season(Month),
    rating_positive = !is.na(fotmob_mean_rating) & fotmob_mean_rating > 0,
    weighted_rating_positive = !is.na(fotmob_minutes_weighted_rating) & fotmob_minutes_weighted_rating > 0,
    fotmob_mean_rating_clean = if_else(rating_positive, fotmob_mean_rating, NA_real_),
    fotmob_minutes_weighted_rating_clean = if_else(
      weighted_rating_positive,
      fotmob_minutes_weighted_rating,
      NA_real_
    )
  )

historical_checkpoint_files <- list.files(
  historical_checkpoint_ratings_dir,
  pattern = "_ratings[.]csv$",
  full.names = TRUE
)

historical_checkpoint_ratings <- bind_rows(lapply(historical_checkpoint_files, function(path) {
  read_csv(path, show_col_types = FALSE, col_types = cols(.default = col_character())) %>%
    mutate(source_file = basename(path))
})) %>%
  mutate(
    source_league_name = as.character(source_league_name),
    source_league_id = as.integer(source_league_id),
    season_start = as.Date(season_start),
    season_end = as.Date(season_end),
    season_name = "2024/2025",
    fotmob_player_id = as.integer(fotmob_player_id),
    fotmob_player_name = as.character(fotmob_player_name),
    fotmob_team_id = as.integer(fotmob_team_id),
    fotmob_team_name = as.character(fotmob_team_name),
    match_id = as.integer(match_id),
    match_date = as.Date(match_date),
    Month = as.Date(format(match_date, "%Y-%m-01")),
    league_id = as.integer(league_id),
    league_name = as.character(league_name),
    minutes_played = as.integer(minutes_played),
    goals = as.integer(goals),
    assists = as.integer(assists),
    yellow_cards = as.integer(yellow_cards),
    red_cards = as.integer(red_cards),
    rating = as.numeric(rating),
    on_bench = as.logical(on_bench),
    is_source_league_match = league_id == source_league_id,
    has_minutes = coalesce(minutes_played, 0L) > 0L,
    has_valid_rating = !is.na(rating) & rating > 0
  ) %>%
  filter(!is.na(fotmob_player_id), !is.na(match_id), !is.na(match_date)) %>%
  distinct(source_league_id, fotmob_player_id, match_id, .keep_all = TRUE)

safe_crosswalk <- read_csv(crosswalk_path, show_col_types = FALSE) %>%
  filter(approved, merge_safe) %>%
  transmute(
    player_id = as.integer(tm_player_id),
    fotmob_player_id = as.integer(fotmob_player_id)
  ) %>%
  distinct(fotmob_player_id, .keep_all = TRUE)

historical_checkpoint_panel_overlap <- historical_checkpoint_ratings %>%
  left_join(safe_crosswalk, by = "fotmob_player_id") %>%
  mutate(in_analysis_panel = !is.na(player_id) & player_id %in% panel$player_id)

key_variables <- c(
  "DaysToExpiry",
  "Age",
  "Minutes_tm",
  "Goals_tm",
  "Assists_tm",
  "Goals_per90_tm",
  "Assists_per90_tm",
  "fotmob_matches",
  "fotmob_minutes",
  "fotmob_goals",
  "fotmob_assists",
  "fotmob_mean_rating_clean",
  "fotmob_minutes_weighted_rating_clean"
)

sample_overview <- tibble(
  statistic = c(
    "Observations",
    "Players",
    "Clubs",
    "Seasons",
    "First month",
    "Last month",
    "Bosman-window observations",
    "Non-Bosman observations"
  ),
  value = c(
    as.character(nrow(panel)),
    as.character(n_distinct(panel$player_id)),
    as.character(n_distinct(panel$ClubID)),
    as.character(n_distinct(panel$season)),
    as.character(min(panel$Month, na.rm = TRUE)),
    as.character(max(panel$Month, na.rm = TRUE)),
    as.character(sum(panel$Bosman, na.rm = TRUE)),
    as.character(sum(!panel$Bosman, na.rm = TRUE))
  )
)

season_coverage <- panel %>%
  group_by(season) %>%
  summarise(
    observations = n(),
    players = n_distinct(player_id),
    clubs = n_distinct(ClubID),
    bosman_window_observations = sum(Bosman, na.rm = TRUE),
    positive_mean_rating_observations = sum(rating_positive, na.rm = TRUE),
    positive_weighted_rating_observations = sum(weighted_rating_positive, na.rm = TRUE),
    first_month = min(Month, na.rm = TRUE),
    last_month = max(Month, na.rm = TRUE),
    .groups = "drop"
  )

rating_availability <- panel %>%
  group_by(season) %>%
  summarise(
    observations = n(),
    fotmob_rows = sum(!is.na(fotmob_matches), na.rm = TRUE),
    positive_mean_rating_observations = sum(rating_positive, na.rm = TRUE),
    positive_weighted_rating_observations = sum(weighted_rating_positive, na.rm = TRUE),
    mean_rating_coverage_share = positive_mean_rating_observations / observations,
    weighted_rating_coverage_share = positive_weighted_rating_observations / observations,
    .groups = "drop"
  )

historical_rating_files <- list.files(
  resolve_path("data", "historical"),
  pattern = "_ratings[.]csv$",
  recursive = TRUE,
  full.names = TRUE
)

historical_rating_file_audit <- bind_rows(lapply(historical_rating_files, function(path) {
  ratings_file <- tryCatch(
    read_csv(path, show_col_types = FALSE, progress = FALSE),
    error = function(e) NULL
  )

  tibble(
    file = path,
    rows = if (is.null(ratings_file)) NA_integer_ else nrow(ratings_file),
    min_match_date = if (!is.null(ratings_file) && nrow(ratings_file) > 0 && "match_date" %in% names(ratings_file)) {
      min(as.Date(ratings_file$match_date), na.rm = TRUE)
    } else {
      as.Date(NA)
    },
    max_match_date = if (!is.null(ratings_file) && nrow(ratings_file) > 0 && "match_date" %in% names(ratings_file)) {
      max(as.Date(ratings_file$match_date), na.rm = TRUE)
    } else {
      as.Date(NA)
    }
  )
})) %>%
  mutate(
    historical_batch = case_when(
      grepl("2023_2024_clean", file) ~ "2023_2024_clean",
      grepl("data/historical/checkpoints/ratings", file) ~ "historical_checkpoints",
      TRUE ~ "other"
    )
  ) %>%
  relocate(historical_batch)

historical_checkpoint_overview <- historical_checkpoint_ratings %>%
  summarise(
    source_folder = historical_checkpoint_ratings_dir,
    files = length(historical_checkpoint_files),
    observations = n(),
    players = n_distinct(fotmob_player_id),
    matches = n_distinct(match_id),
    source_leagues = n_distinct(source_league_id),
    first_match_date = min(match_date, na.rm = TRUE),
    last_match_date = max(match_date, na.rm = TRUE),
    positive_rating_observations = sum(has_valid_rating, na.rm = TRUE),
    zero_rating_observations = sum(rating == 0, na.rm = TRUE),
    mean_rating = mean(rating[has_valid_rating], na.rm = TRUE),
    sd_rating = sd(rating[has_valid_rating], na.rm = TRUE),
    mean_minutes = mean(minutes_played[has_valid_rating], na.rm = TRUE),
    panel_matched_observations = sum(historical_checkpoint_panel_overlap$in_analysis_panel, na.rm = TRUE),
    panel_matched_positive_ratings = sum(
      historical_checkpoint_panel_overlap$in_analysis_panel &
        historical_checkpoint_panel_overlap$has_valid_rating,
      na.rm = TRUE
    )
  )

historical_checkpoint_monthly_summary <- historical_checkpoint_ratings %>%
  group_by(season_name, Month) %>%
  summarise(
    observations = n(),
    players = n_distinct(fotmob_player_id),
    matches = n_distinct(match_id),
    positive_rating_observations = sum(has_valid_rating, na.rm = TRUE),
    mean_rating = mean(rating[has_valid_rating], na.rm = TRUE),
    sd_rating = sd(rating[has_valid_rating], na.rm = TRUE),
    mean_minutes = mean(minutes_played[has_valid_rating], na.rm = TRUE),
    .groups = "drop"
  )

historical_checkpoint_league_summary <- historical_checkpoint_ratings %>%
  group_by(source_league_name, source_league_id) %>%
  summarise(
    observations = n(),
    players = n_distinct(fotmob_player_id),
    matches = n_distinct(match_id),
    positive_rating_observations = sum(has_valid_rating, na.rm = TRUE),
    mean_rating = mean(rating[has_valid_rating], na.rm = TRUE),
    sd_rating = sd(rating[has_valid_rating], na.rm = TRUE),
    first_match_date = min(match_date, na.rm = TRUE),
    last_match_date = max(match_date, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(positive_rating_observations))

table1 <- numeric_summary(panel, key_variables) %>%
  mutate(
    sample_observations = nrow(panel),
    sample_players = n_distinct(panel$player_id),
    sample_clubs = n_distinct(panel$ClubID),
    sample_seasons = n_distinct(panel$season)
  ) %>%
  select(sample_observations, sample_players, sample_clubs, sample_seasons, everything())

table2 <- bind_rows(lapply(key_variables, function(variable) t_test_row(panel, variable)))

renewal_panel <- prepare_renewal_panel(panel)

renewal_overview <- renewal_panel %>%
  filter(ever_signed_new_contract) %>%
  summarise(
    observations = n(),
    players = n_distinct(player_id),
    clubs = n_distinct(ClubID),
    signing_events = sum(signed_new_contract, na.rm = TRUE),
    first_sign_month_min = min(first_sign_month, na.rm = TRUE),
    first_sign_month_max = max(first_sign_month, na.rm = TRUE),
    pre_signing_observations = sum(!post_new_contract, na.rm = TRUE),
    post_signing_observations = sum(post_new_contract, na.rm = TRUE),
    mean_months_from_sign = mean(months_from_sign, na.rm = TRUE),
    mean_rating = mean(fotmob_mean_rating_clean, na.rm = TRUE),
    sd_rating = sd(fotmob_mean_rating_clean, na.rm = TRUE),
    mean_weighted_rating = mean(fotmob_minutes_weighted_rating_clean, na.rm = TRUE),
    sd_weighted_rating = sd(fotmob_minutes_weighted_rating_clean, na.rm = TRUE)
  )

table3 <- renewal_panel %>%
  filter(ever_signed_new_contract, !is.na(sign_bin_6m)) %>%
  group_by(sign_bin_6m) %>%
  summarise(
    observations = n(),
    players = n_distinct(player_id),
    signing_month_observations = sum(signed_new_contract, na.rm = TRUE),
    mean_months_from_sign = mean(months_from_sign, na.rm = TRUE),
    mean_days_to_expiry = mean(DaysToExpiry, na.rm = TRUE),
    mean_rating = mean(fotmob_mean_rating_clean, na.rm = TRUE),
    sd_rating = sd(fotmob_mean_rating_clean, na.rm = TRUE),
    mean_weighted_rating = mean(fotmob_minutes_weighted_rating_clean, na.rm = TRUE),
    sd_weighted_rating = sd(fotmob_minutes_weighted_rating_clean, na.rm = TRUE),
    mean_fotmob_minutes = mean(fotmob_minutes, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(sample_overview, file.path(results_dir, "sample_overview.csv"), na = "")
write_csv(season_coverage, file.path(results_dir, "season_coverage.csv"), na = "")
write_csv(rating_availability, file.path(results_dir, "fotmob_rating_availability_by_season.csv"), na = "")
write_csv(historical_rating_file_audit, file.path(results_dir, "historical_rating_file_audit.csv"), na = "")
write_csv(historical_checkpoint_overview, file.path(results_dir, "historical_2024_2025_checkpoint_rating_overview.csv"), na = "")
write_csv(historical_checkpoint_monthly_summary, file.path(results_dir, "historical_2024_2025_checkpoint_rating_by_month.csv"), na = "")
write_csv(historical_checkpoint_league_summary, file.path(results_dir, "historical_2024_2025_checkpoint_rating_by_league.csv"), na = "")
write_csv(table1, file.path(results_dir, "table1_full_sample_summary_statistics.csv"), na = "")
write_csv(table2, file.path(results_dir, "table2_bosman_window_mean_comparison_ttests.csv"), na = "")
write_csv(renewal_overview, file.path(results_dir, "renewal_subsample_overview.csv"), na = "")
write_csv(table3, file.path(results_dir, "table3_renewal_signing_event_summary.csv"), na = "")

plot_theme <- theme_classic(base_size = 12) +
  theme(
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA),
    panel.grid.major.y = element_line(color = "#E6E1D8", linewidth = 0.35),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    axis.line = element_line(color = "#2B2B2B", linewidth = 0.35),
    axis.ticks = element_line(color = "#2B2B2B", linewidth = 0.3),
    axis.text = element_text(color = "#2B2B2B"),
    axis.title = element_text(color = "#1F1F1F"),
    plot.title = element_text(face = "bold", size = 15, color = "#172033"),
    plot.subtitle = element_text(size = 11, color = "#555555"),
    plot.title.position = "plot",
    legend.position = "bottom",
    legend.title = element_blank(),
    strip.background = element_blank(),
    strip.text = element_text(face = "bold", color = "#172033")
  )

figure1_max_days <- 2190
playerbios_snapshot <- read.xlsx(bios_path) %>%
  filter(is.na(OnLoanFrom)) %>%
  transmute(
    player_id = as.integer(player_id),
    Date_scraped = as.Date(Date_scraped, origin = "1899-12-30"),
    ContractExpiryDate = parse_mixed_date(ContractExpiryDate)
  )

figure1_snapshot_date <- max(playerbios_snapshot$Date_scraped, na.rm = TRUE)
figure1_snapshot <- playerbios_snapshot %>%
  filter(Date_scraped == figure1_snapshot_date) %>%
  arrange(player_id) %>%
  distinct(player_id, .keep_all = TRUE)

figure1 <- figure1_snapshot %>%
  mutate(DaysToExpiry = as.numeric(ContractExpiryDate - Date_scraped)) %>%
  filter(!is.na(DaysToExpiry), DaysToExpiry >= 0, DaysToExpiry <= figure1_max_days) %>%
  ggplot(aes(x = DaysToExpiry)) +
  geom_histogram(binwidth = 30, boundary = 0, fill = "#1F6F78", color = "white", linewidth = 0.15) +
  geom_vline(xintercept = 183, color = "#B33A3A", linewidth = 0.9) +
  annotate(
    "label",
    x = 183,
    y = Inf,
    label = "6-month threshold",
    vjust = 1.35,
    hjust = -0.08,
    label.size = 0,
    fill = "white",
    color = "#B33A3A",
    size = 3.4
  ) +
  scale_x_reverse(
    breaks = c(2190, 1825, 1460, 1095, 730, 365, 183, 0),
    labels = c("6y", "5y", "4y", "3y", "2y", "1y", "6m", "0")
  ) +
  scale_y_continuous(labels = function(x) format(x, big.mark = ",", scientific = FALSE)) +
  coord_cartesian(xlim = c(figure1_max_days, 0)) +
  labs(
    title = "Contract Time Remaining",
    subtitle = paste0(
      "Non-loan PlayerBios snapshot on ",
      format(figure1_snapshot_date, "%Y-%m-%d"),
      "; six years or less remaining"
    ),
    x = "Time until contract expiry",
    y = "Players"
  ) +
  plot_theme

binned_scatter_binwidth <- 30

binned_scatter_data <- panel %>%
  filter(DaysToExpiry >= 0, DaysToExpiry <= 366) %>%
  mutate(days_bin = floor(DaysToExpiry / binned_scatter_binwidth) * binned_scatter_binwidth +
    binned_scatter_binwidth / 2) %>%
  filter(!is.na(fotmob_mean_rating_clean)) %>%
  group_by(days_bin) %>%
  summarise(
    observations = n(),
    mean_rating = mean(fotmob_mean_rating_clean),
    .groups = "drop"
  )

figure2 <- ggplot(binned_scatter_data, aes(x = days_bin, y = mean_rating)) +
  geom_hline(yintercept = 5.5, color = "#E6E1D8", linewidth = 0.45) +
  geom_smooth(
    method = "lm",
    formula = y ~ poly(x, 2),
    se = FALSE,
    color = "#172033",
    linewidth = 1.05
  ) +
  geom_point(
    shape = 21,
    size = 3.3,
    fill = "#1F6F78",
    color = "white",
    stroke = 0.45,
    alpha = 0.95
  ) +
  geom_vline(xintercept = 183, color = "#B33A3A", linewidth = 0.85) +
  annotate(
    "segment",
    x = 183,
    xend = 168,
    y = 5.95,
    yend = 5.95,
    color = "#B33A3A",
    linewidth = 0.35
  ) +
  annotate(
    "text",
    x = 166,
    y = 5.95,
    label = "6-month threshold",
    hjust = 0,
    color = "#B33A3A",
    size = 3.5
  ) +
  scale_x_reverse(
    limits = c(375, 0),
    breaks = c(360, 270, 183, 90, 0),
    labels = c("12m", "9m", "6m", "3m", "0")
  ) +
  scale_y_continuous(limits = c(4.75, 6.05), breaks = seq(4.8, 6.0, by = 0.3)) +
  labs(
    title = "Mean FotMob Rating Near Contract Expiry",
    subtitle = "Thirty-day bins from one year remaining to expiry",
    x = "Time until contract expiry",
    y = "Mean rating"
  ) +
  plot_theme +
  theme(
    legend.position = "none"
  )

historical_checkpoint_rating_density <- historical_checkpoint_ratings %>%
  filter(has_valid_rating) %>%
  ggplot(aes(x = rating)) +
  geom_histogram(binwidth = 0.1, boundary = 0, fill = "#3A7CA5", color = "white", linewidth = 0.2) +
  labs(
    title = "Distribution of 2024/25 historical checkpoint FotMob ratings",
    x = "Match rating",
    y = "Player-match observations"
  ) +
  plot_theme

ggsave(file.path(results_dir, "figure1_days_to_expiry_histogram.png"), figure1, width = 9, height = 6, dpi = 300, bg = "white")
ggsave(file.path(results_dir, "figure2_binned_rating_scatter_around_threshold.png"), figure2, width = 9, height = 6, dpi = 300, bg = "white")
ggsave(
  file.path(results_dir, "historical_2024_2025_checkpoint_rating_histogram.png"),
  historical_checkpoint_rating_density,
  width = 9,
  height = 6,
  dpi = 300
)

overview_lines <- paste0("- ", sample_overview$statistic, ": ", sample_overview$value)

availability_lines <- rating_availability %>%
  mutate(
    line = paste0(
      "- `", season, "`: observations = ", observations,
      ", positive mean-rating rows = ", positive_mean_rating_observations,
      " (", fmt(100 * mean_rating_coverage_share, 1), "%)"
    )
  ) %>%
  pull(line)

historical_checkpoint_lines <- historical_checkpoint_overview %>%
  mutate(
    line = paste0(
      "- 2024/25 checkpoint ratings: observations = ", observations,
      ", positive ratings = ", positive_rating_observations,
      ", players = ", players,
      ", matches = ", matches,
      ", date range = ", first_match_date, " to ", last_match_date,
      ", mean rating = ", fmt(mean_rating),
      ", panel-matched positive ratings = ", panel_matched_positive_ratings
    )
  ) %>%
  pull(line)

table1_lines <- table1 %>%
  mutate(
    line = paste0(
      "- `", variable, "`: n = ", n,
      ", mean = ", fmt(mean),
      ", sd = ", fmt(sd),
      ", median = ", fmt(median)
    )
  ) %>%
  pull(line)

table2_lines <- table2 %>%
  mutate(
    line = paste0(
      "- `", variable, "`: Bosman mean = ", fmt(mean_bosman),
      ", outside mean = ", fmt(mean_outside),
      ", diff = ", fmt(difference_bosman_minus_outside),
      ", p = ", format.pval(p_value, digits = 3, eps = 0.001)
    )
  ) %>%
  pull(line)

summary_lines <- c(
  "# Thesis Descriptive Statistics",
  "",
  "This folder contains the clean descriptive statistics section requested for the thesis. The main sample is `all_comps` from `data/panel/fotmob_analysis_panel_all_comps.csv`, so earlier contract-panel seasons are included.",
  "",
  "Positive FotMob rating variables are used for rating means and plots. Zero ratings are treated as no-rating observations and set to missing in `fotmob_mean_rating_clean` and `fotmob_minutes_weighted_rating_clean`. Earlier seasons can contribute to contract timing, Bosman status, player, club, and Transfermarkt variables even when FotMob ratings are unavailable.",
  "",
  "## Sample Overview",
  "",
  overview_lines,
  "",
  "Season-level coverage is saved in `season_coverage.csv`.",
  "",
  "## FotMob Rating Availability",
  "",
  "The contract panel now covers older seasons, but FotMob rating coverage is not available for every historical season in the local files. Rating coverage by season is saved in `fotmob_rating_availability_by_season.csv`; the historical rating checkpoint audit is saved in `historical_rating_file_audit.csv`.",
  "",
  availability_lines,
  "",
  "The 2024/25 ratings from `data/historical/checkpoints/ratings` are also read directly and summarised in this folder:",
  "",
  historical_checkpoint_lines,
  "",
  "- `historical_2024_2025_checkpoint_rating_overview.csv`",
  "- `historical_2024_2025_checkpoint_rating_by_month.csv`",
  "- `historical_2024_2025_checkpoint_rating_by_league.csv`",
  "- `historical_2024_2025_checkpoint_rating_histogram.png`",
  "",
  "## Table 1",
  "",
  "Full sample summary statistics are saved in `table1_full_sample_summary_statistics.csv`.",
  "",
  table1_lines,
  "",
  "## Table 2",
  "",
  "Comparison of means between player-months inside and outside the Bosman window is saved in `table2_bosman_window_mean_comparison_ttests.csv`.",
  "",
  table2_lines,
  "",
  "## Table 3",
  "",
  "Signing event summary statistics for the renewal analysis subsample are saved in `table3_renewal_signing_event_summary.csv`. The file `renewal_subsample_overview.csv` gives the overall renewal-sample counts.",
  "",
  "## Figures",
  "",
  "- `figure1_days_to_expiry_histogram.png`",
  "- `figure2_binned_rating_scatter_around_threshold.png`"
)

writeLines(summary_lines, file.path(results_dir, "SUMMARY.md"))

message("Saved thesis descriptive statistics to: ", results_dir)
