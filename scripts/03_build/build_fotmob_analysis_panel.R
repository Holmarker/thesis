library(DBI)
library(RSQLite)
library(data.table)
library(dplyr)
library(lubridate)
library(openxlsx)
library(readr)
library(stringr)
library(tidyr)

db_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/OTP-PVM-4.0/valuation_db.sqlite"
bios_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller data.xlsx"
master_monthly_source_path <- "data/master/fotmob_master_monthly_source_league.csv"
master_monthly_all_path <- "data/master/fotmob_master_monthly_all_comps.csv"
panel_dir <- "data/panel"

panel_source_out <- file.path(panel_dir, "fotmob_analysis_panel_source_league.csv")
panel_all_out <- file.path(panel_dir, "fotmob_analysis_panel_all_comps.csv")
panel_source_strict_out <- file.path(panel_dir, "fotmob_analysis_panel_source_league_strict.csv")
panel_all_strict_out <- file.path(panel_dir, "fotmob_analysis_panel_all_comps_strict.csv")
manifest_out <- file.path(panel_dir, "fotmob_analysis_panel_manifest.csv")

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
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

parse_mixed_date <- function(x) {
  if (inherits(x, "Date")) {
    return(as.Date(x))
  }

  x_chr <- as.character(x)
  parsed_dmy <- suppressWarnings(dmy(x_chr))
  parsed_ymd <- suppressWarnings(ymd(x_chr))
  coalesce(parsed_dmy, parsed_ymd)
}

