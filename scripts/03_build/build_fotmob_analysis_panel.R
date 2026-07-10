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
live_monthly_source_path <- "data/fotmob_ratings_monthly_source_league.csv"
live_monthly_all_path <- "data/fotmob_ratings_monthly_all_comps.csv"
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

# master monthly lacks match-result columns; join them from the
# fixtures-linked live monthly aggregates where available
win_cols <- c("result_matches", "wins", "draws", "losses",
              "win_share", "result_points_per_match")

read_win_supplement <- function(live_monthly_path) {
  read_csv(live_monthly_path, show_col_types = FALSE) %>%
    mutate(fotmob_player_id = as.integer(fotmob_player_id),
           Month = as.Date(Month)) %>%
    filter(!is.na(fotmob_player_id), !is.na(Month)) %>%
    group_by(fotmob_player_id, Month) %>%
    slice_max(coalesce(result_matches, 0L), n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(fotmob_player_id, Month, all_of(win_cols))
}

load_master_monthly <- function(path, live_monthly_path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Month = as.Date(Month),
      tm_date_of_birth = as.Date(tm_date_of_birth)
    ) %>%
    select(-any_of(win_cols)) %>%
    mutate(fotmob_player_id = as.integer(fotmob_player_id)) %>%
    left_join(read_win_supplement(live_monthly_path),
              by = c("fotmob_player_id", "Month")) %>%
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
      fotmob_result_matches = result_matches,
      fotmob_wins = wins,
      fotmob_draws = draws,
      fotmob_losses = losses,
      fotmob_win_share = win_share,
      fotmob_result_points_per_match = result_points_per_match,
      fotmob_mean_rating = mean_rating,
      fotmob_minutes_weighted_rating = minutes_weighted_rating,
      fotmob_top_ratings = top_ratings,
      fotmob_player_of_match_awards = player_of_match_awards,
      crosswalk_match_method,
      crosswalk_candidate_score
    )
}

# A contract-expiry snapshot is static absent a transfer or renewal, so a
# player's first-ever OTP snapshot can be projected backward to fill months
# before it, as long as (a) the gap is bounded and (b) the player's club was
# unchanged between the candidate month and the snapshot month (checked via
# the TM appearance history in `stats`, which runs earlier than the contract
# snapshots for players added to tracking later than their FotMob coverage).
BACKWARD_FILL_MAX_GAP_DAYS <- 365

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

  club_by_month <- stats %>%
    select(player_id, Month, ClubID) %>%
    distinct(player_id, Month, .keep_all = TRUE)

  snapshots_keyed <- snapshots %>%
    mutate(matched_snapshot_date = Date_scraped)

  setDT(snapshots_keyed)
  setDT(stats)
  setkey(snapshots_keyed, player_id, Date_scraped)
  setkey(stats, player_id, Month)

  forward <- as_tibble(snapshots_keyed[stats, roll = TRUE]) %>%
    rename(month_key = Date_scraped) %>%
    mutate(contract_date_source = if_else(!is.na(ContractExpiryDate), "observed", NA_character_))

  backward <- as_tibble(snapshots_keyed[stats, roll = -Inf]) %>%
    transmute(
      player_id,
      month_key = Date_scraped,
      bf_ContractExpiryDate = ContractExpiryDate,
      bf_LastExtensionDate = LastExtensionDate,
      bf_matched_snapshot_date = matched_snapshot_date
    )

  panel_dt <- forward %>%
    left_join(backward, by = c("player_id", "month_key")) %>%
    left_join(
      club_by_month %>% rename(club_at_candidate = ClubID),
      by = c("player_id", "month_key" = "Month")
    ) %>%
    mutate(bf_matched_month = as.Date(format(bf_matched_snapshot_date, "%Y-%m-01"))) %>%
    left_join(
      club_by_month %>% rename(club_at_bf_snapshot = ClubID),
      by = c("player_id", "bf_matched_month" = "Month")
    ) %>%
    mutate(
      bf_gap_days = as.numeric(bf_matched_snapshot_date - month_key),
      bf_eligible = is.na(ContractExpiryDate) &
        !is.na(bf_ContractExpiryDate) &
        bf_gap_days <= BACKWARD_FILL_MAX_GAP_DAYS &
        !is.na(club_at_candidate) & !is.na(club_at_bf_snapshot) &
        club_at_candidate == club_at_bf_snapshot,
      ContractExpiryDate = if_else(bf_eligible, bf_ContractExpiryDate, ContractExpiryDate),
      LastExtensionDate = if_else(bf_eligible, bf_LastExtensionDate, LastExtensionDate),
      contract_date_source = if_else(bf_eligible, "backward_filled", contract_date_source)
    ) %>%
    select(-starts_with("bf_"), -club_at_candidate, -club_at_bf_snapshot) %>%
    rename(Date_scraped = month_key)

  panel <- panel_dt %>%
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
    ),
    rows_backward_filled = c(
      sum(panel_source$contract_date_source == "backward_filled", na.rm = TRUE),
      sum(panel_all$contract_date_source == "backward_filled", na.rm = TRUE),
      sum(panel_source_strict$contract_date_source == "backward_filled", na.rm = TRUE),
      sum(panel_all_strict$contract_date_source == "backward_filled", na.rm = TRUE)
    )
  )
}

ensure_dir(panel_dir)

monthly_source_master <- load_master_monthly(master_monthly_source_path, live_monthly_source_path)
monthly_all_master <- load_master_monthly(master_monthly_all_path, live_monthly_all_path)
relevant_player_ids <- sort(unique(c(monthly_source_master$player_id, monthly_all_master$player_id)))

con <- dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
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
