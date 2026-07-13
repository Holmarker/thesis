library(dplyr)
library(readr)
library(stringr)
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

crosswalk_path <- resolve_path("data", "fotmob_transfermarkt_crosswalk_confirmed.csv")
ratings_clean_path <- resolve_path("data", "fotmob_ratings_clean.csv")
monthly_all_path <- resolve_path("data", "fotmob_ratings_monthly_all_comps.csv")
monthly_league_path <- resolve_path("data", "fotmob_ratings_monthly_source_league.csv")
historical_root <- resolve_path("data", "historical")
master_dir <- resolve_path("data", "master")

match_out <- file.path(master_dir, "fotmob_master_match_ratings.csv")
monthly_all_out <- file.path(master_dir, "fotmob_master_monthly_all_comps.csv")
monthly_league_out <- file.path(master_dir, "fotmob_master_monthly_source_league.csv")
historical_out <- file.path(master_dir, "fotmob_master_historical_coverage.csv")
manifest_out <- file.path(master_dir, "fotmob_master_manifest.csv")

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

load_safe_crosswalk <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    filter(approved, merge_safe) %>%
    transmute(
      tm_player_id = as.integer(tm_player_id),
      tm_player_name = player_name_tm,
      tm_current_club = current_club_tm,
      tm_date_of_birth = as.Date(date_of_birth),
      tm_nationality = nationality,
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_player_name = fotmob_player_name,
      fotmob_team_id = as.integer(fotmob_team_id),
      fotmob_team_name = fotmob_team_name,
      fotmob_position_group = position_group,
      fotmob_squad_role = squad_role,
      crosswalk_match_method = match_method,
      crosswalk_candidate_score = as.numeric(candidate_score)
    ) %>%
    # the crosswalk's league is metadata from the matching season, NOT an
    # identity key - joining on it drops all months a matched player spends in
    # another league (same fix as in integrate_historical_fotmob_ratings.R)
    distinct(fotmob_player_id, .keep_all = TRUE)
}

load_match_ratings <- function(path, crosswalk) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      match_date = as.Date(match_date),
      Month = as.Date(Month),
      season_start = as.Date(season_start),
      season_end = as.Date(season_end),
      ratings_scope = case_when(
        isTRUE(has_valid_rating) & isTRUE(has_minutes) ~ "analysis_applicable",
        isTRUE(has_valid_rating) ~ "rated_no_minutes_flag",
        TRUE ~ "not_applicable"
      )
    ) %>%
    inner_join(crosswalk, by = "fotmob_player_id") %>%
    transmute(
      tm_player_id,
      tm_player_name,
      tm_current_club,
      tm_date_of_birth,
      tm_nationality,
      fotmob_player_id,
      fotmob_player_name = coalesce(fotmob_player_name.x, fotmob_player_name.y),
      fotmob_team_id = coalesce(as.integer(fotmob_team_id.x), fotmob_team_id.y),
      fotmob_team_name = coalesce(fotmob_team_name.x, fotmob_team_name.y),
      fotmob_position_group,
      fotmob_squad_role,
      source_league_id,
      source_league_name,
      competition_league_id = as.integer(league_id),
      competition_league_name = league_name,
      stage,
      season_start,
      season_end,
      season_name,
      match_id = as.integer(match_id),
      match_date,
      Month,
      match_page_url,
      match_page_full_url,
      is_source_league_match = as.logical(is_source_league_match),
      in_season_window = as.logical(in_season_window),
      is_home_team = as.logical(is_home_team),
      minutes_played = as.integer(minutes_played),
      goals = as.integer(goals),
      assists = as.integer(assists),
      yellow_cards = as.integer(yellow_cards),
      red_cards = as.integer(red_cards),
      rating = as.numeric(rating),
      is_top_rating = as.logical(is_top_rating),
      player_of_the_match = as.logical(player_of_the_match),
      on_bench = as.logical(on_bench),
      has_minutes = as.logical(has_minutes),
      has_valid_rating = as.logical(has_valid_rating),
      ratings_scope,
      ratings_source,
      crosswalk_match_method,
      crosswalk_candidate_score
    ) %>%
    arrange(match_date, tm_player_id, match_id)
}

load_monthly_ratings <- function(path, crosswalk, monthly_scope) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month)
    ) %>%
    inner_join(crosswalk, by = "fotmob_player_id") %>%
    transmute(
      tm_player_id,
      tm_player_name,
      tm_current_club,
      tm_date_of_birth,
      tm_nationality,
      fotmob_player_id,
      fotmob_player_name = coalesce(fotmob_player_name.x, fotmob_player_name.y),
      fotmob_position_group,
      fotmob_squad_role,
      source_league_id,
      source_league_name,
      Month,
      monthly_scope,
      matches = as.integer(matches),
      appearances = as.integer(appearances),
      starts_proxy = as.integer(starts_proxy),
      minutes = as.integer(minutes),
      goals = as.integer(goals),
      assists = as.integer(assists),
      yellow_cards = as.integer(yellow_cards),
      red_cards = as.integer(red_cards),
      result_matches = as.integer(result_matches),
      wins = as.integer(wins),
      draws = as.integer(draws),
      losses = as.integer(losses),
      win_share = as.numeric(win_share),
      result_points_per_match = as.numeric(result_points_per_match),
      mean_rating = as.numeric(mean_rating),
      minutes_weighted_rating = as.numeric(minutes_weighted_rating),
      top_ratings = as.integer(top_ratings),
      player_of_match_awards = as.integer(player_of_match_awards),
      crosswalk_match_method,
      crosswalk_candidate_score
    ) %>%
    arrange(Month, tm_player_id)
}

