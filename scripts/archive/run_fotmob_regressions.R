library(DBI)
library(RSQLite)
library(broom)
library(data.table)
library(dplyr)
library(fixest)
library(lubridate)
library(openxlsx)
library(readr)
library(stringr)
library(tidyr)

db_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/OTP-PVM-4.0/valuation_db.sqlite"
bios_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller data.xlsx"
fotmob_crosswalk_path <- "RSpeciale/data/fotmob_transfermarkt_crosswalk_confirmed.csv"
fotmob_monthly_path <- "RSpeciale/data/fotmob_ratings_monthly_source_league.csv"

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

con <- dbConnect(RSQLite::SQLite(), db_path)
on.exit(dbDisconnect(con), add = TRUE)

playerstats <- dbGetQuery(con, "SELECT * FROM playerstats_processed")
cat("Loaded playerstats\n")
playerbios_raw <- read.xlsx(bios_path) %>%
  filter(is.na(OnLoanFrom))
cat("Loaded playerbios\n")

fotmob_crosswalk <- read_csv(fotmob_crosswalk_path, show_col_types = FALSE) %>%
  filter(merge_safe) %>%
  transmute(
    player_id = as.integer(tm_player_id),
    fotmob_player_id = as.integer(fotmob_player_id)
  ) %>%
  distinct(player_id, .keep_all = TRUE)

relevant_player_ids <- fotmob_crosswalk$player_id

playerbios <- playerbios_raw %>%
  transmute(
    player_id = as.integer(player_id),
    Date_scraped = as.Date(Date_scraped, origin = "1899-12-30"),
    ContractExpiryDate = parse_mixed_date(ContractExpiryDate),
    DateOfBirth = parse_mixed_date(DateOfBirth),
    PlayerPosition,
    nationality_new
  ) %>%
  filter(player_id %in% relevant_player_ids)

playerstats <- playerstats %>%
  filter(as.integer(PlayerID) %in% relevant_player_ids)
cat("Filtered to relevant players\n")

playerstats_monthly <- playerstats %>%
  mutate(
    Date = dmy(Date),
    Month = floor_date(Date, "month")
  ) %>%
  group_by(PlayerID, Month) %>%
  summarise(
    Minutes = sum(Minutes, na.rm = TRUE),
    Goals = sum(Goals, na.rm = TRUE),
    Assists = sum(Assists, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    Minutes = coalesce(Minutes, 0),
    Goals = coalesce(Goals, 0),
    Assists = coalesce(Assists, 0),
    Goals_per90 = if_else(Minutes > 0, Goals / Minutes * 90, NA_real_)
  ) %>%
  ungroup()
cat("Built playerstats_monthly\n")

rm(playerstats)
gc()

snapshots <- playerbios %>%
  transmute(player_id, Date_scraped, ContractExpiryDate)

stats <- playerstats_monthly %>%
  transmute(
    player_id = as.integer(PlayerID),
    Month = as.Date(Month),
    Minutes,
    Goals,
    Assists,
    Goals_per90
  )

player_demo <- playerbios %>%
  arrange(player_id, Date_scraped) %>%
  group_by(player_id) %>%
  summarise(
    DateOfBirth = first(DateOfBirth),
    PlayerPosition = first(PlayerPosition),
    nationality_new = first(nationality_new),
    .groups = "drop"
  ) %>%
  distinct()

fotmob_monthly <- read_csv(fotmob_monthly_path, show_col_types = FALSE) %>%
  transmute(
    fotmob_player_id = as.integer(fotmob_player_id),
    Month = as.Date(Month),
    fotmob_matches = matches,
    fotmob_minutes = minutes,
    fotmob_mean_rating = mean_rating,
    fotmob_minutes_weighted_rating = minutes_weighted_rating
  )

fotmob_panel <- fotmob_crosswalk %>%
  inner_join(fotmob_monthly, by = "fotmob_player_id")
cat("Built fotmob panel inputs\n")

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
  left_join(fotmob_panel, by = c("player_id", "Month")) %>%
  mutate(
    Age = floor(as.numeric((Date_scraped - DateOfBirth) / 365.25)),
    country_region = map_country_region(nationality_new),
    GenPosition = clean_position(PlayerPosition)
  )
cat("Built merged panel\n")

rm(snapshots, stats, player_demo, fotmob_crosswalk, fotmob_monthly, fotmob_panel, playerbios, playerstats_monthly)
gc()

panel_fotmob <- panel %>%
  filter(!is.na(fotmob_mean_rating))

panel_fotmob_weighted <- panel %>%
  filter(!is.na(fotmob_minutes_weighted_rating), fotmob_minutes >= 90)
cat("Built FotMob samples\n")

fotmob_rating_ols <- lm(fotmob_mean_rating ~ Bosman + Age + I(Age^2), data = panel_fotmob)
cat("Ran OLS mean rating\n")
fotmob_weighted_rating_ols <- lm(
  fotmob_minutes_weighted_rating ~ Bosman + Age + I(Age^2),
  data = panel_fotmob_weighted
)
cat("Ran OLS weighted rating\n")

fotmob_rating_fe <- feols(
  fotmob_mean_rating ~ Bosman | player_id + Month,
  data = panel_fotmob,
  cluster = ~player_id
)
cat("Ran FE mean rating\n")

fotmob_weighted_rating_fe <- feols(
  fotmob_minutes_weighted_rating ~ Bosman | player_id + Month,
  data = panel_fotmob_weighted,
  cluster = ~player_id
)
cat("Ran FE weighted rating\n")

fotmob_event_model <- feols(
  fotmob_mean_rating ~ i(ExpiryBin, ref = "2-4y") | player_id + Month,
  data = panel_fotmob,
  cluster = ~player_id
)
cat("Ran event model\n")

coverage <- tibble(
  panel_rows = nrow(panel),
  panel_players = n_distinct(panel$player_id),
  rows_with_fotmob_rating = sum(!is.na(panel$fotmob_mean_rating)),
  players_with_fotmob_rating = n_distinct(panel$player_id[!is.na(panel$fotmob_mean_rating)])
)

cat("Coverage\n")
print(coverage)
cat("\nOLS mean rating\n")
print(broom::tidy(fotmob_rating_ols))
cat("\nOLS weighted rating\n")
print(broom::tidy(fotmob_weighted_rating_ols))
cat("\nFE mean rating\n")
print(broom::tidy(fotmob_rating_fe))
cat("\nFE weighted rating\n")
print(broom::tidy(fotmob_weighted_rating_fe))
cat("\nEvent model\n")
print(broom::tidy(fotmob_event_model))
