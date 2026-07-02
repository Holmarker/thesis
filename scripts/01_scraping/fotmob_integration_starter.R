library(dplyr)
library(jsonlite)
library(lubridate)
library(openxlsx)
library(purrr)
library(readr)
library(stringr)
library(tibble)

# Multi-league FotMob integration.
# Workflow:
# 1. Read active leagues from league_config_resolved.csv.
# 2. Pull teams for each league.
# 3. Pull squad pages to get FotMob player IDs.
# 4. Pull player pages to get recent match ratings.
# 5. Build candidate matches to Transfermarkt player IDs.

bios_path <- Sys.getenv(
  "FOTMOB_BIOS_PATH",
  "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller data.xlsx"
)
league_config_path <- Sys.getenv(
  "FOTMOB_LEAGUE_CONFIG",
  "RSpeciale/league_config_resolved.csv"
)

teams_out <- "RSpeciale/data/fotmob_all_league_teams.csv"
players_out <- "RSpeciale/data/fotmob_all_league_players.csv"
ratings_out <- "RSpeciale/data/fotmob_all_player_recent_matches.csv"
crosswalk_out <- "RSpeciale/data/fotmob_all_transfermarkt_crosswalk_candidates.csv"
checkpoint_dir <- "RSpeciale/data/checkpoints"
teams_checkpoint_dir <- file.path(checkpoint_dir, "teams")
players_checkpoint_dir <- file.path(checkpoint_dir, "players")
ratings_checkpoint_dir <- file.path(checkpoint_dir, "ratings")
ratings_batch_size <- 25

normalize_name <- function(x) {
  x %>%
    iconv(from = "", to = "ASCII//TRANSLIT") %>%
    tolower() %>%
    str_replace_all("[^a-z0-9 ]", " ") %>%
    str_squish()
}