load_partial_historical_inventory <- function(historical_root, crosswalk) {
  season_dirs <- list.dirs(historical_root, recursive = FALSE, full.names = TRUE)
  season_dirs <- season_dirs[!grepl("_bad_|_clean$", basename(season_dirs))]

  if (length(season_dirs) == 0) {
    return(tibble())
  }

  inventory_files <- unlist(lapply(season_dirs, function(dir_path) {
    list.files(
      file.path(dir_path, "checkpoints", "statseasons"),
      pattern = "_statseasons\\.csv$",
      full.names = TRUE
    )
  }))

  if (length(inventory_files) == 0) {
    return(tibble())
  }

  bind_rows(lapply(inventory_files, function(path) {
    season_run <- basename(dirname(dirname(dirname(path))))
    read_csv(
      path,
      show_col_types = FALSE,
      col_types = cols(.default = col_character())
    ) %>%
      mutate(historical_run = season_run)
  })) %>%
    mutate(
      source_league_id = as.integer(source_league_id),
      tournament_id = as.integer(tournament_id),
      fotmob_player_id = as.integer(fotmob_player_id),
      tm_player_id = as.integer(tm_player_id)
    ) %>%
    inner_join(
      crosswalk %>%
        select(
          tm_player_id,
          fotmob_player_id,
          tm_player_name,
          tm_current_club,
          tm_date_of_birth,
          tm_nationality,
          fotmob_position_group,
          fotmob_squad_role,
          crosswalk_match_method,
          crosswalk_candidate_score
        ),
      by = c("tm_player_id", "fotmob_player_id")
    ) %>%
    transmute(
      historical_run,
      season_name,
      tm_player_id,
      tm_player_name,
      tm_current_club,
      tm_date_of_birth,
      tm_nationality,
      fotmob_player_id,
      fotmob_player_name,
      fotmob_position_group,
      fotmob_squad_role,
      source_league_id,
      source_league_name,
      source_team_name,
      tournament_id,
      tournament_name,
      entry_id,
      has_deep_stats = as.logical(has_deep_stats),
      primary_team_name,
      primary_team_id = as.integer(primary_team_id),
      main_league_name,
      main_league_id = as.integer(main_league_id),
      crosswalk_match_method,
      crosswalk_candidate_score
    ) %>%
    distinct()
}

build_manifest <- function(match_master, monthly_all_master, monthly_league_master, historical_master) {
  tibble(
    dataset = c(
      "match_master",
      "monthly_all_comps",
      "monthly_source_league",
      "historical_coverage"
    ),
    rows = c(
      nrow(match_master),
      nrow(monthly_all_master),
      nrow(monthly_league_master),
      nrow(historical_master)
    ),
    unique_tm_players = c(
      dplyr::n_distinct(match_master$tm_player_id),
      dplyr::n_distinct(monthly_all_master$tm_player_id),
      dplyr::n_distinct(monthly_league_master$tm_player_id),
      dplyr::n_distinct(historical_master$tm_player_id)
    ),
    unique_fotmob_players = c(
      dplyr::n_distinct(match_master$fotmob_player_id),
      dplyr::n_distinct(monthly_all_master$fotmob_player_id),
      dplyr::n_distinct(monthly_league_master$fotmob_player_id),
      dplyr::n_distinct(historical_master$fotmob_player_id)
    )
  )
}

ensure_dir(master_dir)

crosswalk_safe <- load_safe_crosswalk(crosswalk_path)
match_master <- load_match_ratings(ratings_clean_path, crosswalk_safe)
monthly_all_master <- load_monthly_ratings(monthly_all_path, crosswalk_safe, "all_comps")
monthly_league_master <- load_monthly_ratings(monthly_league_path, crosswalk_safe, "source_league")
historical_master <- load_partial_historical_inventory(historical_root, crosswalk_safe)
manifest <- build_manifest(
  match_master,
  monthly_all_master,
  monthly_league_master,
  historical_master
)

write_csv(match_master, match_out, na = "")
message("Saved match-level master dataset to: ", match_out)

write_csv(monthly_all_master, monthly_all_out, na = "")
message("Saved monthly all-comps master dataset to: ", monthly_all_out)

write_csv(monthly_league_master, monthly_league_out, na = "")
message("Saved monthly source-league master dataset to: ", monthly_league_out)

write_csv(historical_master, historical_out, na = "")
message("Saved historical coverage master dataset to: ", historical_out)

write_csv(manifest, manifest_out, na = "")
message("Saved master dataset manifest to: ", manifest_out)