load_playerstats_monthly <- function(con, relevant_player_ids) {
  dbGetQuery(con, "SELECT * FROM playerstats_processed") %>%
    filter(as.integer(PlayerID) %in% relevant_player_ids) %>%
    mutate(
      Date = dmy(Date),
      Month = floor_date(Date, "month")
    ) %>%
    group_by(PlayerID, Month) %>%
    summarise(
      Season = first(Season),
      ClubID = first(ClubID),
      Club = first(Club),
      Matches_tm = n(),
      Minutes_tm = sum(Minutes, na.rm = TRUE),
      Goals_tm = sum(Goals, na.rm = TRUE),
      Assists_tm = sum(Assists, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    group_by(PlayerID) %>%
    complete(Month = seq.Date(min(Month), max(Month), by = "month")) %>%
    arrange(PlayerID, Month) %>%
    fill(ClubID, Club, .direction = "downup") %>%
    mutate(
      Matches_tm = coalesce(Matches_tm, 0L),
      Minutes_tm = coalesce(Minutes_tm, 0),
      Goals_tm = coalesce(Goals_tm, 0),
      Assists_tm = coalesce(Assists_tm, 0),
      Goals_per90_tm = if_else(Minutes_tm > 0, Goals_tm / Minutes_tm * 90, NA_real_),
      Assists_per90_tm = if_else(Minutes_tm > 0, Assists_tm / Minutes_tm * 90, NA_real_),
      GA_per90_tm = if_else(Minutes_tm > 0, (Goals_tm + Assists_tm) / Minutes_tm * 90, NA_real_),
      MonthID = as.integer(format(Month, "%Y%m"))
    ) %>%
    ungroup() %>%
    transmute(
      player_id = as.integer(PlayerID),
      Month = as.Date(Month),
      ClubID,
      Club,
      Matches_tm,
      Minutes_tm,
      Goals_tm,
      Assists_tm,
      Goals_per90_tm,
      Assists_per90_tm,
      GA_per90_tm,
      MonthID
    )
}

load_snapshots <- function(playerbios, relevant_player_ids) {
  playerbios %>%
    filter(player_id %in% relevant_player_ids) %>%
    transmute(
      player_id = as.integer(player_id),
      Date_scraped = as.Date(Date_scraped, origin = "1899-12-30"),
      ContractExpiryDate = parse_mixed_date(ContractExpiryDate),
      LastExtensionDate = parse_mixed_date(LastExtensionDate)
    )
}

load_player_demo <- function(playerbios, relevant_player_ids) {
  playerbios %>%
    filter(player_id %in% relevant_player_ids) %>%
    mutate(
      player_id = as.integer(player_id),
      Date_scraped = as.Date(Date_scraped, origin = "1899-12-30")
    ) %>%
    arrange(player_id, Date_scraped) %>%
    group_by(player_id) %>%
    summarise(
      DateOfBirth = parse_mixed_date(first(DateOfBirth)),
      PlayerHeight = first(PlayerHeight),
      PreferredFoot = first(PreferredFoot),
      PlayerPosition = first(PlayerPosition),
      nationality_new = first(nationality_new),
      .groups = "drop"
    )
}

load_master_monthly <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      tm_date_of_birth = as.Date(tm_date_of_birth)
    ) %>%
    distinct(tm_player_id, Month, .keep_all = TRUE) %>%
    transmute(
      player_id = as.integer(tm_player_id),
      Month,
      fotmob_player_id = as.integer(fotmob_player_id),
      fotmob_player_name,
      fotmob_position_group,
      fotmob_squad_role,
      fotmob_source_league = source_league_name,
      fotmob_source_league_id = as.integer(source_league_id),
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

build_panel <- function(monthly_master, snapshots, stats, player_demo) {
  rating_months <- monthly_master %>%
    select(player_id, Month) %>%
    distinct()

  stats <- stats %>%
    full_join(rating_months, by = c("player_id", "Month")) %>%
    mutate(
      Matches_tm = coalesce(Matches_tm, 0L),
      Minutes_tm = coalesce(Minutes_tm, 0),
      Goals_tm = coalesce(Goals_tm, 0),
      Assists_tm = coalesce(Assists_tm, 0),
      Goals_per90_tm = if_else(Minutes_tm > 0, Goals_tm / Minutes_tm * 90, NA_real_),
      Assists_per90_tm = if_else(Minutes_tm > 0, Assists_tm / Minutes_tm * 90, NA_real_),
      GA_per90_tm = if_else(Minutes_tm > 0, (Goals_tm + Assists_tm) / Minutes_tm * 90, NA_real_),
      MonthID = coalesce(MonthID, as.integer(format(Month, "%Y%m")))
    )

  setDT(snapshots)
  setDT(stats)
  setkey(snapshots, player_id, Date_scraped)
  setkey(stats, player_id, Month)

  panel <- snapshots[stats, roll = TRUE] %>%
    mutate(
      Month = as.Date(Date_scraped),
      ContractExpiryDate = as.Date(ContractExpiryDate),
      Date_scraped = as.Date(Date_scraped),
      DaysToExpiry = as.numeric(ContractExpiryDate - Date_scraped)
    ) %>%
    filter(!is.na(DaysToExpiry), DaysToExpiry >= 0) %>%
    mutate(
      Bosman = DaysToExpiry <= 183,
      ExpiryBin = cut(
        DaysToExpiry,
        breaks = c(0, 90, 180, 365, 730, 1500, Inf),
        labels = c("0-3m", "3-6m", "6-12m", "1-2y", "2-4y", "4y+")
      )
    ) %>%
    left_join(player_demo, by = "player_id") %>%
    left_join(monthly_master, by = c("player_id", "Month")) %>%
    mutate(
      Age = floor(as.numeric((Date_scraped - DateOfBirth) / 365.25)),
      country_region = map_country_region(nationality_new),
      GenPosition = clean_position(PlayerPosition),
      has_fotmob_rating = !is.na(fotmob_mean_rating),
      has_fotmob_weighted_rating = !is.na(fotmob_minutes_weighted_rating),
      fotmob_applicable = has_fotmob_rating & coalesce(fotmob_minutes, 0) > 0
    )

  as_tibble(panel)
}

build_strict_panel <- function(panel) {
  panel %>%
    filter(
      has_fotmob_rating,
      coalesce(fotmob_minutes, 0) > 0,
      coalesce(fotmob_matches, 0) > 0
    )
}

build_manifest <- function(panel_source, panel_all, panel_source_strict, panel_all_strict) {
  tibble(
    dataset = c(
      "panel_source_league",
      "panel_all_comps",
      "panel_source_league_strict",
      "panel_all_comps_strict"
    ),
    rows = c(
      nrow(panel_source),
      nrow(panel_all),
      nrow(panel_source_strict),
      nrow(panel_all_strict)
    ),
    unique_players = c(
      n_distinct(panel_source$player_id),
      n_distinct(panel_all$player_id),
      n_distinct(panel_source_strict$player_id),
      n_distinct(panel_all_strict$player_id)
    ),
    rows_with_rating = c(
      sum(panel_source$has_fotmob_rating, na.rm = TRUE),
      sum(panel_all$has_fotmob_rating, na.rm = TRUE),
      sum(panel_source_strict$has_fotmob_rating, na.rm = TRUE),
      sum(panel_all_strict$has_fotmob_rating, na.rm = TRUE)
    )
  )
}

ensure_dir(panel_dir)

monthly_source_master <- load_master_monthly(master_monthly_source_path)
monthly_all_master <- load_master_monthly(master_monthly_all_path)
relevant_player_ids <- sort(unique(c(monthly_source_master$player_id, monthly_all_master$player_id)))

con <- dbConnect(RSQLite::SQLite(), db_path)
on.exit(dbDisconnect(con), add = TRUE)

playerbios <- read.xlsx(bios_path) %>%
  filter(is.na(OnLoanFrom))

stats <- load_playerstats_monthly(con, relevant_player_ids)
snapshots <- load_snapshots(playerbios, relevant_player_ids)
player_demo <- load_player_demo(playerbios, relevant_player_ids)

panel_source <- build_panel(monthly_source_master, snapshots, stats, player_demo)
panel_all <- build_panel(monthly_all_master, snapshots, stats, player_demo)
panel_source_strict <- build_strict_panel(panel_source)
panel_all_strict <- build_strict_panel(panel_all)
manifest <- build_manifest(panel_source, panel_all, panel_source_strict, panel_all_strict)

write_csv(panel_source, panel_source_out, na = "")
message("Saved source-league analysis panel to: ", panel_source_out)

write_csv(panel_all, panel_all_out, na = "")
message("Saved all-competitions analysis panel to: ", panel_all_out)

write_csv(panel_source_strict, panel_source_strict_out, na = "")
message("Saved strict source-league analysis panel to: ", panel_source_strict_out)

write_csv(panel_all_strict, panel_all_strict_out, na = "")
message("Saved strict all-competitions analysis panel to: ", panel_all_strict_out)

write_csv(manifest, manifest_out, na = "")
message("Saved panel manifest to: ", manifest_out)