normalize_team <- function(x) {
  x %>%
    normalize_name() %>%
    str_replace_all("\\bfc\\b|\\bcf\\b|\\bafc\\b", "") %>%
    str_squish()
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

empty_players_tbl <- function() {
  tibble(
    source_league_name = character(),
    source_league_id = integer(),
    source_ccode = character(),
    season_start = as.Date(character()),
    season_end = as.Date(character()),
    fotmob_team_id = integer(),
    fotmob_team_name = character(),
    fotmob_player_id = integer(),
    fotmob_player_name = character(),
    shirt_number = character(),
    age = integer(),
    country_code = character(),
    country_name = character(),
    position_group = character(),
    squad_role = character()
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

get_fotmob_json <- function(url) {
  fromJSON(url, simplifyVector = FALSE)
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

safe_slug <- function(x) {
  x %>%
    normalize_name() %>%
    str_replace_all(" ", "-")
}

get_fotmob_page_json <- function(url) {
  html <- paste(readLines(url, warn = FALSE), collapse = "\n")
  json_txt <- sub('.*<script id="__NEXT_DATA__" type="application/json">', "", html)
  json_txt <- sub("</script>.*", "", json_txt)
  fromJSON(json_txt, simplifyVector = FALSE)
}

extract_table_teams <- function(table_obj) {
  teams <- table_obj$all %||% list()

  if (length(teams) == 0) {
    return(tibble())
  }

  tibble(
    fotmob_team_id = map_int(teams, \(x) x$id),
    fotmob_team_name = map_chr(teams, \(x) x$name),
    fotmob_team_short_name = map_chr(teams, \(x) x$shortName),
    fotmob_team_page_url = map_chr(teams, \(x) x$pageUrl)
  )
}

extract_league_teams_from_payload <- function(payload) {
  direct_table <- payload$data$table %||% NULL

  if (!is.null(direct_table) && length(direct_table$all %||% list()) > 0) {
    return(extract_table_teams(direct_table))
  }

  composite_tables <- payload$data$tables %||% list()

  if (length(composite_tables) == 0) {
    return(tibble())
  }

  bind_rows(lapply(composite_tables, function(table_group) {
    extract_table_teams(table_group$table %||% list())
  })) %>%
    distinct(fotmob_team_id, .keep_all = TRUE)
}

get_league_teams <- function(league_row) {
  payload <- get_fotmob_json(
    sprintf("https://www.fotmob.com/api/data/tltable?leagueId=%s", league_row$league_id)
  )[[1]]

  teams <- extract_league_teams_from_payload(payload)

  if (nrow(teams) == 0) {
    return(
      tibble(
        source_league_name = character(),
        source_league_id = integer(),
        source_ccode = character(),
        season_start = as.Date(character()),
        season_end = as.Date(character()),
        fotmob_team_id = integer(),
        fotmob_team_name = character(),
        fotmob_team_short_name = character(),
        fotmob_team_page_url = character(),
        fotmob_team_slug = character(),
        fotmob_team_name_clean = character()
      )
    )
  }

  teams %>%
    mutate(
    source_league_name = league_row$league_name,
    source_league_id = as.integer(league_row$league_id),
    source_ccode = league_row$ccode,
    season_start = as.Date(league_row$season_start),
    season_end = as.Date(league_row$season_end)
    ) %>%
    mutate(
      fotmob_team_slug = basename(fotmob_team_page_url),
      fotmob_team_name_clean = normalize_team(fotmob_team_name)
    ) %>%
    select(
      source_league_name,
      source_league_id,
      source_ccode,
      season_start,
      season_end,
      fotmob_team_id,
      fotmob_team_name,
      fotmob_team_short_name,
      fotmob_team_page_url,
      fotmob_team_slug,
      fotmob_team_name_clean
    )
}

extract_squad_group <- function(group, team_row) {
  members <- group$members %||% list()

  if (length(members) == 0) {
    return(empty_players_tbl())
  }

  bind_rows(lapply(members, function(player) {
    tibble(
      source_league_name = team_row$source_league_name,
      source_league_id = as.integer(team_row$source_league_id),
      source_ccode = team_row$source_ccode,
      season_start = as.Date(team_row$season_start),
      season_end = as.Date(team_row$season_end),
      fotmob_team_id = as.integer(team_row$fotmob_team_id),
      fotmob_team_name = team_row$fotmob_team_name,
      fotmob_player_id = player$id %||% NA_integer_,
      fotmob_player_name = player$name %||% NA_character_,
      shirt_number = as.character(player$shirtNumber %||% NA_character_),
      age = player$age %||% NA_integer_,
      country_code = as.character(player$ccode %||% NA_character_),
      country_name = as.character(player$cname %||% NA_character_),
      position_group = as.character(group$title %||% NA_character_),
      squad_role = as.character(player$role$fallback %||% NA_character_)
    )
  }))
}

get_team_players <- function(team_row) {
  url <- sprintf(
    "https://www.fotmob.com/teams/%s/squad/%s",
    team_row$fotmob_team_id,
    team_row$fotmob_team_slug
  )

  payload <- tryCatch(get_fotmob_page_json(url), error = function(e) NULL)

  if (is.null(payload)) {
    return(empty_players_tbl())
  }

  squad_groups <- payload$props$pageProps$fallback[[sprintf("team-%s", team_row$fotmob_team_id)]]$squad$squad

  if (is.null(squad_groups) || length(squad_groups) == 0) {
    return(empty_players_tbl())
  }

  bind_rows(lapply(squad_groups, extract_squad_group, team_row = team_row))
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

  recent_matches <- player_payload$recentMatches

  bind_rows(lapply(recent_matches, function(x) {
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

load_transfermarkt_players <- function(path) {
  read.xlsx(path) %>%
    transmute(
      tm_player_id = as.integer(player_id),
      player_name_tm = PlayerName,
      player_name_tm_clean = normalize_name(PlayerName),
      current_club_tm = CurrentClub,
      current_club_tm_clean = normalize_team(CurrentClub),
      date_of_birth = ymd(DateOfBirth),
      nationality = nationality_new,
      player_url
    ) %>%
    distinct()
}

build_crosswalk_candidates <- function(tm_players, fotmob_players) {
  fotmob_master <- fotmob_players %>%
    transmute(
      source_league_name,
      source_league_id,
      fotmob_player_id,
      fotmob_player_name,
      fotmob_player_name_clean = normalize_name(fotmob_player_name),
      fotmob_team_id,
      fotmob_team_name,
      fotmob_team_name_clean = normalize_team(fotmob_team_name)
    ) %>%
    distinct()

  exact_name_team <- tm_players %>%
    inner_join(
      fotmob_master,
      by = c(
        "player_name_tm_clean" = "fotmob_player_name_clean",
        "current_club_tm_clean" = "fotmob_team_name_clean"
      )
    ) %>%
    mutate(match_method = "exact_name_plus_team")

  exact_name_only <- tm_players %>%
    inner_join(
      fotmob_master,
      by = c("player_name_tm_clean" = "fotmob_player_name_clean")
    ) %>%
    filter(!(tm_player_id %in% exact_name_team$tm_player_id)) %>%
    mutate(match_method = "exact_name_only")

  bind_rows(exact_name_team, exact_name_only) %>%
    arrange(source_league_name, match_method, player_name_tm, fotmob_team_name)
}

get_teams_checkpoint_path <- function(league_row) {
  file.path(
    teams_checkpoint_dir,
    sprintf("%s_%s_teams.csv", league_row$league_id, safe_slug(league_row$league_name))
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

coerce_teams_checkpoint <- function(df) {
  df %>%
    mutate(
      source_league_id = as.integer(source_league_id),
      season_start = as.Date(season_start),
      season_end = as.Date(season_end),
      fotmob_team_id = as.integer(fotmob_team_id)
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
      source_league_id = as.integer(source_league_id),
      season_start = as.Date(season_start),
      season_end = as.Date(season_end),
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_team_id = as.integer(fotmob_team_id),
      opponent_team_id = as.integer(opponent_team_id),
      match_id = as.integer(match_id),
      match_date = as.Date(match_date),
      league_id = as.integer(league_id),
      minutes_played = as.integer(minutes_played),
      goals = as.integer(goals),
      assists = as.integer(assists),
      yellow_cards = as.integer(yellow_cards),
      red_cards = as.integer(red_cards),
      rating = as.numeric(rating),
      is_home_team = as.logical(is_home_team),
      is_top_rating = as.logical(is_top_rating),
      player_of_the_match = as.logical(player_of_the_match),
      on_bench = as.logical(on_bench)
    )
}

fetch_or_load_teams <- function(league_row) {
  checkpoint_path <- get_teams_checkpoint_path(league_row)

  if (file.exists(checkpoint_path)) {
    message("Loading teams checkpoint for ", league_row$league_name)
    teams_checkpoint <- 
      read_csv(checkpoint_path, show_col_types = FALSE) %>%
        coerce_teams_checkpoint()

    if (nrow(teams_checkpoint) > 0) {
      return(teams_checkpoint)
    }

    message("Teams checkpoint for ", league_row$league_name, " is empty; refetching")
  }

  message("Fetching teams for ", league_row$league_name, " (", league_row$league_id, ")")
  teams <- get_league_teams(league_row)
  write_csv(teams, checkpoint_path, na = "")
  teams
}

fetch_or_load_players <- function(league_name, league_id, league_teams) {
  checkpoint_path <- get_players_checkpoint_path(league_name, league_id)

  if (file.exists(checkpoint_path)) {
    message("Loading players checkpoint for ", league_name)
    players_checkpoint <-
      read_csv(checkpoint_path, show_col_types = FALSE) %>%
        coerce_players_checkpoint()

    if (nrow(players_checkpoint) > 0) {
      return(players_checkpoint)
    }

    message("Players checkpoint for ", league_name, " is empty; refetching")
  }

  players <- bind_rows(
    empty_players_tbl(),
    lapply(seq_len(nrow(league_teams)), function(i) {
      team_row <- league_teams[i, ]
      message("Fetching squad for ", team_row$fotmob_team_name, " [", team_row$source_league_name, "]")
      get_team_players(team_row)
    })
  ) %>%
    filter(!is.na(fotmob_player_id), !is.na(fotmob_player_name)) %>%
    distinct(fotmob_player_id, .keep_all = TRUE) %>%
    mutate(
      fotmob_player_slug = fotmob_player_name %>%
        normalize_name() %>%
        str_replace_all(" ", "-")
    ) %>%
    arrange(source_league_name, fotmob_team_name, fotmob_player_name)

  write_csv(players, checkpoint_path, na = "")
  players
}

fetch_or_load_ratings <- function(league_name, league_id, league_players) {
  checkpoint_path <- get_ratings_checkpoint_path(league_name, league_id)

  existing <- empty_ratings_tbl()
  processed_ids <- integer()

  if (file.exists(checkpoint_path)) {
    message("Loading ratings checkpoint for ", league_name)
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
      "Fetching recent matches for ",
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
        "Saved ratings checkpoint for ",
        league_name,
        " after ",
        i,
        " players"
      )
      batch_accum <- empty_ratings_tbl()
    }
  }

  ratings_accum
}

ensure_dir(checkpoint_dir)
ensure_dir(teams_checkpoint_dir)
ensure_dir(players_checkpoint_dir)
ensure_dir(ratings_checkpoint_dir)

league_config <- read_csv(league_config_path, show_col_types = FALSE) %>%
  filter(active, match_status == "matched") %>%
  mutate(
    league_id = as.integer(league_id),
    season_start = as.Date(season_start),
    season_end = as.Date(season_end)
  )

message("Active matched leagues: ", nrow(league_config))

fotmob_teams <- bind_rows(
  lapply(seq_len(nrow(league_config)), function(i) {
    fetch_or_load_teams(league_config[i, ])
  })
) %>%
  arrange(source_league_name, fotmob_team_name)

write_csv(fotmob_teams, teams_out, na = "")
message("Saved team list to: ", teams_out)

fotmob_players <- bind_rows(
  lapply(seq_len(nrow(league_config)), function(i) {
    league_row <- league_config[i, ]
    league_teams <- fotmob_teams %>%
      filter(source_league_id == league_row$league_id)
    fetch_or_load_players(league_row$league_name, league_row$league_id, league_teams)
  })
) %>%
  distinct(fotmob_player_id, .keep_all = TRUE) %>%
  arrange(source_league_name, fotmob_team_name, fotmob_player_name)

write_csv(fotmob_players, players_out, na = "")
message("Saved player list to: ", players_out)

fotmob_ratings <- bind_rows(
  lapply(seq_len(nrow(league_config)), function(i) {
    league_row <- league_config[i, ]
    league_players <- fotmob_players %>%
      filter(source_league_id == league_row$league_id)
    fetch_or_load_ratings(league_row$league_name, league_row$league_id, league_players)
  })
) %>%
  distinct(fotmob_player_id, match_id, .keep_all = TRUE) %>%
  arrange(source_league_name, match_date, fotmob_player_name, match_id)

write_csv(fotmob_ratings, ratings_out, na = "")
message("Saved recent-match ratings to: ", ratings_out)

tm_players <- load_transfermarkt_players(bios_path)
crosswalk_candidates <- build_crosswalk_candidates(tm_players, fotmob_players)
write_csv(crosswalk_candidates, crosswalk_out, na = "")
message("Saved crosswalk candidates to: ", crosswalk_out)
