library(dplyr)
library(jsonlite)
library(lubridate)
library(readr)
library(stringr)
library(tibble)

args <- commandArgs(trailingOnly = TRUE)

project_root <- if (dir.exists("data")) "." else "RSpeciale"
season_name <- if (length(args) >= 1) args[[1]] else "2023/2024"
league_config_path <- if (length(args) >= 2) args[[2]] else file.path(project_root, "league_config_resolved_2024_2025.csv")
limit_leagues <- if (length(args) >= 3) as.integer(args[[3]]) else NA_integer_
limit_matches <- if (length(args) >= 4) as.integer(args[[4]]) else NA_integer_
request_delay <- suppressWarnings(as.numeric(Sys.getenv("FOTMOB_REQUEST_DELAY", unset = "0.35")))
if (is.na(request_delay) || request_delay < 0) {
  request_delay <- 0.35
}

fixtures_dir <- file.path(project_root, "data", "historical", "match_fixtures", str_replace_all(season_name, "/", "_"))
ratings_dir <- file.path(project_root, "data", "historical", "checkpoints", "ratings")
manifest_out <- file.path(project_root, "data", "historical", paste0("fotmob_match_rating_scrape_manifest_", str_replace_all(season_name, "/", "_"), ".csv"))

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

safe_slug <- function(x) {
  x %>%
    iconv(from = "", to = "ASCII//TRANSLIT") %>%
    tolower() %>%
    str_replace_all("[^a-z0-9 ]", " ") %>%
    str_squish() %>%
    str_replace_all(" ", "-")
}

season_query <- function(x) {
  str_replace(x, "/", "-")
}

season_queries_for_league <- function(target_season, league_row) {
  start_month <- as.integer(format(as.Date(league_row$season_start), "%m"))
  start_year <- as.integer(str_sub(target_season, 1, 4))

  if (!is.na(start_month) && start_month == 1L) {
    return(as.character(c(start_year, start_year + 1L)))
  }

  season_query(target_season)
}

season_dates <- function(x) {
  start_year <- as.integer(str_sub(x, 1, 4))
  list(
    start = as.Date(sprintf("%s-07-01", start_year)),
    end = as.Date(sprintf("%s-06-30", start_year + 1L))
  )
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

get_build_id <- function() {
  html <- paste(readLines("https://www.fotmob.com", warn = FALSE), collapse = "\n")
  json_txt <- sub('.*<script id="__NEXT_DATA__" type="application/json">', "", html)
  json_txt <- sub("</script>.*", "", json_txt)
  payload <- fromJSON(json_txt, simplifyVector = FALSE)
  payload$buildId
}

scalar_chr <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(NA_character_)
  }
  as.character(x[[1]])
}

scalar_int <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(NA_integer_)
  }
  suppressWarnings(as.integer(x[[1]]))
}

scalar_num <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(x[[1]]))
}

empty_fixture_tbl <- function() {
  tibble(
    source_league_name = character(),
    source_league_id = integer(),
    season_name = character(),
    season_start = as.Date(character()),
    season_end = as.Date(character()),
    round = character(),
    round_name = character(),
    match_id = integer(),
    match_date = as.Date(character()),
    match_time_utc = character(),
    match_page_url = character(),
    home_team_id = integer(),
    home_team_name = character(),
    away_team_id = integer(),
    away_team_name = character(),
    score = character(),
    finished = logical()
  )
}

