library(dplyr)
library(lubridate)
library(readr)

project_root <- if (dir.exists("data")) "." else "RSpeciale"

path_in <- function(...) {
  file.path(project_root, ...)
}

out_dir <- path_in("results", "fotmob_regressions", "coverage_diagnostics")
if (!dir.exists(out_dir)) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
}

season_label <- function(month) {
  case_when(
    month >= as.Date("2021-07-01") & month < as.Date("2022-07-01") ~ "2021/2022",
    month >= as.Date("2022-07-01") & month < as.Date("2023-07-01") ~ "2022/2023",
    month >= as.Date("2023-07-01") & month < as.Date("2024-07-01") ~ "2023/2024",
    month >= as.Date("2024-07-01") & month < as.Date("2025-07-01") ~ "2024/2025",
    month >= as.Date("2025-07-01") & month < as.Date("2026-07-01") ~ "2025/2026",
    TRUE ~ "other"
  )
}

read_monthly <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      tm_player_id = as.integer(tm_player_id),
      fotmob_player_id = as.integer(fotmob_player_id),
      source_league_id = as.integer(source_league_id),
      Month = as.Date(Month),
      season = season_label(Month)
    )
}

read_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      player_id = as.integer(player_id),
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_source_league_id = as.integer(fotmob_source_league_id),
      Month = as.Date(Month),
      season = season_label(Month)
    )
}

crosswalk <- read_csv(
  path_in("data", "fotmob_transfermarkt_crosswalk_confirmed.csv"),
  show_col_types = FALSE
) %>%
  mutate(
    tm_player_id = as.integer(tm_player_id),
    fotmob_player_id = as.integer(fotmob_player_id),
    source_league_id = as.integer(source_league_id),
    approved = as.logical(approved),
    merge_safe = as.logical(merge_safe)
  )

safe_crosswalk <- crosswalk %>%
  filter(approved, merge_safe) %>%
  distinct(tm_player_id, fotmob_player_id, .keep_all = TRUE)

monthly_all <- read_monthly(path_in("data", "master", "fotmob_master_monthly_all_comps.csv"))
monthly_source <- read_monthly(path_in("data", "master", "fotmob_master_monthly_source_league.csv"))
panel_all <- read_panel(path_in("data", "panel", "fotmob_analysis_panel_all_comps.csv"))
panel_source <- read_panel(path_in("data", "panel", "fotmob_analysis_panel_source_league.csv"))
panel_all_strict <- read_panel(path_in("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv"))
panel_source_strict <- read_panel(path_in("data", "panel", "fotmob_analysis_panel_source_league_strict.csv"))

crosswalk_summary <- tibble(
  stage = c(
    "confirmed_crosswalk",
    "approved_merge_safe",
    "approved_not_merge_safe"
  ),
  rows = c(
    nrow(crosswalk),
    nrow(safe_crosswalk),
    nrow(filter(crosswalk, approved, !merge_safe))
  ),
  unique_tm_players = c(
    n_distinct(crosswalk$tm_player_id),
    n_distinct(safe_crosswalk$tm_player_id),
    n_distinct(filter(crosswalk, approved, !merge_safe)$tm_player_id)
  ),
  unique_fotmob_players = c(
    n_distinct(crosswalk$fotmob_player_id),
    n_distinct(safe_crosswalk$fotmob_player_id),
    n_distinct(filter(crosswalk, approved, !merge_safe)$fotmob_player_id)
  )
)

season_funnel <- tibble(season = c("2021/2022", "2022/2023", "2023/2024", "2024/2025", "2025/2026")) %>%
  left_join(
    monthly_all %>%
      group_by(season) %>%
      summarise(
        monthly_all_rows = n(),
        monthly_all_players = n_distinct(tm_player_id),
        .groups = "drop"
      ),
    by = "season"
  ) %>%
  left_join(
    monthly_source %>%
      group_by(season) %>%
      summarise(
        monthly_source_rows = n(),
        monthly_source_players = n_distinct(tm_player_id),
        .groups = "drop"
      ),
    by = "season"
  ) %>%
  left_join(
    panel_all %>%
      group_by(season) %>%
      summarise(
        panel_all_rows = n(),
        panel_all_players = n_distinct(player_id),
        panel_all_rows_with_rating = sum(has_fotmob_rating, na.rm = TRUE),
        panel_all_players_with_rating = n_distinct(player_id[has_fotmob_rating]),
        .groups = "drop"
      ),
    by = "season"
  ) %>%
  left_join(
    panel_source %>%
      group_by(season) %>%
      summarise(
        panel_source_rows = n(),
        panel_source_players = n_distinct(player_id),
        panel_source_rows_with_rating = sum(has_fotmob_rating, na.rm = TRUE),
        panel_source_players_with_rating = n_distinct(player_id[has_fotmob_rating]),
        .groups = "drop"
      ),
    by = "season"
  ) %>%
  left_join(
    panel_all_strict %>%
      group_by(season) %>%
      summarise(
        strict_all_rows = n(),
        strict_all_players = n_distinct(player_id),
        .groups = "drop"
      ),
    by = "season"
  ) %>%
  left_join(
    panel_source_strict %>%
      group_by(season) %>%
      summarise(
        strict_source_rows = n(),
        strict_source_players = n_distinct(player_id),
        .groups = "drop"
      ),
    by = "season"
  ) %>%
  mutate(across(where(is.numeric), ~ coalesce(.x, 0)))

full_panel_keys <- panel_all %>%
  select(player_id, Month, full_panel_has_rating = has_fotmob_rating)

strict_keys <- panel_all_strict %>%
  select(player_id, Month) %>%
  mutate(in_strict_panel = TRUE)

monthly_all_losses <- monthly_all %>%
  select(
    season,
    source_league_name,
    tm_player_id,
    fotmob_player_id,
    Month,
    matches,
    minutes,
    mean_rating
  ) %>%
  left_join(full_panel_keys, by = c("tm_player_id" = "player_id", "Month")) %>%
  left_join(strict_keys, by = c("tm_player_id" = "player_id", "Month")) %>%
  mutate(
    coverage_status = case_when(
      is.na(full_panel_has_rating) ~ "missing_contract_panel_month",
      !coalesce(in_strict_panel, FALSE) ~ "in_full_panel_not_strict",
      TRUE ~ "in_strict_panel"
    )
  )

monthly_loss_by_league <- monthly_all_losses %>%
  group_by(season, source_league_name, coverage_status) %>%
  summarise(
    monthly_rows = n(),
    unique_players = n_distinct(tm_player_id),
    total_minutes = sum(minutes, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(season, coverage_status, desc(unique_players), desc(monthly_rows))

unsafe_crosswalk_by_league <- crosswalk %>%
  filter(approved, !merge_safe) %>%
  group_by(source_league_name, review_flag, has_tm_conflict, has_fotmob_conflict) %>%
  summarise(
    rows = n(),
    unique_tm_players = n_distinct(tm_player_id),
    unique_fotmob_players = n_distinct(fotmob_player_id),
    .groups = "drop"
  ) %>%
  arrange(desc(rows), source_league_name)

write_csv(crosswalk_summary, file.path(out_dir, "crosswalk_summary.csv"), na = "")
write_csv(season_funnel, file.path(out_dir, "season_funnel.csv"), na = "")
write_csv(monthly_loss_by_league, file.path(out_dir, "monthly_loss_by_league.csv"), na = "")
write_csv(unsafe_crosswalk_by_league, file.path(out_dir, "unsafe_crosswalk_by_league.csv"), na = "")

message("Saved coverage diagnostics to: ", out_dir)
print(crosswalk_summary)
print(season_funnel)
