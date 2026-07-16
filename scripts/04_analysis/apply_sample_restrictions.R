# Shared estimation-sample restrictions (S1-S8 in text/DECISIONS.md).
# Decided ex ante 2026-07-15; every analysis script sources this file so the
# rules cannot drift between scripts.
#
# Usage:
#   source(file.path("scripts", "04_analysis", "apply_sample_restrictions.R"))
#   df <- apply_sample_restrictions(df, margin = "rating")   # or "playing"
#
# Expects columns: Month (Date), player_id, fotmob_source_league.

EXCL8_LEAGUES <- c(
  "Ukrainian Premier Liga",
  "Serbian Super Liga",
  "Czech First League",
  "Romanian Liga 1",
  "Bulgarian Parva Liga",
  "Hungarian Nemzeti Bajnoksag",
  "Turkish 1.Lig",
  "Belgian Challenger Pro League"
)

apply_sample_restrictions <- function(df, margin = c("rating", "playing")) {
  margin <- match.arg(margin)

  # S1: drop the 2021/22 stub (months before July 2022)
  df <- dplyr::filter(df, Month >= as.Date("2022-07-01"))

  # S2: constant league composition for rating outcomes only
  if (margin == "rating") {
    df <- dplyr::filter(df, !fotmob_source_league %in% EXCL8_LEAGUES)
  }

  # S7 (amended 2026-07-16): off-season months carry no allocation
  # information (playing margin only). A league-month is off-season when
  # fewer than 10% of the league's contracted players record any minutes --
  # league-specific, so calendar-year seasons (Norway, Brazil, ...) and long
  # winter breaks (Denmark) are handled symmetrically.
  if (margin == "playing") {
    # a league-month is off-season when the league played ZERO league fixtures
    # that month (friendlies do not count); calendar derived from the clean
    # match data. Only applied within league-seasons that have fixture
    # coverage, so uncovered league-seasons (e.g. the excl-8 leagues before
    # 2024/25) are never condemned wholesale.
    cal <- readr::read_csv(
      file.path("data", "league_month_fixture_calendar.csv"),
      show_col_types = FALSE
    ) %>%
      dplyr::mutate(
        month = as.Date(month),
        season_start = ifelse(as.integer(format(month, "%m")) >= 7,
                              as.integer(format(month, "%Y")),
                              as.integer(format(month, "%Y")) - 1L)
      )
    covered_seasons <- cal %>%
      dplyr::distinct(source_league_name, season_start)
    active_months <- cal %>% dplyr::distinct(source_league_name, month)

    df <- df %>%
      # off-season months carry no FotMob rows, so fotmob_source_league is NA
      # there; fill each player's league through his own gap months
      dplyr::arrange(player_id, Month) %>%
      dplyr::group_by(player_id) %>%
      dplyr::mutate(.lg = fotmob_source_league) %>%
      tidyr::fill(.lg, .direction = "downup") %>%
      dplyr::ungroup() %>%
      dplyr::mutate(
        .season_start = ifelse(as.integer(format(Month, "%m")) >= 7,
                               as.integer(format(Month, "%Y")),
                               as.integer(format(Month, "%Y")) - 1L)
      ) %>%
      dplyr::left_join(
        covered_seasons %>% dplyr::mutate(.season_covered = TRUE),
        by = c(".lg" = "source_league_name", ".season_start" = "season_start")
      ) %>%
      dplyr::left_join(
        active_months %>% dplyr::mutate(.league_played = TRUE),
        by = c(".lg" = "source_league_name", "Month" = "month")
      ) %>%
      dplyr::filter(
        is.na(.lg) |
          !dplyr::coalesce(.season_covered, FALSE) |
          dplyr::coalesce(.league_played, FALSE)
      ) %>%
      dplyr::select(-.lg, -.season_start, -.season_covered, -.league_played)
  }

  # S3: minimum panel presence of 6 observed months per player
  df <- df %>%
    dplyr::group_by(player_id) %>%
    dplyr::filter(dplyr::n() >= 6) %>%
    dplyr::ungroup()

  df
}

# S5 (months-to-expiry support <= 48) is enforced where duration enters:
# expiry bins already top-code at 48+; splines/event studies must restrict
# support to <= 48 months at the point of use.
# S4 (no age limits) and S6 (goalkeepers included, split reported) require no
# filtering here by design.
