library(data.table)

clean_row_path <- "RSpeciale/data/fotmob_ratings_clean.csv"
monthly_all_out <- "RSpeciale/data/fotmob_ratings_monthly_all_comps.csv"
monthly_league_out <- "RSpeciale/data/fotmob_ratings_monthly_source_league.csv"

weighted_mean_safe <- function(x, w) {
  keep <- !is.na(x) & !is.na(w) & w > 0
  if (!any(keep)) {
    return(NA_real_)
  }
  weighted.mean(x[keep], w[keep])
}

summarise_monthly_dt <- function(dt) {
  dt[
    ,
    .(
      fotmob_player_name = first(fotmob_player_name),
      source_league_name = first(source_league_name),
      source_league_id = first(source_league_id),
      matches = uniqueN(match_id),
      appearances = sum(fifelse(is.na(minutes_played), FALSE, minutes_played > 0L)),
      starts_proxy = sum(!fcoalesce(on_bench, FALSE)),
      minutes = sum(minutes_played, na.rm = TRUE),
      goals = sum(goals, na.rm = TRUE),
      assists = sum(assists, na.rm = TRUE),
      yellow_cards = sum(yellow_cards, na.rm = TRUE),
      red_cards = sum(red_cards, na.rm = TRUE),
      mean_rating = {
        v <- mean(rating, na.rm = TRUE)
        if (is.nan(v)) NA_real_ else v
      },
      minutes_weighted_rating = weighted_mean_safe(rating, minutes_played),
      top_ratings = sum(fcoalesce(is_top_rating, FALSE)),
      player_of_match_awards = sum(fcoalesce(player_of_the_match, FALSE))
    ),
    by = .(fotmob_player_id, Month)
  ][order(fotmob_player_id, Month)]
}

dt <- fread(
  clean_row_path,
  sep = ",",
  na.strings = c("", "NA"),
  showProgress = TRUE
)

dt[, Month := as.IDate(Month)]
dt[, fotmob_player_id := as.integer(fotmob_player_id)]
dt[, source_league_id := as.integer(source_league_id)]
dt[, match_id := as.integer(match_id)]
dt[, minutes_played := as.integer(minutes_played)]
dt[, goals := as.integer(goals)]
dt[, assists := as.integer(assists)]
dt[, yellow_cards := as.integer(yellow_cards)]
dt[, red_cards := as.integer(red_cards)]
dt[, rating := as.numeric(rating)]
dt[, is_top_rating := as.logical(is_top_rating)]
dt[, player_of_the_match := as.logical(player_of_the_match)]
dt[, on_bench := as.logical(on_bench)]
dt[, is_source_league_match := as.logical(is_source_league_match)]

monthly_all <- summarise_monthly_dt(dt)
fwrite(monthly_all, monthly_all_out)
cat("Saved monthly all-competitions ratings to:", monthly_all_out, "\n")

monthly_source_league <- summarise_monthly_dt(dt[is_source_league_match == TRUE])
fwrite(monthly_source_league, monthly_league_out)
cat("Saved monthly source-league ratings to:", monthly_league_out, "\n")
