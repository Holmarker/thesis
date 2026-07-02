library(dplyr)
library(lubridate)
library(readr)
library(stringr)
library(tibble)

path_in <- function(...) file.path(...)

historical_ratings_dir <- path_in("data", "historical", "checkpoints", "ratings")
crosswalk_path <- path_in("data", "fotmob_transfermarkt_crosswalk_confirmed.csv")
monthly_all_path <- path_in("data", "master", "fotmob_master_monthly_all_comps.csv")
monthly_source_path <- path_in("data", "master", "fotmob_master_monthly_source_league.csv")
manifest_path <- path_in("data", "master", "fotmob_master_manifest.csv")

target_season_slug <- Sys.getenv("FOTMOB_HISTORICAL_SEASON_SLUG", unset = "2023-2024")
target_files <- list.files(
  historical_ratings_dir,
  pattern = paste0("_", target_season_slug, "_ratings[.]csv$"),
  full.names = TRUE
)

if (length(target_files) == 0) {
  stop("No historical ratings files found for season slug: ", target_season_slug)
}

safe_write_csv <- function(df, path) {
  tmp_path <- paste0(path, ".tmp")
  df <- df %>%
    mutate(across(where(is.character), ~ iconv(.x, from = "", to = "UTF-8", sub = "")))
  utils::write.csv(df, tmp_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")

  if (file.exists(path)) {
    file.remove(path)
  }

  file.rename(tmp_path, path)
}

decode_fotmob_text <- function(x) {
  ifelse(
    is.na(x),
    NA_character_,
    utils::URLdecode(gsub("<([0-9A-Fa-f]{2})>", "%\\1", x))
  )
}

read_ratings_file <- function(path) {
  read_csv(path, show_col_types = FALSE, col_types = cols(.default = col_character())) %>%
    mutate(
      source_league_name = as.character(source_league_name),
      source_league_id = as.integer(source_league_id),
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_player_name = decode_fotmob_text(as.character(fotmob_player_name)),
      fotmob_team_id = as.integer(fotmob_team_id),
      match_id = as.integer(match_id),
      match_date = as.Date(match_date),
      league_id = as.integer(league_id),
      minutes_played = as.integer(minutes_played),
      goals = as.integer(goals),
      assists = as.integer(assists),
      yellow_cards = as.integer(yellow_cards),
      red_cards = as.integer(red_cards),
      rating = as.numeric(rating),
      is_top_rating = as.logical(is_top_rating),
      player_of_the_match = as.logical(player_of_the_match),
      on_bench = as.logical(on_bench),
      Month = floor_date(match_date, unit = "month"),
      is_source_league_match = league_id == source_league_id
    ) %>%
    filter(!is.na(match_id), !is.na(fotmob_player_id), !is.na(match_date)) %>%
    distinct(source_league_id, fotmob_player_id, match_id, .keep_all = TRUE)
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
      fotmob_player_name_crosswalk = fotmob_player_name,
      fotmob_position_group = position_group,
      fotmob_squad_role = squad_role,
      source_league_name = source_league_name,
      source_league_id = as.integer(source_league_id),
      crosswalk_match_method = match_method,
      crosswalk_candidate_score = as.numeric(candidate_score)
    ) %>%
    distinct(tm_player_id, fotmob_player_id, source_league_id, .keep_all = TRUE)
}

weighted_mean_safe <- function(x, w) {
  keep <- !is.na(x) & !is.na(w) & w > 0
  if (!any(keep)) {
    return(NA_real_)
  }
  stats::weighted.mean(x[keep], w[keep])
}