empty_ratings_tbl <- function() {
  tibble(
    source_league_name = character(),
    source_league_id = integer(),
    season_name = character(),
    ratings_source = character(),
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

fetch_fixtures <- function(league_row, build_id, season_name) {
  slug <- safe_slug(league_row$league_name)
  dates <- season_dates(season_name)
  queries <- season_queries_for_league(season_name, league_row)
  matches <- unlist(lapply(queries, function(query) {
    url <- sprintf(
      "https://www.fotmob.com/_next/data/%s/leagues/%s/matches/%s.json?season=%s",
      build_id,
      league_row$league_id,
      slug,
      query
    )

    payload <- tryCatch(fromJSON(url, simplifyVector = FALSE), error = function(e) NULL)
    payload$pageProps$fixtures$allMatches %||% list()
  }), recursive = FALSE)

  if (length(matches) == 0) {
    return(empty_fixture_tbl())
  }

  bind_rows(lapply(matches, function(match) {
    utc_time <- scalar_chr(match$status$utcTime)

    tibble(
      source_league_name = league_row$league_name,
      source_league_id = as.integer(league_row$league_id),
      season_name = season_name,
      season_start = dates$start,
      season_end = dates$end,
      round = scalar_chr(match$round),
      round_name = scalar_chr(match$roundName),
      match_id = scalar_int(match$id),
      match_date = as.Date(utc_time),
      match_time_utc = utc_time,
      match_page_url = scalar_chr(match$pageUrl),
      home_team_id = scalar_int(match$home$id),
      home_team_name = scalar_chr(match$home$name),
      away_team_id = scalar_int(match$away$id),
      away_team_name = scalar_chr(match$away$name),
      score = scalar_chr(match$status$scoreStr),
      finished = as.logical(match$status$finished %||% FALSE)
    )
  })) %>%
    filter(
      !is.na(match_id),
      finished,
      match_date >= dates$start,
      match_date <= dates$end
    ) %>%
    distinct(match_id, .keep_all = TRUE)
}

fetch_match_details <- function(match_id, x_mas = "", cookie = "") {
  url <- sprintf("https://www.fotmob.com/api/data/matchDetails?matchId=%s", match_id)
  args <- c(
    "-L",
    "-s",
    "-H",
    shQuote("User-Agent: Mozilla/5.0"),
    "-H",
    shQuote("Accept: application/json, text/plain, */*"),
    "-H",
    shQuote("Referer: https://www.fotmob.com/")
  )

  if (nzchar(x_mas)) {
    args <- c(args, "-H", shQuote(paste0("x-mas: ", x_mas)))
  }

  if (nzchar(cookie)) {
    args <- c(args, "-H", shQuote(paste0("Cookie: ", cookie)))
  }

  args <- c(args, shQuote(url))

  out <- tryCatch(system2("curl", args = args, stdout = TRUE, stderr = TRUE), error = function(e) character())
  txt <- paste(out, collapse = "\n")

  if (!str_starts(str_squish(txt), "\\{")) {
    return(NULL)
  }

  tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
}

stat_value <- function(player_stats, key) {
  groups <- player_stats$stats %||% list()

  for (group in groups) {
    stats <- group$stats %||% list()

    for (stat_name in names(stats)) {
      item <- stats[[stat_name]]
      if (identical(item$key %||% NA_character_, key)) {
        return(scalar_num(item$stat$value))
      }
    }
  }

  NA_real_
}

flatten_lineup_players <- function(team, is_home_team, on_bench) {
  players <- if (on_bench) team$subs %||% list() else team$starters %||% list()

  if (length(players) == 0) {
    return(tibble())
  }

  bind_rows(lapply(players, function(player) {
    tibble(
      fotmob_player_id = scalar_int(player$id),
      fotmob_player_name = scalar_chr(player$name),
      fotmob_team_id = scalar_int(team$id),
      fotmob_team_name = scalar_chr(team$name),
      is_home_team = is_home_team,
      on_bench = on_bench,
      rating = scalar_num(player$performance$rating)
    )
  }))
}

extract_match_ratings <- function(details, fixture) {
  general <- details$general
  lineup <- details$content$lineup
  player_stats <- details$content$playerStats %||% list()

  if (is.null(lineup) || length(player_stats) == 0) {
    return(empty_ratings_tbl())
  }

  lineup_players <- bind_rows(
    flatten_lineup_players(lineup$homeTeam, TRUE, FALSE),
    flatten_lineup_players(lineup$homeTeam, TRUE, TRUE),
    flatten_lineup_players(lineup$awayTeam, FALSE, FALSE),
    flatten_lineup_players(lineup$awayTeam, FALSE, TRUE)
  )

  if (nrow(lineup_players) == 0) {
    return(empty_ratings_tbl())
  }

  max_rating <- max(lineup_players$rating, na.rm = TRUE)
  if (!is.finite(max_rating)) {
    max_rating <- NA_real_
  }

  rows <- bind_rows(lapply(seq_len(nrow(lineup_players)), function(i) {
    player <- lineup_players[i, ]
    stats <- player_stats[[as.character(player$fotmob_player_id)]] %||% list()

    opponent <- if (player$is_home_team) {
      general$awayTeam
    } else {
      general$homeTeam
    }

    tibble(
      source_league_name = fixture$source_league_name,
      source_league_id = as.integer(fixture$source_league_id),
      season_name = fixture$season_name,
      ratings_source = "match_details",
      season_start = as.Date(fixture$season_start),
      season_end = as.Date(fixture$season_end),
      fotmob_player_id = as.integer(player$fotmob_player_id),
      fotmob_player_name = player$fotmob_player_name,
      fotmob_team_id = as.integer(player$fotmob_team_id),
      fotmob_team_name = player$fotmob_team_name,
      opponent_team_id = scalar_int(opponent$id),
      opponent_team_name = scalar_chr(opponent$name),
      match_id = as.integer(fixture$match_id),
      match_date = as.Date(fixture$match_date),
      match_page_url = fixture$match_page_url,
      league_id = scalar_int(general$parentLeagueId %||% general$leagueId),
      league_name = scalar_chr(general$leagueName),
      stage = scalar_chr(general$leagueRoundName),
      is_home_team = as.logical(player$is_home_team),
      minutes_played = as.integer(stat_value(stats, "minutes_played")),
      goals = as.integer(stat_value(stats, "goals")),
      assists = as.integer(stat_value(stats, "assists")),
      yellow_cards = as.integer(stat_value(stats, "yellow_cards")),
      red_cards = as.integer(stat_value(stats, "red_cards")),
      rating = as.numeric(player$rating),
      is_top_rating = !is.na(player$rating) & !is.na(max_rating) & player$rating == max_rating,
      player_of_the_match = FALSE,
      on_bench = as.logical(player$on_bench)
    )
  }))

  rows %>%
    filter(!is.na(fotmob_player_id), !is.na(match_id))
}

coerce_existing_ratings <- function(path) {
  if (!file.exists(path)) {
    return(empty_ratings_tbl())
  }

  read_csv(path, show_col_types = FALSE, col_types = cols(.default = col_character())) %>%
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

ensure_dir(fixtures_dir)
ensure_dir(ratings_dir)

league_config <- read_csv(league_config_path, show_col_types = FALSE) %>%
  filter(active, match_status == "matched") %>%
  mutate(league_id = as.integer(league_id))

if (!is.na(limit_leagues)) {
  league_config <- head(league_config, limit_leagues)
}

build_id <- get_build_id()
message("FotMob build id: ", build_id)
message("Season target: ", season_name)
message("Leagues queued: ", nrow(league_config))

x_mas <- Sys.getenv("FOTMOB_X_MAS", unset = "")
cookie <- Sys.getenv("FOTMOB_COOKIE", unset = "")
cookie_file <- Sys.getenv("FOTMOB_COOKIE_FILE", unset = "")

if (!nzchar(cookie) && nzchar(cookie_file) && file.exists(cookie_file)) {
  cookie <- str_squish(paste(readLines(cookie_file, warn = FALSE), collapse = " "))
}

has_auth <- nzchar(x_mas) || nzchar(cookie)

if (!has_auth) {
  message("Neither FOTMOB_X_MAS nor FOTMOB_COOKIE is set. The script will write fixture queues only.")
}

manifest <- bind_rows(lapply(seq_len(nrow(league_config)), function(i) {
  league_row <- league_config[i, ]
  league_slug <- safe_slug(league_row$league_name)
  fixture_path <- file.path(fixtures_dir, sprintf("%s_%s_fixtures.csv", league_row$league_id, league_slug))
  ratings_path <- file.path(
    ratings_dir,
    sprintf("%s_%s_%s_ratings.csv", league_row$league_id, league_slug, str_replace_all(season_name, "/", "-"))
  )

  fixtures <- fetch_fixtures(league_row, build_id, season_name)

  write_csv(fixtures, fixture_path, na = "")
  message("Saved fixtures for ", league_row$league_name, ": ", nrow(fixtures))

  fixtures_to_process <- fixtures
  if (!is.na(limit_matches)) {
    fixtures_to_process <- head(fixtures_to_process, limit_matches)
  }

  existing <- coerce_existing_ratings(ratings_path)
  processed_ids <- unique(existing$match_id)

  if (!has_auth || nrow(fixtures_to_process) == 0) {
    return(tibble(
      source_league_name = league_row$league_name,
      source_league_id = league_row$league_id,
      fixtures = nrow(fixtures),
      processed_matches = length(processed_ids),
      rating_rows = nrow(existing),
      ratings_path = ratings_path
    ))
  }

  remaining <- fixtures_to_process %>%
    filter(!(match_id %in% processed_ids))

  ratings_accum <- existing

  for (j in seq_len(nrow(remaining))) {
    fixture <- remaining[j, ]
    message(
      "Fetching match details ",
      league_row$league_name,
      " ",
      j,
      "/",
      nrow(remaining),
      ": ",
      fixture$match_id
    )

    details <- fetch_match_details(fixture$match_id, x_mas = x_mas, cookie = cookie)
    match_rows <- if (is.null(details)) empty_ratings_tbl() else extract_match_ratings(details, fixture)

    ratings_accum <- bind_rows(ratings_accum, match_rows) %>%
      distinct(fotmob_player_id, match_id, .keep_all = TRUE) %>%
      arrange(match_date, fotmob_team_name, fotmob_player_name)

    write_csv(ratings_accum, ratings_path, na = "")

    if (request_delay > 0 && j < nrow(remaining)) {
      Sys.sleep(request_delay)
    }
  }

  tibble(
    source_league_name = league_row$league_name,
    source_league_id = league_row$league_id,
    fixtures = nrow(fixtures),
    processed_matches = n_distinct(ratings_accum$match_id),
    rating_rows = nrow(ratings_accum),
    ratings_path = ratings_path
  )
}))

write_csv(manifest, manifest_out, na = "")
print(manifest)
message("Saved scrape manifest to: ", manifest_out)
