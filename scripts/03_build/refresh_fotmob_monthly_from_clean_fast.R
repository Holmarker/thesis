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
  # month's league label comes from actual source-league matches, not an
  # alphabetically-first roster tag (D7 in text/DECISIONS.md)
  setorder(dt, fotmob_player_id, Month, -is_source_league_match, match_date, na.last = TRUE)
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
      result_matches = sum(!is.na(team_win)),
      wins = sum(fcoalesce(team_win, FALSE)),
      draws = sum(fcoalesce(team_draw, FALSE)),
      losses = sum(fcoalesce(team_loss, FALSE)),
      win_share = {
        rm_ <- sum(!is.na(team_win))
        if (rm_ > 0) sum(fcoalesce(team_win, FALSE)) / rm_ else NA_real_
      },
      result_points_per_match = {
        rm_ <- sum(!is.na(team_win))
        if (rm_ > 0) {
          (sum(fcoalesce(team_win, FALSE)) * 3 + sum(fcoalesce(team_draw, FALSE))) / rm_
        } else {
          NA_real_
        }
      },
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
# a football match caps out at ~120 minutes; larger values are FotMob API glitches
dt[minutes_played > 120L, minutes_played := NA_integer_]
dt[, goals := as.integer(goals)]
dt[, assists := as.integer(assists)]
dt[, yellow_cards := as.integer(yellow_cards)]
dt[, red_cards := as.integer(red_cards)]
dt[, rating := as.numeric(rating)]
dt[, is_top_rating := as.logical(is_top_rating)]
dt[, player_of_the_match := as.logical(player_of_the_match)]
dt[, on_bench := as.logical(on_bench)]
dt[, is_source_league_match := as.logical(is_source_league_match)]
dt[, team_win := as.logical(team_win)]
dt[, team_draw := as.logical(team_draw)]
dt[, team_loss := as.logical(team_loss)]

# players scraped under two source leagues (mid-season transfers) carry the same
# match twice; keep one row per player-match, preferring the source-league copy,
# then rows with a rating, then the one with most minutes
dt[, dedup_rank := frank(
  -(fcoalesce(is_source_league_match, FALSE) * 4L +
      (!is.na(rating)) * 2L +
      fifelse(is.na(minutes_played), 0L, 1L)),
  ties.method = "first"
), by = .(fotmob_player_id, match_id)]
dt <- dt[is.na(match_id) | dedup_rank == 1L]
dt[, dedup_rank := NULL]

# D9/D9b: friendlies and national-team competitions excluded from monthly
# aggregates (id list + name-pattern fallback; never matches "Europa League")
intl_ids <- fread("RSpeciale/data/international_competition_ids.csv")$league_id
intl_pattern <- "friendl|world cup qual|nations league|africa cup|gold cup|copa america|asian cup|olympi|\\bu1[79]\\b|\\bu2[013]\\b|^euro( |$)"
dt <- dt[!(league_id %in% intl_ids) | is.na(league_id)]
dt <- dt[!grepl(intl_pattern, tolower(fcoalesce(league_name, "")))]
monthly_all <- summarise_monthly_dt(dt)
fwrite(monthly_all, monthly_all_out)
cat("Saved monthly all-competitions ratings to:", monthly_all_out, "\n")

monthly_source_league <- summarise_monthly_dt(dt[is_source_league_match == TRUE])
fwrite(monthly_source_league, monthly_league_out)
cat("Saved monthly source-league ratings to:", monthly_league_out, "\n")
