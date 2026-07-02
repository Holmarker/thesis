library(data.table)
library(dplyr)
library(readr)
library(stringr)

project_root <- if (dir.exists("data")) "." else "RSpeciale"

path_in <- function(...) {
  file.path(project_root, ...)
}

make_expiry_bin <- function(days_to_expiry) {
  cut(
    days_to_expiry,
    breaks = c(0, 90, 180, 365, 730, 1500, Inf),
    labels = c("0-3m", "3-6m", "6-12m", "1-2y", "2-4y", "4y+")
  )
}

map_country_region <- function(nationality) {
  case_when(
    nationality %in% c("Denmark", "Sweden", "Norway", "Finland", "Iceland", "Faroe Islands") ~ "Northern Europe",
    nationality %in% c(
      "England", "Ireland", "Scotland", "Wales", "Germany", "Netherlands",
      "Belgium", "France", "Austria", "Switzerland", "Luxembourg"
    ) ~ "Western Europe",
    nationality %in% c("Spain", "Portugal", "Italy", "Greece", "Cyprus", "Malta") ~ "Southern Europe",
    nationality %in% c(
      "Poland", "Czech Republic", "Slovakia", "Hungary", "Romania", "Bulgaria",
      "Ukraine", "Russia", "Belarus", "Serbia", "Croatia", "Bosnia-Herzegovina",
      "Slovenia", "Montenegro", "North Macedonia", "Albania", "Kosovo",
      "Moldova", "Georgia", "Armenia", "Azerbaijan", "Estonia", "Latvia", "Lithuania"
    ) ~ "Eastern Europe",
    nationality %in% c("United States", "Canada", "Mexico") ~ "North America",
    nationality %in% c(
      "Jamaica", "Haiti", "Dominican Republic", "Curacao", "Guadeloupe",
      "Martinique", "Bermuda", "St. Kitts & Nevis", "Grenada",
      "Antigua and Barbuda", "Guyana", "Suriname"
    ) ~ "Caribbean",
    nationality %in% c(
      "Brazil", "Argentina", "Chile", "Uruguay", "Colombia", "Peru",
      "Ecuador", "Paraguay", "Bolivia", "Venezuela"
    ) ~ "South America",
    nationality %in% c(
      "Saudi Arabia", "Iran", "Iraq", "Israel", "Jordan", "Syria",
      "Palestine", "Palästina", "Bahrain"
    ) ~ "Middle East",
    nationality %in% c(
      "Japan", "Korea, South", "China", "Vietnam", "Indonesia",
      "Bangladesh", "Uzbekistan", "Tajikistan", "Philippines"
    ) ~ "Asia",
    nationality %in% c(
      "Nigeria", "Senegal", "Ghana", "Cameroon", "DR Congo", "Congo",
      "Morocco", "Algeria", "Tunisia", "Egypt", "South Africa", "Kenya",
      "Tanzania", "Zimbabwe", "Zambia", "Rwanda", "Burundi", "Niger",
      "Chad", "Gabon", "Benin", "Togo", "Liberia", "Sierra Leone",
      "Central African Republic", "Equatorial Guinea", "Guinea",
      "Guinea-Bissau", "Mali", "Mauritania", "Namibia", "Madagascar",
      "Mozambique", "Burkina Faso", "Burkina", "Cote d'Ivoire",
      "Cape Verde", "Comoros", "The Gambia"
    ) ~ "Africa",
    nationality %in% c("Australia", "New Zealand") ~ "Oceania",
    TRUE ~ "Other"
  )
}

clean_position <- function(position) {
  raw_position <- word(position, 1)

  case_when(
    raw_position %in% c("attack", "Attacker", "Forward") ~ "Attack",
    raw_position %in% c("midfield", "Midfielder") ~ "Midfield",
    raw_position %in% c("Defender", "Defense") ~ "Defense",
    raw_position %in% c("Goalkeeper", "Keeper") ~ "Goalkeeper",
    TRUE ~ raw_position
  )
}

