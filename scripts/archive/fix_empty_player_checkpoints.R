library(dplyr)
library(jsonlite)
library(purrr)
library(readr)
library(stringr)
library(tibble)

league_config_path <- "RSpeciale/league_config_resolved.csv"
teams_checkpoint_dir <- "RSpeciale/data/checkpoints/teams"
players_checkpoint_dir <- "RSpeciale/data/checkpoints/players"

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

get_fotmob_page_json <- function(url) {
  html <- paste(readLines(url, warn = FALSE), collapse = "\n")
  json_txt <- sub('.*<script id="__NEXT_DATA__" type="application/json">', "", html)
  json_txt <- sub("</script>.*", "", json_txt)
  fromJSON(json_txt, simplifyVector = FALSE)
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

league_config <- read_csv(league_config_path, show_col_types = FALSE) %>%
  filter(active, match_status == "matched") %>%
  mutate(
    league_id = as.integer(league_id),
    season_start = as.Date(season_start),
    season_end = as.Date(season_end)
  )

player_files <- list.files(
  players_checkpoint_dir,
  pattern = "_players\\.csv$",
  full.names = TRUE
)

empty_files <- player_files[sapply(player_files, function(path) {
  length(readLines(path, warn = FALSE)) <= 1
})]

if (length(empty_files) == 0) {
  message("No empty player checkpoints found.")
  quit(save = "no")
}

message("Empty player checkpoints found: ", length(empty_files))

for (path in empty_files) {
  league_id <- as.integer(str_extract(basename(path), "^[0-9]+"))
  league_row <- league_config %>% filter(league_id == !!league_id)

  if (nrow(league_row) == 0) {
    message("Skipping ", basename(path), " because league_id was not found in config")
    next
  }

  teams_path <- file.path(
    teams_checkpoint_dir,
    sprintf("%s_%s_teams.csv", league_id, normalize_name(league_row$league_name[[1]]) %>% str_replace_all(" ", "-"))
  )

  teams <- read_csv(teams_path, show_col_types = FALSE)

  if (nrow(teams) == 0) {
    message("Skipping ", league_row$league_name[[1]], " because teams checkpoint is still empty")
    next
  }

  message("Refetching players for ", league_row$league_name[[1]], " (", league_id, ")")

  players <- bind_rows(
    empty_players_tbl(),
    lapply(seq_len(nrow(teams)), function(i) {
      team_row <- teams[i, ]
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

  write_csv(players, path, na = "")
  message("Saved ", nrow(players), " players to ", path)
}
