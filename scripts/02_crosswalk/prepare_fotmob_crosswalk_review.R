library(dplyr)
library(lubridate)
library(openxlsx)
library(readr)
library(stringr)
library(tibble)

bios_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller data.xlsx"
fotmob_players_path <- "RSpeciale/data/fotmob_all_league_players.csv"
candidate_out <- "RSpeciale/data/fotmob_all_transfermarkt_crosswalk_candidates.csv"
review_out <- "RSpeciale/data/fotmob_transfermarkt_crosswalk_review.csv"
autokeep_out <- "RSpeciale/data/fotmob_transfermarkt_crosswalk_autokeep.csv"
manual_review_out <- "RSpeciale/data/fotmob_transfermarkt_crosswalk_manual_review.csv"

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
    str_replace_all("\\bfootball club\\b|\\bfc\\b|\\bcf\\b|\\bafc\\b|\\bsc\\b|\\bac\\b", " ") %>%
    str_replace_all("\\butd\\b", "united") %>%
    str_squish()
}

decode_fotmob_text <- function(x) {
  ifelse(
    is.na(x),
    NA_character_,
    utils::URLdecode(gsub("<([0-9A-Fa-f]{2})>", "%\\1", x))
  )
}

load_tm_players <- function(path) {
  read.xlsx(path) %>%
    transmute(
      tm_player_id = as.integer(player_id),
      player_name_tm = PlayerName,
      player_name_tm_clean = normalize_name(PlayerName),
      current_club_tm = CurrentClub,
      current_club_tm_clean = normalize_team(CurrentClub),
      date_of_birth = suppressWarnings(dmy(DateOfBirth)),
      nationality = nationality_new,
      player_url
    ) %>%
    filter(!is.na(tm_player_id), !is.na(player_name_tm_clean), player_name_tm_clean != "") %>%
    distinct()
}

load_fotmob_players <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    transmute(
      source_league_name,
      source_league_id = as.integer(source_league_id),
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_player_name = decode_fotmob_text(as.character(fotmob_player_name)),
      fotmob_player_name_clean = normalize_name(fotmob_player_name),
      fotmob_team_id = as.integer(fotmob_team_id),
      fotmob_team_name = decode_fotmob_text(as.character(fotmob_team_name)),
      fotmob_team_name_clean = normalize_team(fotmob_team_name),
      age = as.integer(age),
      country_name = as.character(country_name),
      position_group = as.character(position_group),
      squad_role = as.character(squad_role)
    ) %>%
    filter(!is.na(fotmob_player_id), !is.na(fotmob_player_name_clean), fotmob_player_name_clean != "") %>%
    distinct()
}

team_match_score <- function(tm_team, fotmob_team) {
  case_when(
    is.na(tm_team) | is.na(fotmob_team) ~ 0L,
    tm_team == "" | fotmob_team == "" ~ 0L,
    tm_team == fotmob_team ~ 40L,
    str_detect(tm_team, fixed(fotmob_team)) ~ 25L,
    str_detect(fotmob_team, fixed(tm_team)) ~ 25L,
    TRUE ~ 0L
  )
}

tm_players <- load_tm_players(bios_path)
fotmob_players <- load_fotmob_players(fotmob_players_path)

candidates <- tm_players %>%
  inner_join(
    fotmob_players,
    by = c("player_name_tm_clean" = "fotmob_player_name_clean"),
    relationship = "many-to-many"
  ) %>%
  mutate(
    name_match_score = 100L,
    team_match_score = team_match_score(current_club_tm_clean, fotmob_team_name_clean),
    same_nationality_hint = !is.na(nationality) &
      !is.na(country_name) &
      normalize_name(nationality) == normalize_name(country_name),
    same_position_hint = !is.na(position_group),
    candidate_score = name_match_score + team_match_score + if_else(same_nationality_hint, 5L, 0L),
    match_method = case_when(
      team_match_score >= 40L ~ "exact_name_plus_team",
      team_match_score >= 25L ~ "exact_name_plus_partial_team",
      TRUE ~ "exact_name_only"
    )
  ) %>%
  arrange(desc(candidate_score), player_name_tm, fotmob_team_name, source_league_name)

candidate_summary <- candidates %>%
  count(tm_player_id, name = "candidate_count_tm")

fotmob_summary <- candidates %>%
  count(fotmob_player_id, name = "candidate_count_fotmob")

review_file <- candidates %>%
  left_join(candidate_summary, by = "tm_player_id") %>%
  left_join(fotmob_summary, by = "fotmob_player_id") %>%
  arrange(tm_player_id, desc(candidate_score), fotmob_player_id) %>%
  group_by(tm_player_id) %>%
  mutate(
    candidate_rank_tm = row_number(),
    best_score_tm = max(candidate_score, na.rm = TRUE),
    tied_best_count_tm = sum(candidate_score == best_score_tm, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  arrange(fotmob_player_id, desc(candidate_score), tm_player_id) %>%
  group_by(fotmob_player_id) %>%
  mutate(
    candidate_rank_fotmob = row_number(),
    best_score_fotmob = max(candidate_score, na.rm = TRUE),
    tied_best_count_fotmob = sum(candidate_score == best_score_fotmob, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  mutate(
    auto_keep = candidate_rank_tm == 1L &
      candidate_rank_fotmob == 1L &
      tied_best_count_tm == 1L &
      tied_best_count_fotmob == 1L &
      candidate_score >= 140L,
    review_flag = case_when(
      auto_keep ~ "auto_keep_candidate",
      candidate_rank_tm > 1L ~ "non_top_tm_candidate",
      tied_best_count_tm > 1L | tied_best_count_fotmob > 1L ~ "ambiguous_top_match",
      candidate_count_tm > 3L | candidate_count_fotmob > 3L ~ "many_candidates",
      match_method == "exact_name_only" ~ "needs_manual_team_check",
      TRUE ~ "review"
    )
  ) %>%
  arrange(player_name_tm, desc(candidate_score), fotmob_team_name, source_league_name)

write_csv(candidates, candidate_out, na = "")
message("Saved crosswalk candidates to: ", candidate_out)

write_csv(review_file, review_out, na = "")
message("Saved crosswalk review file to: ", review_out)

autokeep_matches <- review_file %>%
  filter(auto_keep) %>%
  distinct(tm_player_id, .keep_all = TRUE) %>%
  arrange(player_name_tm)

manual_review_matches <- review_file %>%
  filter(candidate_rank_tm == 1L, !auto_keep) %>%
  distinct(tm_player_id, .keep_all = TRUE) %>%
  arrange(review_flag, desc(candidate_score), player_name_tm)

write_csv(autokeep_matches, autokeep_out, na = "")
message("Saved crosswalk auto-keep matches to: ", autokeep_out)

write_csv(manual_review_matches, manual_review_out, na = "")
message("Saved crosswalk manual-review queue to: ", manual_review_out)
