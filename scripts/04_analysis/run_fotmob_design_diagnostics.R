library(dplyr)
library(readr)
library(tibble)

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates) | dir.exists(candidates)]

  if (length(existing) > 0) {
    return(existing[[1]])
  }

  candidates[[1]]
}

safe_write_csv <- function(df, path) {
  tmp_path <- tempfile(
    pattern = paste0(basename(path), "."),
    tmpdir = dirname(path),
    fileext = ".tmp"
  )

  utils::write.csv(df, tmp_path, row.names = FALSE, na = "")

  if (file.exists(path)) {
    file.remove(path)
  }

  file.rename(tmp_path, path)
}

football_season <- function(month) {
  year <- as.integer(format(month, "%Y"))
  month_num <- as.integer(format(month, "%m"))
  start_year <- if_else(month_num >= 7L, year, year - 1L)
  paste0(start_year, "/", start_year + 1L)
}

read_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      player_id = as.integer(player_id),
      DaysToExpiry = as.numeric(DaysToExpiry),
      Bosman = as.logical(Bosman),
      Age = as.numeric(Age),
      fotmob_mean_rating = as.numeric(fotmob_mean_rating),
      fotmob_minutes_weighted_rating = as.numeric(fotmob_minutes_weighted_rating),
      fotmob_minutes = as.numeric(fotmob_minutes),
      fotmob_matches = as.numeric(fotmob_matches),
      season = football_season(Month)
    )
}

read_monthly_master <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      tm_player_id = as.integer(tm_player_id),
      season = football_season(Month)
    )
}

make_funnel <- function(monthly_master, panel, strict, sample_name) {
  master_keys <- monthly_master %>%
    distinct(season, tm_player_id, Month)

  panel_keys <- panel %>%
    distinct(season, player_id, Month)

  overlap <- master_keys %>%
    inner_join(
      panel_keys,
      by = c("season", "tm_player_id" = "player_id", "Month")
    )

  seasons <- sort(unique(c(master_keys$season, panel$season, strict$season)))

  bind_rows(lapply(seasons, function(season_name) {
    master_season <- master_keys %>% filter(season == season_name)
    panel_season <- panel %>% filter(season == season_name)
    overlap_season <- overlap %>% filter(season == season_name)
    strict_season <- strict %>% filter(season == season_name)

    tibble(
      sample_name = sample_name,
      season = season_name,
      master_monthly_rows = nrow(master_season),
      master_players = n_distinct(master_season$tm_player_id),
      panel_rows = nrow(panel_season),
      panel_players = n_distinct(panel_season$player_id),
      exact_player_month_overlap = nrow(overlap_season),
      overlap_players = n_distinct(overlap_season$tm_player_id),
      strict_rows = nrow(strict_season),
      strict_players = n_distinct(strict_season$player_id),
      strict_share_of_master = if_else(nrow(master_season) > 0, nrow(strict_season) / nrow(master_season), NA_real_),
      strict_share_of_overlap = if_else(nrow(overlap_season) > 0, nrow(strict_season) / nrow(overlap_season), NA_real_)
    )
  }))
}

make_rdd_support <- function(panel, sample_name) {
  cutoffs <- c(120, 150, 180, 210, 240)
  bandwidths <- c(30, 60, 90, 180)

  specs <- expand.grid(
    cutoff_days = cutoffs,
    bandwidth_days = bandwidths,
    stringsAsFactors = FALSE
  )

  bind_rows(lapply(seq_len(nrow(specs)), function(i) {
    cutoff <- specs$cutoff_days[[i]]
    bandwidth <- specs$bandwidth_days[[i]]

    local_df <- panel %>%
      filter(
        !is.na(DaysToExpiry),
        abs(DaysToExpiry - cutoff) <= bandwidth
      )

    tibble(
      sample_name = sample_name,
      cutoff_days = cutoff,
      bandwidth_days = bandwidth,
      n_rows = nrow(local_df),
      n_players = n_distinct(local_df$player_id),
      n_above = sum(local_df$DaysToExpiry > cutoff, na.rm = TRUE),
      n_inside = sum(local_df$DaysToExpiry <= cutoff, na.rm = TRUE),
      n_above_players = n_distinct(local_df$player_id[local_df$DaysToExpiry > cutoff]),
      n_inside_players = n_distinct(local_df$player_id[local_df$DaysToExpiry <= cutoff])
    )
  }))
}

make_near_cutoff_balance <- function(panel, sample_name, cutoff_days = 180, bandwidth_days = 90) {
  panel %>%
    filter(
      !is.na(DaysToExpiry),
      abs(DaysToExpiry - cutoff_days) <= bandwidth_days
    ) %>%
    mutate(side = if_else(DaysToExpiry <= cutoff_days, "inside_cutoff", "above_cutoff")) %>%
    group_by(side) %>%
    summarise(
      sample_name = sample_name,
      cutoff_days = cutoff_days,
      bandwidth_days = bandwidth_days,
      n_rows = n(),
      n_players = n_distinct(player_id),
      mean_age = mean(Age, na.rm = TRUE),
      mean_minutes = mean(fotmob_minutes, na.rm = TRUE),
      mean_matches = mean(fotmob_matches, na.rm = TRUE),
      mean_rating = mean(fotmob_mean_rating, na.rm = TRUE),
      weighted_rating = mean(fotmob_minutes_weighted_rating, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    relocate(sample_name)
}

results_dir <- resolve_path("results", "fotmob_regressions")
dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

monthly_all <- read_monthly_master(resolve_path("data", "master", "fotmob_master_monthly_all_comps.csv"))
monthly_source <- read_monthly_master(resolve_path("data", "master", "fotmob_master_monthly_source_league.csv"))

panel_all <- read_panel(resolve_path("data", "panel", "fotmob_analysis_panel_all_comps.csv"))
panel_source <- read_panel(resolve_path("data", "panel", "fotmob_analysis_panel_source_league.csv"))
strict_all <- read_panel(resolve_path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv"))
strict_source <- read_panel(resolve_path("data", "panel", "fotmob_analysis_panel_source_league_strict.csv"))

funnel <- bind_rows(
  make_funnel(monthly_all, panel_all, strict_all, "all_comps"),
  make_funnel(monthly_source, panel_source, strict_source, "source_league")
) %>%
  arrange(sample_name, season)

rdd_support <- bind_rows(
  make_rdd_support(panel_all, "all_comps"),
  make_rdd_support(panel_source, "source_league")
) %>%
  arrange(sample_name, cutoff_days, bandwidth_days)

near_cutoff_balance <- bind_rows(
  make_near_cutoff_balance(panel_all, "all_comps"),
  make_near_cutoff_balance(panel_source, "source_league")
)

safe_write_csv(funnel, file.path(results_dir, "fotmob_design_sample_funnel.csv"))
safe_write_csv(rdd_support, file.path(results_dir, "fotmob_design_rdd_support.csv"))
safe_write_csv(near_cutoff_balance, file.path(results_dir, "fotmob_design_near_cutoff_balance.csv"))

print(funnel)
print(rdd_support)
print(near_cutoff_balance)
