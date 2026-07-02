library(dplyr)
library(jsonlite)
library(readr)
library(stringr)
library(tibble)

crosswalk_path <- Sys.getenv(
  "FOTMOB_HISTORICAL_CROSSWALK",
  "RSpeciale/data/fotmob_transfermarkt_crosswalk_confirmed.csv"
)
players_path <- Sys.getenv(
  "FOTMOB_HISTORICAL_PLAYERS",
  "RSpeciale/data/fotmob_all_league_players.csv"
)
players_checkpoint_dir <- Sys.getenv(
  "FOTMOB_HISTORICAL_PLAYERS_CHECKPOINT_DIR",
  "RSpeciale/data/checkpoints/players"
)
season_targets_path <- Sys.getenv(
  "FOTMOB_HISTORICAL_TARGETS",
  "RSpeciale/fotmob_historical_season_targets.csv"
)

historical_dir <- Sys.getenv(
  "FOTMOB_HISTORICAL_DIR",
  "RSpeciale/data/historical"
)
historical_checkpoint_dir <- file.path(historical_dir, "checkpoints", "statseasons")
inventory_out <- file.path(historical_dir, "fotmob_historical_statseasons_inventory.csv")
player_core_out <- file.path(historical_dir, "fotmob_historical_player_core.csv")

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

scalar_chr <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(NA_character_)
  }

  if (is.list(x)) {
    x <- unlist(x, recursive = TRUE, use.names = FALSE)
  }

  if (length(x) == 0) {
    return(NA_character_)
  }

  as.character(x[[1]])
}

scalar_int <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(NA_integer_)
  }

  if (is.list(x)) {
    x <- unlist(x, recursive = TRUE, use.names = FALSE)
  }

  if (length(x) == 0) {
    return(NA_integer_)
  }

  suppressWarnings(as.integer(x[[1]]))
}

scalar_lgl <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(NA)
  }

  if (is.list(x)) {
    x <- unlist(x, recursive = TRUE, use.names = FALSE)
  }

  if (length(x) == 0) {
    return(NA)
  }

  as.logical(x[[1]])
}

