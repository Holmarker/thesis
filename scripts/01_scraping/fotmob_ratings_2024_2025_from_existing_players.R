library(dplyr)
library(jsonlite)
library(readr)
library(stringr)
library(tibble)

args <- commandArgs(trailingOnly = TRUE)

league_config_path <- if (length(args) >= 1) args[[1]] else "RSpeciale/league_config_resolved_2024_2025.csv"
players_checkpoint_dir <- "RSpeciale/data/checkpoints/players"
ratings_checkpoint_dir <- if (length(args) >= 2) args[[2]] else "RSpeciale/data/historical/checkpoints/ratings"
ratings_out <- if (length(args) >= 3) args[[3]] else "RSpeciale/data/historical/fotmob_all_player_recent_matches_2024_2025.csv"
ratings_batch_size <- 25

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

normalize_name <- function(x) {
  x %>%
    iconv(from = "", to = "ASCII//TRANSLIT") %>%
    tolower() %>%
    str_replace_all("[^a-z0-9 ]", " ") %>%
    str_squish()
}

safe_slug <- function(x) {
  x %>%
    normalize_name() %>%
    str_replace_all(" ", "-")
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

infer_season_label <- function(start_date, end_date) {
  sprintf(
    "%s/%s",
    format(as.Date(start_date), "%Y"),
    format(as.Date(end_date), "%Y")
  )
}

empty_ratings_tbl <- function() {
  tibble(
    source_league_name = character(),
    source_league_id = integer(),
    season_start = as.Date(character()),
    season_end = as.Date(character()),
    fotmob_player_id = integer(),
    fotmob_player_name = character(),
    fotmob_team_id = integer(),
    fotmob_team_name = character(),
    opponent_team_id = integer(),
    opponent_team_name = character(),
    match_id = integer(),
    match_date = as.Date(character()),
    match_page_url = character(),
    league_id = integer(),
    league_name = character(),
    stage = character(),
    is_home_team = logical(),
    minutes_played = integer(),
    goals = integer(),
    assists = integer(),
    yellow_cards = integer(),
    red_cards = integer(),
    rating = double(),
    is_top_rating = logical(),
    player_of_the_match = logical(),
    on_bench = logical()
  )
}

get_fotmob_page_json <- function(url) {
  html <- paste(readLines(url, warn = FALSE), collapse = "\n")
  json_txt <- sub('.*<script id="__NEXT_DATA__" type="application/json">', "", html)
  json_txt <- sub("</script>.*", "", json_txt)
  fromJSON(json_txt, simplifyVector = FALSE)
}

get_player_recent_matches <- function(player_row) {
  url <- sprintf(
    "https://www.fotmob.com/players/%s/%s",
    player_row$fotmob_player_id,
    player_row$fotmob_player_slug
  )

  payload <- tryCatch(get_fotmob_page_json(url), error = function(e) NULL)

  if (is.null(payload)) {
    return(empty_ratings_tbl())
  }

  player_key <- sprintf("player:%s", player_row$fotmob_player_id)
  player_payload <- payload$props$pageProps$fallback[[player_key]]

  if (is.null(player_payload) || is.null(player_payload$recentMatches)) {
    return(empty_ratings_tbl())
  }

  bind_rows(lapply(player_payload$recentMatches, function(x) {
    tibble(
      source_league_name = player_row$source_league_name,
      source_league_id = as.integer(player_row$source_league_id),
      season_start = as.Date(player_row$season_start),
      season_end = as.Date(player_row$season_end),
      fotmob_player_id = player_payload$id,
      fotmob_player_name = player_payload$name,
      fotmob_team_id = x$teamId %||% NA_integer_,
      fotmob_team_name = x$teamName %||% NA_character_,
      opponent_team_id = x$opponentTeamId %||% NA_integer_,
      opponent_team_name = x$opponentTeamName %||% NA_character_,
      match_id = x$id %||% NA_integer_,
      match_date = as.Date(x$matchDate$utcTime %||% NA_character_),
      match_page_url = x$matchPageUrl %||% NA_character_,
      league_id = x$leagueId %||% NA_integer_,
      league_name = x$leagueName %||% NA_character_,
      stage = x$stage %||% NA_character_,
      is_home_team = x$isHomeTeam %||% NA,
      minutes_played = x$minutesPlayed %||% NA_integer_,
      goals = x$goals %||% NA_integer_,
      assists = x$assists %||% NA_integer_,
      yellow_cards = x$yellowCards %||% NA_integer_,
      red_cards = x$redCards %||% NA_integer_,
      rating = suppressWarnings(as.numeric(x$ratingProps$rating %||% NA_character_)),
      is_top_rating = x$ratingProps$isTopRating %||% NA,
      player_of_the_match = x$playerOfTheMatch %||% NA,
      on_bench = x$onBench %||% NA
    )
  })) %>%
    filter(
      !is.na(match_date),
      match_date >= as.Date(player_row$season_start),
      match_date <= as.Date(player_row$season_end)
    )
}

coerce_players_checkpoint <- function(df) {
  df %>%
    mutate(
      source_league_name = as.character(source_league_name),
      source_league_id = as.integer(source_league_id),
      source_ccode = as.character(source_ccode),
      season_start = as.Date(season_start),
      season_end = as.Date(season_end),
      fotmob_team_id = as.integer(fotmob_team_id),
      fotmob_team_name = as.character(fotmob_team_name),
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_player_name = as.character(fotmob_player_name),
      shirt_number = as.character(shirt_number),
      age = as.integer(age),
      country_code = as.character(country_code),
      country_name = as.character(country_name),
      position_group = as.character(position_group),
      squad_role = as.character(squad_role),
      fotmob_player_slug = as.character(fotmob_player_slug)
    )
}

coerce_ratings_checkpoint <- function(df) {
  df %>%
    mutate(
      source_league_name = as.character(source_league_name),
      source_league_id = as.integer(source_league_id),
      season_start = as.Date(season_start),
      season_end = as.Date(season_end),
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_player_name = as.character(fotmob_player_name),
      fotmob_team_id = as.integer(fotmob_team_id),
      fotmob_team_name = as.character(fotmob_team_name),
      opponent_team_id = as.integer(opponent_team_id),
      opponent_team_name = as.character(opponent_team_name),
      match_id = as.integer(match_id),
      match_date = as.Date(match_date),
      match_page_url = as.character(match_page_url),
      league_id = as.integer(league_id),
      league_name = as.character(league_name),
      stage = as.character(stage),
      is_home_team = as.logical(is_home_team),
      minutes_played = as.integer(minutes_played),
      goals = as.integer(goals),
      assists = as.integer(assists),
      yellow_cards = as.integer(yellow_cards),
      red_cards = as.integer(red_cards),
      rating = as.numeric(rating),
      is_top_rating = as.logical(is_top_rating),
      player_of_the_match = as.logical(player_of_the_match),
      on_bench = as.logical(on_bench)
    )
}

get_players_checkpoint_path <- function(league_name, league_id) {
  file.path(
    players_checkpoint_dir,
    sprintf("%s_%s_players.csv", league_id, safe_slug(league_name))
  )
}

get_ratings_checkpoint_path <- function(league_name, league_id) {
  file.path(
    ratings_checkpoint_dir,
    sprintf("%s_%s_ratings.csv", league_id, safe_slug(league_name))
  )
}

load_league_players <- function(league_row) {
  checkpoint_path <- get_players_checkpoint_path(league_row$league_name, league_row$league_id)

  if (!file.exists(checkpoint_path)) {
    message("Missing players checkpoint for ", league_row$league_name, ": ", checkpoint_path)
    return(tibble())
  }

  read_csv(checkpoint_path, show_col_types = FALSE) %>%
    coerce_players_checkpoint() %>%
    mutate(
      season_start = as.Date(league_row$season_start),
      season_end = as.Date(league_row$season_end)
    ) %>%
    distinct(fotmob_player_id, .keep_all = TRUE) %>%
    arrange(fotmob_team_name, fotmob_player_name)
}

fetch_or_load_ratings <- function(league_row, league_players, season_label) {
  checkpoint_path <- get_ratings_checkpoint_path(league_row$league_name, league_row$league_id)

  existing <- empty_ratings_tbl()
  processed_ids <- integer()

  if (file.exists(checkpoint_path)) {
    message("Loading ratings checkpoint for ", league_row$league_name)
    existing <- read_csv(checkpoint_path, show_col_types = FALSE) %>%
      coerce_ratings_checkpoint()
    processed_ids <- unique(existing$fotmob_player_id)
  }

  remaining_players <- league_players %>%
    filter(!(fotmob_player_id %in% processed_ids))

  ratings_accum <- existing

  if (nrow(remaining_players) == 0) {
    return(ratings_accum)
  }

  batch_accum <- empty_ratings_tbl()

  for (i in seq_len(nrow(remaining_players))) {
    player_row <- remaining_players[i, ]
    message(
      "Fetching ",
      season_label,
      " recent matches for ",
      player_row$fotmob_player_name,
      " [", player_row$source_league_name, "] (",
      i, "/", nrow(remaining_players), ")"
    )

    player_ratings <- get_player_recent_matches(player_row)
    batch_accum <- bind_rows(batch_accum, player_ratings)

    if (i %% ratings_batch_size == 0 || i == nrow(remaining_players)) {
      ratings_accum <- bind_rows(ratings_accum, batch_accum) %>%
        filter(!is.na(match_id)) %>%
        distinct(fotmob_player_id, match_id, .keep_all = TRUE) %>%
        arrange(source_league_name, match_date, fotmob_player_name, match_id)

      write_csv(ratings_accum, checkpoint_path, na = "")
      message(
        "Saved ",
        season_label,
        " ratings checkpoint for ",
        league_row$league_name,
        " after ",
        i,
        " players"
      )
      batch_accum <- empty_ratings_tbl()
    }
  }

  ratings_accum
}

ensure_dir(ratings_checkpoint_dir)

league_config <- read_csv(league_config_path, show_col_types = FALSE) %>%
  filter(active, match_status == "matched") %>%
  mutate(
    league_id = as.integer(league_id),
    season_start = as.Date(season_start),
    season_end = as.Date(season_end)
  )

season_label <- infer_season_label(
  min(league_config$season_start, na.rm = TRUE),
  max(league_config$season_end, na.rm = TRUE)
)

message("Active matched leagues in ", season_label, " config: ", nrow(league_config))

fotmob_ratings <- bind_rows(
  lapply(seq_len(nrow(league_config)), function(i) {
    league_row <- league_config[i, ]
    league_players <- load_league_players(league_row)

    if (nrow(league_players) == 0) {
      return(empty_ratings_tbl())
    }

    fetch_or_load_ratings(league_row, league_players, season_label)
  })
) %>%
  distinct(fotmob_player_id, match_id, .keep_all = TRUE) %>%
  arrange(source_league_name, match_date, fotmob_player_name, match_id)

write_csv(fotmob_ratings, ratings_out, na = "")
message("Saved combined ", season_label, " recent-match ratings to: ", ratings_out)
