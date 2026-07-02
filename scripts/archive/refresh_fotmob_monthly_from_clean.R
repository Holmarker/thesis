library(dplyr)
library(readr)

clean_row_path <- "RSpeciale/data/fotmob_ratings_clean.csv"
monthly_all_out <- "RSpeciale/data/fotmob_ratings_monthly_all_comps.csv"
monthly_league_out <- "RSpeciale/data/fotmob_ratings_monthly_source_league.csv"

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
      mean_rating = mean(rating, na.rm = TRUE),
      mean_rating = if_else(is.nan(mean_rating), NA_real_, mean_rating),
      minutes_weighted_rating = weighted_mean_safe(rating, minutes_played),
      top_ratings = sum(coalesce(is_top_rating, FALSE), na.rm = TRUE),
      player_of_match_awards = sum(coalesce(player_of_the_match, FALSE), na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(fotmob_player_id, Month)
}

ratings_raw <- read_csv(clean_row_path, show_col_types = FALSE) %>%
  mutate(
    Month = as.Date(Month),
    fotmob_player_id = as.integer(fotmob_player_id),
    source_league_id = as.integer(source_league_id),
    match_id = as.integer(match_id),
    minutes_played = as.integer(minutes_played),
    goals = as.integer(goals),
    assists = as.integer(assists),
    yellow_cards = as.integer(yellow_cards),
    red_cards = as.integer(red_cards),
    rating = as.numeric(rating),
    is_top_rating = as.logical(is_top_rating),
    player_of_the_match = as.logical(player_of_the_match),
    on_bench = as.logical(on_bench),
    is_source_league_match = as.logical(is_source_league_match)
  )

monthly_all <- summarise_monthly(ratings_raw)
write_csv(monthly_all, monthly_all_out, na = "")
message("Saved monthly all-competitions ratings to: ", monthly_all_out)

monthly_source_league <- ratings_raw %>%
  filter(is_source_league_match) %>%
  summarise_monthly()

write_csv(monthly_source_league, monthly_league_out, na = "")
message("Saved monthly source-league ratings to: ", monthly_league_out)
