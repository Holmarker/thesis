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

  # S7: off-season months carry no allocation information (playing margin only)
  if (margin == "playing") {
    df <- dplyr::filter(df, !(format(Month, "%m") %in% c("06", "07")))
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
