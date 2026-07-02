library(dplyr)
library(jsonlite)
library(readr)
library(stringr)
library(tibble)

league_config_path <- "RSpeciale/league_config_resolved.csv"
teams_checkpoint_dir <- "RSpeciale/data/checkpoints/teams"

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

normalize_team <- function(x) {
  x %>%
    normalize_name() %>%
    str_replace_all("\\bfc\\b|\\bcf\\b|\\bafc\\b", "") %>%
    str_squish()
}

safe_slug <- function(x) {
  x %>%
    normalize_name() %>%
    str_replace_all(" ", "-")
}

extract_table_teams <- function(table_obj) {
  teams <- table_obj$all %||% list()

  if (length(teams) == 0) {
    return(tibble())
  }

  tibble(
    fotmob_team_id = purrr::map_int(teams, \(x) x$id),
    fotmob_team_name = purrr::map_chr(teams, \(x) x$name),
    fotmob_team_short_name = purrr::map_chr(teams, \(x) x$shortName),
    fotmob_team_page_url = purrr::map_chr(teams, \(x) x$pageUrl)
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
  payload <- fromJSON(
    sprintf("https://www.fotmob.com/api/data/tltable?leagueId=%s", league_row$league_id),
    simplifyVector = FALSE
  )[[1]]

  teams <- extract_league_teams_from_payload(payload)

  teams %>%
    mutate(
      source_league_name = league_row$league_name,
      source_league_id = as.integer(league_row$league_id),
      source_ccode = league_row$ccode,
      season_start = as.Date(league_row$season_start),
      season_end = as.Date(league_row$season_end),
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

league_config <- read_csv(league_config_path, show_col_types = FALSE) %>%
  filter(active, match_status == "matched") %>%
  mutate(
    league_id = as.integer(league_id),
    season_start = as.Date(season_start),
    season_end = as.Date(season_end)
  )

checkpoint_files <- list.files(
  teams_checkpoint_dir,
  pattern = "_teams\\.csv$",
  full.names = TRUE
)

empty_files <- checkpoint_files[sapply(checkpoint_files, function(path) {
  length(readLines(path, warn = FALSE)) <= 1
})]

if (length(empty_files) == 0) {
  message("No empty team checkpoints found.")
  quit(save = "no")
}

message("Empty team checkpoints found: ", length(empty_files))

for (path in empty_files) {
  league_id <- as.integer(str_extract(basename(path), "^[0-9]+"))
  league_row <- league_config %>% filter(league_id == !!league_id)

  if (nrow(league_row) == 0) {
    message("Skipping ", basename(path), " because league_id was not found in config")
    next
  }

  message("Refetching teams for ", league_row$league_name[[1]], " (", league_id, ")")
  teams <- get_league_teams(league_row[1, ])
  write_csv(teams, path, na = "")
  message("Saved ", nrow(teams), " teams to ", path)
}