read_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      player_id = as.integer(player_id),
      Month = as.Date(Month),
      Date_scraped = as.Date(Date_scraped),
      ContractExpiryDate = as.Date(ContractExpiryDate),
      LastExtensionDate = as.Date(LastExtensionDate),
      DateOfBirth = as.Date(DateOfBirth),
      Bosman = as.logical(Bosman)
    )
}

read_monthly_master <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      tm_player_id = as.integer(tm_player_id),
      fotmob_player_id = as.integer(fotmob_player_id),
      Month = as.Date(Month)
    )
}

fotmob_cols <- c(
  "fotmob_player_id",
  "fotmob_player_name",
  "fotmob_position_group",
  "fotmob_squad_role",
  "fotmob_source_league",
  "fotmob_source_league_id",
  "fotmob_matches",
  "fotmob_appearances",
  "fotmob_starts_proxy",
  "fotmob_minutes",
  "fotmob_goals",
  "fotmob_assists",
  "fotmob_yellow_cards",
  "fotmob_red_cards",
  "fotmob_mean_rating",
  "fotmob_minutes_weighted_rating",
  "fotmob_top_ratings",
  "fotmob_player_of_match_awards",
  "crosswalk_match_method",
  "crosswalk_candidate_score",
  "has_fotmob_rating",
  "has_fotmob_weighted_rating",
  "fotmob_applicable"
)

monthly_to_panel_cols <- function(monthly_master) {
  monthly_master %>%
    transmute(
      player_id = tm_player_id,
      Month,
      fotmob_player_id,
      fotmob_player_name,
      fotmob_position_group,
      fotmob_squad_role,
      fotmob_source_league = source_league_name,
      fotmob_source_league_id = source_league_id,
      fotmob_matches = matches,
      fotmob_appearances = appearances,
      fotmob_starts_proxy = starts_proxy,
      fotmob_minutes = minutes,
      fotmob_goals = goals,
      fotmob_assists = assists,
      fotmob_yellow_cards = yellow_cards,
      fotmob_red_cards = red_cards,
      fotmob_mean_rating = mean_rating,
      fotmob_minutes_weighted_rating = minutes_weighted_rating,
      fotmob_top_ratings = top_ratings,
      fotmob_player_of_match_awards = player_of_match_awards,
      crosswalk_match_method,
      crosswalk_candidate_score
    )
}

augment_panel <- function(panel, monthly_master) {
  monthly_panel <- monthly_to_panel_cols(monthly_master) %>%
    distinct(player_id, Month, .keep_all = TRUE)

  panel_base <- panel %>%
    select(-any_of(fotmob_cols))

  panel_with_monthly <- panel_base %>%
    left_join(monthly_panel, by = c("player_id", "Month")) %>%
    mutate(
      has_fotmob_rating = !is.na(fotmob_mean_rating),
      has_fotmob_weighted_rating = !is.na(fotmob_minutes_weighted_rating),
      fotmob_applicable = has_fotmob_rating & coalesce(fotmob_minutes, 0) > 0
    )

  existing_keys <- panel_base %>%
    select(player_id, Month) %>%
    distinct()

  missing_months <- monthly_panel %>%
    anti_join(existing_keys, by = c("player_id", "Month"))

  contract_base <- panel_base %>%
    arrange(player_id, Month)

  setDT(contract_base)
  setDT(missing_months)
  setkey(contract_base, player_id, Month)
  setkey(missing_months, player_id, Month)

  additions <- contract_base[missing_months, roll = TRUE] %>%
    as_tibble() %>%
    filter(!is.na(ContractExpiryDate)) %>%
    mutate(
      Date_scraped = Month,
      MonthID = as.integer(format(Month, "%Y%m")),
      Matches_tm = 0L,
      Minutes_tm = 0,
      Goals_tm = 0,
      Assists_tm = 0,
      Goals_per90_tm = NA_real_,
      Assists_per90_tm = NA_real_,
      GA_per90_tm = NA_real_,
      DaysToExpiry = as.numeric(ContractExpiryDate - Date_scraped),
      Bosman = DaysToExpiry <= 183,
      ExpiryBin = make_expiry_bin(DaysToExpiry),
      Age = floor(as.numeric((Date_scraped - DateOfBirth) / 365.25)),
      country_region = map_country_region(nationality_new),
      GenPosition = clean_position(PlayerPosition),
      has_fotmob_rating = !is.na(fotmob_mean_rating),
      has_fotmob_weighted_rating = !is.na(fotmob_minutes_weighted_rating),
      fotmob_applicable = has_fotmob_rating & coalesce(fotmob_minutes, 0) > 0
    ) %>%
    filter(!is.na(DaysToExpiry), DaysToExpiry >= 0)

  bind_rows(panel_with_monthly, additions) %>%
    distinct(player_id, Month, .keep_all = TRUE) %>%
    arrange(player_id, Month)
}

