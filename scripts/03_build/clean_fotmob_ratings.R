library(dplyr)
library(lubridate)
library(readr)
library(stringr)
library(tibble)

ratings_checkpoint_dir <- "data/checkpoints/ratings"
historical_ratings_checkpoint_dir <- "data/historical/checkpoints/ratings"
historical_fixture_dir <- "data/historical/match_fixtures"
clean_row_out <- "data/fotmob_ratings_clean.csv"
monthly_all_out <- "data/fotmob_ratings_monthly_all_comps.csv"
monthly_league_out <- "data/fotmob_ratings_monthly_source_league.csv"

read_ratings_csv <- function(path) {
  as_tibble(utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    colClasses = "character",
    check.names = FALSE,
    fileEncoding = "UTF-8"
  ))
}

ensure_columns <- function(df, defaults) {
  for (col_name in names(defaults)) {
    if (!(col_name %in% names(df))) {
      df[[col_name]] <- defaults[[col_name]]
    }
  }

  df
}

safe_write_csv <- function(df, path) {
  tmp_path <- paste0(path, ".tmp")
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

parse_fotmob_date <- function(x) {
  suppressWarnings(as.Date(ymd(x)))
}

coerce_ratings <- function(df) {
  df %>%
    ensure_columns(list(
      season_name = NA_character_,
      ratings_source = "recent_matches"
    )) %>%
    mutate(
      source_league_name = as.character(source_league_name),
      source_league_id = as.integer(source_league_id),
      season_name = as.character(season_name),
      season_start = as.Date(season_start),
      season_end = as.Date(season_end),
      ratings_source = as.character(ratings_source),
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_player_name = decode_fotmob_text(as.character(fotmob_player_name)),
      fotmob_team_id = as.integer(fotmob_team_id),
      fotmob_team_name = decode_fotmob_text(as.character(fotmob_team_name)),
      opponent_team_id = as.integer(opponent_team_id),
      opponent_team_name = decode_fotmob_text(as.character(opponent_team_name)),
      match_id = as.integer(match_id),
      match_date = parse_fotmob_date(match_date),
      match_page_url = as.character(match_page_url),
      league_id = as.integer(league_id),
      league_name = decode_fotmob_text(as.character(league_name)),
      stage = decode_fotmob_text(as.character(stage)),
      is_home_team = as.logical(is_home_team),
      minutes_played = as.integer(minutes_played),
      goals = as.integer(goals),
      assists = as.integer(assists),
      yellow_cards = as.integer(yellow_cards),
      red_cards = as.integer(red_cards),
      rating = as.numeric(rating),
      # FotMob ratings live on a 0-10 scale; out-of-range values are
      # source-side glitches (e.g. extra-time accumulation) -> set NA
      rating = if_else(!is.na(rating) & (rating <= 0 | rating > 10), NA_real_, rating),
      is_top_rating = as.logical(is_top_rating),
      player_of_the_match = as.logical(player_of_the_match),
      on_bench = as.logical(on_bench)
    ) %>%
    mutate(
      across(
        c(
          source_league_name,
          season_name,
          ratings_source,
          fotmob_player_name,
          fotmob_team_name,
          opponent_team_name,
          match_page_url,
          league_name,
          stage
        ),
        as.character
      )
    )
}

list_rating_files <- function(path) {
  if (!dir.exists(path)) {
    return(character())
  }

  list.files(
    path,
    pattern = "_ratings\\.csv$",
    full.names = TRUE
  )
}

list_fixture_files <- function(path) {
  if (!dir.exists(path)) {
    return(character())
  }

  list.files(
    path,
    pattern = "_fixtures\\.csv$",
    full.names = TRUE,
    recursive = TRUE
  )
}

parse_fixture_results <- function(path) {
  read_ratings_csv(path) %>%
    ensure_columns(list(
      match_id = NA_character_,
      home_team_id = NA_character_,
      away_team_id = NA_character_,
      score = NA_character_
    )) %>%
    transmute(
      match_id = as.integer(match_id),
      home_team_id = as.integer(home_team_id),
      away_team_id = as.integer(away_team_id),
      score = as.character(score)
    ) %>%
    mutate(
      score_parts = str_match(score, "^\\s*([0-9]+)\\s*-\\s*([0-9]+)\\s*$"),
      home_score = as.integer(score_parts[, 2]),
      away_score = as.integer(score_parts[, 3])
    ) %>%
    select(-score_parts) %>%
    filter(!is.na(match_id), !is.na(home_score), !is.na(away_score))
}

load_fixture_results <- function() {
  fixture_files <- list_fixture_files(historical_fixture_dir)

  if (length(fixture_files) == 0) {
    return(tibble(
      match_id = integer(),
      home_team_id = integer(),
      away_team_id = integer(),
      home_score = integer(),
      away_score = integer()
    ))
  }

  bind_rows(lapply(fixture_files, parse_fixture_results)) %>%
    distinct(match_id, .keep_all = TRUE)
}

weighted_mean_safe <- function(x, w) {
  keep <- !is.na(x) & !is.na(w) & w > 0
  if (!any(keep)) {
    return(NA_real_)
  }
  stats::weighted.mean(x[keep], w[keep])
}

summarise_monthly <- function(df) {
  df %>%
    group_by(fotmob_player_id, Month) %>%
    summarise(
      fotmob_player_name = first(fotmob_player_name),
      source_league_name = first(source_league_name),
      source_league_id = first(source_league_id),
      matches = n_distinct(match_id),
      appearances = sum(coalesce(minutes_played, 0) > 0, na.rm = TRUE),
      starts_proxy = sum(!coalesce(on_bench, FALSE), na.rm = TRUE),
      minutes = sum(minutes_played, na.rm = TRUE),
      goals = sum(goals, na.rm = TRUE),
      assists = sum(assists, na.rm = TRUE),
      yellow_cards = sum(yellow_cards, na.rm = TRUE),
      red_cards = sum(red_cards, na.rm = TRUE),
      result_matches = sum(!is.na(team_win)),
      wins = sum(coalesce(team_win, FALSE), na.rm = TRUE),
      draws = sum(coalesce(team_draw, FALSE), na.rm = TRUE),
      losses = sum(coalesce(team_loss, FALSE), na.rm = TRUE),
      win_share = if_else(result_matches > 0, wins / result_matches, NA_real_),
      result_points_per_match = if_else(
        result_matches > 0,
        (wins * 3 + draws) / result_matches,
        NA_real_
      ),
      mean_rating = mean(rating, na.rm = TRUE),
      mean_rating = if_else(is.nan(mean_rating), NA_real_, mean_rating),
      minutes_weighted_rating = weighted_mean_safe(rating, minutes_played),
      top_ratings = sum(coalesce(is_top_rating, FALSE), na.rm = TRUE),
      player_of_match_awards = sum(coalesce(player_of_the_match, FALSE), na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(fotmob_player_id, Month)
}

rating_files <- c(
  list_rating_files(ratings_checkpoint_dir),
  list_rating_files(historical_ratings_checkpoint_dir)
)

default_skip_files <- c("264_belgian-challenger-pro-league_ratings.csv")
env_skip_files <- str_split(Sys.getenv("FOTMOB_SKIP_RATING_FILES", unset = ""), ",", simplify = TRUE)
env_skip_files <- str_squish(env_skip_files[nzchar(str_squish(env_skip_files))])
skip_files <- unique(c(default_skip_files, env_skip_files))

if (length(skip_files) > 0) {
  skipped <- rating_files[basename(rating_files) %in% skip_files]
  rating_files <- rating_files[!(basename(rating_files) %in% skip_files)]

  if (length(skipped) > 0) {
    message("Skipping ratings checkpoints: ", paste(basename(skipped), collapse = ", "))
  }
}

if (length(rating_files) == 0) {
  stop(
    "No ratings checkpoint files found in ",
    ratings_checkpoint_dir,
    " or ",
    historical_ratings_checkpoint_dir
  )
}

message("Reading ratings checkpoints: ", length(rating_files))

fixture_results <- load_fixture_results()
message("Loaded fixture results for matches: ", nrow(fixture_results))

ratings_raw <- bind_rows(lapply(seq_along(rating_files), function(i) {
  path <- rating_files[[i]]
  message("Reading checkpoint ", i, "/", length(rating_files), ": ", basename(path))

  read_ratings_csv(path) %>%
    coerce_ratings()
})) %>%
  filter(!is.na(match_id), !is.na(fotmob_player_id), !is.na(match_date)) %>%
  distinct(source_league_id, fotmob_player_id, match_id, .keep_all = TRUE) %>%
  mutate(
    match_page_full_url = if_else(
      str_detect(match_page_url, "^https?://"),
      match_page_url,
      paste0("https://www.fotmob.com", match_page_url)
    ),
    Month = floor_date(match_date, unit = "month"),
    in_season_window = match_date >= season_start & match_date <= season_end,
    is_source_league_match = league_id == source_league_id,
    has_minutes = coalesce(minutes_played, 0L) > 0L,
    has_valid_rating = !is.na(rating) & rating > 0
  ) %>%
  left_join(fixture_results, by = "match_id") %>%
  mutate(
    team_score = case_when(
      fotmob_team_id == home_team_id ~ home_score,
      fotmob_team_id == away_team_id ~ away_score,
      TRUE ~ NA_integer_
    ),
    opponent_score = case_when(
      fotmob_team_id == home_team_id ~ away_score,
      fotmob_team_id == away_team_id ~ home_score,
      TRUE ~ NA_integer_
    ),
    team_goal_diff = team_score - opponent_score,
    team_win = !is.na(team_goal_diff) & team_goal_diff > 0,
    team_draw = !is.na(team_goal_diff) & team_goal_diff == 0,
    team_loss = !is.na(team_goal_diff) & team_goal_diff < 0
  ) %>%
  arrange(source_league_name, fotmob_player_name, match_date, match_id)

safe_write_csv(ratings_raw, clean_row_out)
message("Saved clean row-level ratings to: ", clean_row_out)

monthly_all <- summarise_monthly(ratings_raw)
safe_write_csv(monthly_all, monthly_all_out)
message("Saved monthly all-competitions ratings to: ", monthly_all_out)

monthly_source_league <- ratings_raw %>%
  filter(is_source_league_match) %>%
  summarise_monthly()

safe_write_csv(monthly_source_league, monthly_league_out)
message("Saved monthly source-league ratings to: ", monthly_league_out)