normalize_name <- function(x) {
  x %>%
    iconv(from = "", to = "ASCII//TRANSLIT") %>%
    tolower() %>%
    str_replace_all("[^a-z0-9 ]", " ") %>%
    str_squish()
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

empty_inventory_tbl <- function() {
  tibble(
    fotmob_player_id = integer(),
    fotmob_player_name = character(),
    fotmob_player_slug = character(),
    tm_player_id = integer(),
    source_league_name = character(),
    source_league_id = integer(),
    source_team_name = character(),
    season_name = character(),
    tournament_name = character(),
    tournament_id = integer(),
    entry_id = character(),
    has_deep_stats = logical(),
    birth_date = character(),
    contract_end = character(),
    primary_team_name = character(),
    primary_team_id = integer(),
    main_league_name = character(),
    main_league_id = integer()
  )
}

empty_player_core_tbl <- function() {
  tibble(
    fotmob_player_id = integer(),
    fotmob_player_name = character(),
    fotmob_player_slug = character(),
    tm_player_id = integer(),
    source_league_name = character(),
    source_league_id = integer(),
    source_team_name = character(),
    birth_date = character(),
    contract_end = character(),
    primary_team_name = character(),
    primary_team_id = integer(),
    main_league_name = character(),
    main_league_id = integer(),
    available_stat_seasons = character(),
    recent_matches_n = integer()
  )
}

extract_player_statseasons <- function(player_row, target_seasons) {
  url <- sprintf(
    "https://www.fotmob.com/players/%s/%s",
    player_row$fotmob_player_id,
    player_row$fotmob_player_slug
  )

  payload <- tryCatch(get_fotmob_page_json(url), error = function(e) NULL)

  if (is.null(payload)) {
    return(list(
      inventory = empty_inventory_tbl(),
      player_core = empty_player_core_tbl()
    ))
  }

  player_key <- sprintf("player:%s", player_row$fotmob_player_id)
  player_payload <- payload$props$pageProps$fallback[[player_key]]

  if (is.null(player_payload)) {
    return(list(
      inventory = empty_inventory_tbl(),
      player_core = empty_player_core_tbl()
    ))
  }

  available_seasons <- player_payload$statSeasons %||% list()

  player_core <- tibble(
    fotmob_player_id = as.integer(player_row$fotmob_player_id),
    fotmob_player_name = scalar_chr(player_payload$name %||% player_row$fotmob_player_name),
    fotmob_player_slug = player_row$fotmob_player_slug,
    tm_player_id = as.integer(player_row$tm_player_id),
    source_league_name = player_row$source_league_name,
    source_league_id = as.integer(player_row$source_league_id),
    source_team_name = player_row$fotmob_team_name,
    birth_date = scalar_chr(player_payload$birthDate),
    contract_end = scalar_chr(player_payload$contractEnd),
    primary_team_name = scalar_chr(player_payload$primaryTeam$name),
    primary_team_id = scalar_int(player_payload$primaryTeam$id),
    main_league_name = scalar_chr(player_payload$mainLeague$name),
    main_league_id = scalar_int(player_payload$mainLeague$id),
    available_stat_seasons = paste(
      vapply(available_seasons, function(s) s$seasonName %||% "", character(1)),
      collapse = "|"
    ),
    recent_matches_n = length(player_payload$recentMatches %||% list())
  )

  inventory <- bind_rows(lapply(available_seasons, function(season_obj) {
    season_name <- season_obj$seasonName %||% NA_character_

    if (is.na(season_name) || !(season_name %in% target_seasons)) {
      return(empty_inventory_tbl())
    }

    tournaments <- season_obj$tournaments %||% list()

    if (length(tournaments) == 0) {
      return(empty_inventory_tbl())
    }

    bind_rows(lapply(tournaments, function(tournament_obj) {
      tibble(
        fotmob_player_id = as.integer(player_row$fotmob_player_id),
        fotmob_player_name = scalar_chr(player_payload$name %||% player_row$fotmob_player_name),
        fotmob_player_slug = player_row$fotmob_player_slug,
        tm_player_id = as.integer(player_row$tm_player_id),
        source_league_name = player_row$source_league_name,
        source_league_id = as.integer(player_row$source_league_id),
        source_team_name = player_row$fotmob_team_name,
        season_name = season_name,
        tournament_name = scalar_chr(tournament_obj$name),
        tournament_id = scalar_int(tournament_obj$tournamentId),
        entry_id = scalar_chr(tournament_obj$entryId),
        has_deep_stats = scalar_lgl(tournament_obj$hasDeepStats),
        birth_date = scalar_chr(player_payload$birthDate),
        contract_end = scalar_chr(player_payload$contractEnd),
        primary_team_name = scalar_chr(player_payload$primaryTeam$name),
        primary_team_id = scalar_int(player_payload$primaryTeam$id),
        main_league_name = scalar_chr(player_payload$mainLeague$name),
        main_league_id = scalar_int(player_payload$mainLeague$id)
      )
    }))
  }))

  list(
    inventory = inventory,
    player_core = player_core
  )
}

season_targets <- read_csv(season_targets_path, show_col_types = FALSE) %>%
  filter(active)

target_seasons <- season_targets$season_name

crosswalk <- read_csv(crosswalk_path, show_col_types = FALSE) %>%
  filter(merge_safe) %>%
  transmute(
    tm_player_id = as.integer(tm_player_id),
    fotmob_player_id = as.integer(fotmob_player_id)
  )

load_fotmob_players <- function(players_path, players_checkpoint_dir) {
  checkpoint_files <- list.files(
    players_checkpoint_dir,
    pattern = "_players\\.csv$",
    full.names = TRUE
  )

  if (length(checkpoint_files) > 0) {
    return(
      bind_rows(lapply(checkpoint_files, function(path) {
        read_csv(path, show_col_types = FALSE)
      })) %>%
        transmute(
          source_league_name,
          source_league_id = as.integer(source_league_id),
          fotmob_team_name,
          fotmob_player_id = as.integer(fotmob_player_id),
          fotmob_player_name,
          fotmob_player_slug = as.character(fotmob_player_slug)
        ) %>%
        distinct(fotmob_player_id, .keep_all = TRUE)
    )
  }

  read_csv(players_path, show_col_types = FALSE) %>%
    transmute(
      source_league_name,
      source_league_id = as.integer(source_league_id),
      fotmob_team_name,
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_player_name,
      fotmob_player_slug = as.character(fotmob_player_slug)
    ) %>%
    distinct(fotmob_player_id, .keep_all = TRUE)
}

fotmob_players <- load_fotmob_players(players_path, players_checkpoint_dir)

historical_players <- crosswalk %>%
  inner_join(fotmob_players, by = "fotmob_player_id") %>%
  arrange(source_league_name, fotmob_team_name, fotmob_player_name)

ensure_dir(historical_dir)
ensure_dir(historical_checkpoint_dir)

existing_files <- list.files(
  historical_checkpoint_dir,
  pattern = "_statseasons\\.csv$",
  full.names = TRUE
)

processed_ids <- if (length(existing_files) == 0) {
  integer()
} else {
  bind_rows(lapply(existing_files, read_csv, show_col_types = FALSE)) %>%
    pull(fotmob_player_id) %>%
    unique()
}

remaining_players <- historical_players %>%
  filter(!(fotmob_player_id %in% processed_ids))

message("Historical target seasons: ", paste(target_seasons, collapse = ", "))
message("Safe matched players available: ", nrow(historical_players))
message("Already checkpointed: ", length(processed_ids))
message("Remaining players: ", nrow(remaining_players))

for (i in seq_len(nrow(remaining_players))) {
  player_row <- remaining_players[i, ]

  message(
    "Preparing historical statSeasons for ",
    player_row$fotmob_player_name,
    " [", player_row$source_league_name, "] (",
    i, "/", nrow(remaining_players), ")"
  )

  extracted <- extract_player_statseasons(player_row, target_seasons)
  checkpoint_stub <- sprintf(
    "%s_%s",
    player_row$fotmob_player_id,
    safe_slug(player_row$fotmob_player_name)
  )

  write_csv(
    extracted$inventory,
    file.path(historical_checkpoint_dir, paste0(checkpoint_stub, "_statseasons.csv")),
    na = ""
  )

  write_csv(
    extracted$player_core,
    file.path(historical_checkpoint_dir, paste0(checkpoint_stub, "_player_core.csv")),
    na = ""
  )

  if (i %% 25 == 0 || i == nrow(remaining_players)) {
    message("Saved historical-prep checkpoint after ", i, " players")
  }
}

inventory_files <- list.files(
  historical_checkpoint_dir,
  pattern = "_statseasons\\.csv$",
  full.names = TRUE
)

player_core_files <- list.files(
  historical_checkpoint_dir,
  pattern = "_player_core\\.csv$",
  full.names = TRUE
)

historical_inventory <- bind_rows(lapply(inventory_files, read_csv, show_col_types = FALSE)) %>%
  distinct(fotmob_player_id, season_name, tournament_id, entry_id, .keep_all = TRUE) %>%
  arrange(source_league_name, season_name, fotmob_player_name, tournament_name)

historical_player_core <- bind_rows(lapply(player_core_files, read_csv, show_col_types = FALSE)) %>%
  distinct(fotmob_player_id, .keep_all = TRUE) %>%
  arrange(source_league_name, fotmob_player_name)

write_csv(historical_inventory, inventory_out, na = "")
message("Saved historical statSeasons inventory to: ", inventory_out)

write_csv(historical_player_core, player_core_out, na = "")
message("Saved historical player core file to: ", player_core_out)

message(
  "Note: this script inventories historical season/tournament pointers from statSeasons. ",
  "It does not yet fetch older match-by-match ratings."
)