write_augmented_panel <- function(panel_path, strict_path, monthly_path) {
  panel <- read_panel(panel_path)
  monthly_master <- read_monthly_master(monthly_path)
  augmented <- augment_panel(panel, monthly_master)
  augmented <- augmented %>% select(all_of(names(panel)))

  strict <- augmented %>%
    filter(
      has_fotmob_rating,
      coalesce(fotmob_minutes, 0) > 0,
      coalesce(fotmob_matches, 0) > 0
    )

  write_csv(augmented, panel_path, na = "")
  write_csv(strict, strict_path, na = "")

  tibble(
    panel_path = panel_path,
    panel_rows_before = nrow(panel),
    panel_rows_after = nrow(augmented),
    strict_rows_after = nrow(strict),
    strict_players_after = n_distinct(strict$player_id)
  )
}

results <- bind_rows(
  write_augmented_panel(
    path_in("data", "panel", "fotmob_analysis_panel_all_comps.csv"),
    path_in("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv"),
    path_in("data", "master", "fotmob_master_monthly_all_comps.csv")
  ),
  write_augmented_panel(
    path_in("data", "panel", "fotmob_analysis_panel_source_league.csv"),
    path_in("data", "panel", "fotmob_analysis_panel_source_league_strict.csv"),
    path_in("data", "master", "fotmob_master_monthly_source_league.csv")
  )
)

manifest <- tibble(
  dataset = c(
    "panel_source_league",
    "panel_all_comps",
    "panel_source_league_strict",
    "panel_all_comps_strict"
  ),
  rows = c(
    nrow(read_panel(path_in("data", "panel", "fotmob_analysis_panel_source_league.csv"))),
    nrow(read_panel(path_in("data", "panel", "fotmob_analysis_panel_all_comps.csv"))),
    nrow(read_panel(path_in("data", "panel", "fotmob_analysis_panel_source_league_strict.csv"))),
    nrow(read_panel(path_in("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")))
  ),
  unique_players = c(
    n_distinct(read_panel(path_in("data", "panel", "fotmob_analysis_panel_source_league.csv"))$player_id),
    n_distinct(read_panel(path_in("data", "panel", "fotmob_analysis_panel_all_comps.csv"))$player_id),
    n_distinct(read_panel(path_in("data", "panel", "fotmob_analysis_panel_source_league_strict.csv"))$player_id),
    n_distinct(read_panel(path_in("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv"))$player_id)
  ),
  rows_with_rating = c(
    sum(read_panel(path_in("data", "panel", "fotmob_analysis_panel_source_league.csv"))$has_fotmob_rating, na.rm = TRUE),
    sum(read_panel(path_in("data", "panel", "fotmob_analysis_panel_all_comps.csv"))$has_fotmob_rating, na.rm = TRUE),
    sum(read_panel(path_in("data", "panel", "fotmob_analysis_panel_source_league_strict.csv"))$has_fotmob_rating, na.rm = TRUE),
    sum(read_panel(path_in("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv"))$has_fotmob_rating, na.rm = TRUE)
  )
)

write_csv(manifest, path_in("data", "panel", "fotmob_analysis_panel_manifest.csv"), na = "")
print(results)
print(manifest)