summarise_monthly <- function(df, monthly_scope) {
  df %>%
    group_by(fotmob_player_id, Month) %>%
    summarise(
      fotmob_player_name = first(fotmob_player_name),
      source_league_name = first(source_league_name),
      source_league_id = first(source_league_id),
      monthly_scope = monthly_scope,
      matches = n_distinct(match_id),
      appearances = sum(coalesce(minutes_played, 0L) > 0L, na.rm = TRUE),
      starts_proxy = sum(!coalesce(on_bench, FALSE), na.rm = TRUE),
      minutes = sum(minutes_played, na.rm = TRUE),
      goals = sum(goals, na.rm = TRUE),
      assists = sum(assists, na.rm = TRUE),
      yellow_cards = sum(yellow_cards, na.rm = TRUE),
      red_cards = sum(red_cards, na.rm = TRUE),
      mean_rating = mean(rating, na.rm = TRUE),
      mean_rating = if_else(is.nan(mean_rating), NA_real_, mean_rating),
      minutes_weighted_rating = weighted_mean_safe(rating, minutes_played),
      top_ratings = sum(coalesce(is_top_rating, FALSE), na.rm = TRUE),
      player_of_match_awards = sum(coalesce(player_of_the_match, FALSE), na.rm = TRUE),
      .groups = "drop"
    )
}

to_master_monthly <- function(monthly, crosswalk) {
  monthly %>%
    inner_join(crosswalk, by = c("fotmob_player_id", "source_league_id", "source_league_name")) %>%
    transmute(
      tm_player_id,
      tm_player_name,
      tm_current_club,
      tm_date_of_birth,
      tm_nationality,
      fotmob_player_id,
      fotmob_player_name = coalesce(fotmob_player_name, fotmob_player_name_crosswalk),
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
      mean_rating = as.numeric(mean_rating),
      minutes_weighted_rating = as.numeric(minutes_weighted_rating),
      top_ratings = as.integer(top_ratings),
      player_of_match_awards = as.integer(player_of_match_awards),
      crosswalk_match_method,
      crosswalk_candidate_score
    )
}

merge_monthly <- function(path, additions) {
  existing <- read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      across(
        c(
          source_league_id, tm_player_id, fotmob_player_id,
          matches, appearances, starts_proxy, minutes, goals, assists,
          yellow_cards, red_cards, top_ratings, player_of_match_awards
        ),
        ~ suppressWarnings(as.integer(.x))
      ),
      across(
        c(mean_rating, minutes_weighted_rating, crosswalk_candidate_score),
        ~ suppressWarnings(as.numeric(.x))
      )
    ) %>%
    filter(!is.na(Month), !is.na(source_league_id), !is.na(fotmob_player_id))

  bind_rows(existing, additions) %>%
    arrange(Month, tm_player_id, source_league_id, monthly_scope) %>%
    distinct(tm_player_id, fotmob_player_id, source_league_id, Month, monthly_scope, .keep_all = TRUE)
}

message("Reading historical ratings files: ", length(target_files))
ratings <- bind_rows(lapply(target_files, read_ratings_file))
crosswalk <- load_safe_crosswalk(crosswalk_path)

monthly_all_add <- ratings %>%
  summarise_monthly("all_comps") %>%
  to_master_monthly(crosswalk)

monthly_source_add <- ratings %>%
  filter(is_source_league_match) %>%
  summarise_monthly("source_league") %>%
  to_master_monthly(crosswalk)

message("New monthly all-comps rows matched to crosswalk: ", nrow(monthly_all_add))
message("New monthly source-league rows matched to crosswalk: ", nrow(monthly_source_add))

monthly_all <- merge_monthly(monthly_all_path, monthly_all_add)
monthly_source <- merge_monthly(monthly_source_path, monthly_source_add)

safe_write_csv(monthly_all, monthly_all_path)
safe_write_csv(monthly_source, monthly_source_path)

manifest <- read_csv(manifest_path, show_col_types = FALSE) %>%
  mutate(
    rows = case_when(
      dataset == "monthly_all_comps" ~ nrow(monthly_all),
      dataset == "monthly_source_league" ~ nrow(monthly_source),
      TRUE ~ rows
    ),
    unique_tm_players = case_when(
      dataset == "monthly_all_comps" ~ n_distinct(monthly_all$tm_player_id),
      dataset == "monthly_source_league" ~ n_distinct(monthly_source$tm_player_id),
      TRUE ~ unique_tm_players
    ),
    unique_fotmob_players = case_when(
      dataset == "monthly_all_comps" ~ n_distinct(monthly_all$fotmob_player_id),
      dataset == "monthly_source_league" ~ n_distinct(monthly_source$fotmob_player_id),
      TRUE ~ unique_fotmob_players
    )
  )

safe_write_csv(manifest, manifest_path)

message("Saved updated monthly master files and manifest.")
