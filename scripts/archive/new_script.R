library(DBI)
library(RSQLite)
library(broom)
library(data.table)
library(dplyr)
library(fixest)
library(ggplot2)
library(lubridate)
library(openxlsx)
library(purrr)
library(readr)
library(stringr)
library(tidyr)

db_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/OTP-PVM-4.0/valuation_db.sqlite"
bios_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller data.xlsx"
history_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller historik_arkiv.xlsx"
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

make_bin_plot <- function(data, y_var, y_label, title) {
  plot_data <- data %>%
    filter(!is.na(ExpiryBin)) %>%
    group_by(ExpiryBin) %>%
    summarise(
      value = mean(.data[[y_var]], na.rm = TRUE),
      n = n(),
      .groups = "drop"
    )

  ggplot(plot_data, aes(x = ExpiryBin, y = value)) +
    geom_col(fill = "steelblue") +
    labs(
      x = "Days to Contract Expiry",
      y = y_label,
      title = title
    ) +
    theme_minimal()
}

con <- dbConnect(RSQLite::SQLite(), db_path)
on.exit(dbDisconnect(con), add = TRUE)

playerstats <- dbGetQuery(con, "SELECT * FROM playerstats_processed")
playerbios <- read.xlsx(bios_path) %>%
  filter(is.na(OnLoanFrom)) %>%
  mutate(Date_scraped = as.Date(Date_scraped, origin = "1899-12-30"))
playerhist <- read.xlsx(history_path) %>%
  mutate(Date_scraped = as.Date(Date_scraped, origin = "1899-12-30"))

playerstats_monthly <- playerstats %>%
  mutate(
    Date = dmy(Date),
    Month = floor_date(Date, "month")
  ) %>%
  group_by(PlayerID, Month) %>%
  summarise(
    Season = first(Season),
    ClubID = first(ClubID),
    Club = first(Club),
    Matches = n(),
    Minutes = sum(Minutes, na.rm = TRUE),
    Goals = sum(Goals, na.rm = TRUE),
    Assists = sum(Assists, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(PlayerID) %>%
  complete(Month = seq.Date(min(Month), max(Month), by = "month")) %>%
  arrange(PlayerID, Month) %>%
  fill(ClubID, Club, .direction = "downup") %>%
  mutate(
    Matches = coalesce(Matches, 0L),
    Minutes = coalesce(Minutes, 0),
    Goals = coalesce(Goals, 0),
    Assists = coalesce(Assists, 0),
    Goals_per90 = if_else(Minutes > 0, Goals / Minutes * 90, NA_real_),
    Assists_per90 = if_else(Minutes > 0, Assists / Minutes * 90, NA_real_),
    GA_per90 = if_else(Minutes > 0, (Goals + Assists) / Minutes * 90, NA_real_),
    Season = if_else(month(Month) >= 8, year(Month), year(Month) - 1),
    MonthID = as.integer(format(Month, "%Y%m"))
  ) %>%
  ungroup()

contract_snapshot <- playerbios %>%
  group_by(player_id) %>%
  summarise(
    n_obs = n(),
    n_expiry = n_distinct(ContractExpiryDate),
    .groups = "drop"
  )

snapshots_by_year <- playerbios %>%
  mutate(year = year(Date_scraped)) %>%
  count(year)

snapshots <- playerbios %>%
  transmute(
    player_id = as.integer(player_id),
    Date_scraped = as.Date(Date_scraped),
    ContractExpiryDate = parse_mixed_date(ContractExpiryDate),
    LastExtensionDate = parse_mixed_date(LastExtensionDate)
  )

stats <- playerstats_monthly %>%
  transmute(
    player_id = as.integer(PlayerID),
    Month = as.Date(Month),
    Minutes,
    Goals,
    Assists,
    Goals_per90,
    Assists_per90,
    GA_per90
  )

fotmob_crosswalk <- read_csv(fotmob_crosswalk_path, show_col_types = FALSE) %>%
  filter(merge_safe) %>%
  transmute(
    player_id = as.integer(tm_player_id),
    fotmob_player_id = as.integer(fotmob_player_id),
    fotmob_source_league = source_league_name
  ) %>%
  distinct(player_id, .keep_all = TRUE)

fotmob_monthly <- read_csv(fotmob_monthly_path, show_col_types = FALSE) %>%
  transmute(
    fotmob_player_id = as.integer(fotmob_player_id),
    Month = as.Date(Month),
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
    fotmob_player_of_match_awards = player_of_match_awards
  )

fotmob_panel <- fotmob_crosswalk %>%
  inner_join(fotmob_monthly, by = "fotmob_player_id")

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
  )

player_demo <- playerbios %>%
  arrange(player_id, Date_scraped) %>%
  group_by(player_id) %>%
  summarise(
    DateOfBirth = first(DateOfBirth),
    PlayerHeight = first(PlayerHeight),
    PreferredFoot = first(PreferredFoot),
    PlayerPosition = first(PlayerPosition),
    nationality_new = first(nationality_new),
    .groups = "drop"
  ) %>%
  mutate(
    player_id = as.integer(player_id),
    DateOfBirth = parse_mixed_date(DateOfBirth)
  )

panel <- panel %>%
  left_join(player_demo, by = "player_id") %>%
  left_join(fotmob_panel, by = c("player_id", "Month")) %>%
  mutate(
    Age = floor(as.numeric((Date_scraped - DateOfBirth) / 365.25)),
    country_region = map_country_region(nationality_new),
    EU_player = if_else(
      country_region %in% c(
        "Northern Europe", "Western Europe", "Southern Europe", "Eastern Europe"
      ),
      1,
      0
    ),
    months_to_expiry = pmax(pmin(round(DaysToExpiry / 30), 24), -6),
    GenPosition = clean_position(PlayerPosition)
  )

fotmob_coverage <- panel %>%
  summarise(
    panel_rows = n(),
    panel_players = n_distinct(player_id),
    rows_with_fotmob_rating = sum(!is.na(fotmob_mean_rating)),
    players_with_fotmob_rating = n_distinct(player_id[!is.na(fotmob_mean_rating)])
  )

panel_filtered <- panel %>%
  filter(Minutes >= 90)

panel_fotmob <- panel %>%
  filter(!is.na(fotmob_mean_rating))

panel_fotmob_weighted <- panel %>%
  filter(!is.na(fotmob_minutes_weighted_rating), fotmob_minutes >= 90)

plot_goals <- make_bin_plot(panel, "Goals", "Average Goals", "Player Goals by Contract Expiry Phase")
plot_minutes <- make_bin_plot(panel, "Minutes", "Average Minutes Played", "Player Minutes by Contract Expiry Phase")
plot_goals_per90 <- make_bin_plot(panel, "Goals_per90", "Average Goals per 90", "Player Goals per 90 by Contract Expiry Phase")
plot_assists <- make_bin_plot(panel, "Assists", "Average Assists", "Player Assists by Contract Expiry Phase")
plot_fotmob_rating <- make_bin_plot(
  panel_fotmob,
  "fotmob_mean_rating",
  "Average FotMob Rating",
  "FotMob Rating by Contract Expiry Phase"
)
plot_fotmob_weighted_rating <- make_bin_plot(
  panel_fotmob_weighted,
  "fotmob_minutes_weighted_rating",
  "Average Minutes-Weighted FotMob Rating",
  "Minutes-Weighted FotMob Rating by Contract Expiry Phase"
)
plot_goals_per90_filtered <- make_bin_plot(
  panel_filtered,
  "Goals_per90",
  "Average Goals per 90",
  "Player Goals per 90 by Contract Expiry Phase (90+ Minutes)"
)

minutes_model <- lm(Minutes ~ Bosman, data = panel)
goal_model <- lm(Goals ~ Bosman, data = panel)
age_model <- lm(Minutes ~ Bosman + Age + DaysToExpiry + Bosman * Age, data = panel)
simple_ols <- lm(Minutes ~ Bosman + Age + I(Age^2), data = panel)
fotmob_rating_ols <- lm(fotmob_mean_rating ~ Bosman + Age + I(Age^2), data = panel_fotmob)
fotmob_weighted_rating_ols <- lm(
  fotmob_minutes_weighted_rating ~ Bosman + Age + I(Age^2),
  data = panel_fotmob_weighted
)

minutes_fe <- feols(
  Minutes ~ Bosman | player_id + Date_scraped,
  data = panel,
  cluster = ~player_id
)

fotmob_rating_fe <- feols(
  fotmob_mean_rating ~ Bosman | player_id + Month,
  data = panel_fotmob,
  cluster = ~player_id
)

fotmob_weighted_rating_fe <- feols(
  fotmob_minutes_weighted_rating ~ Bosman | player_id + Month,
  data = panel_fotmob_weighted,
  cluster = ~player_id
)

event_model <- feols(
  Goals_per90 ~ i(ExpiryBin, ref = "2-4y") | player_id + Date_scraped,
  data = panel,
  cluster = ~player_id
)

fotmob_event_model <- feols(
  fotmob_mean_rating ~ i(ExpiryBin, ref = "2-4y") | player_id + Month,
  data = panel_fotmob,
  cluster = ~player_id
)

fotmob_weighted_event_model <- feols(
  fotmob_minutes_weighted_rating ~ i(ExpiryBin, ref = "2-4y") | player_id + Month,
  data = panel_fotmob_weighted,
  cluster = ~player_id
)

position_models <- list(
  Attack = panel %>%
    filter(GenPosition == "Attack") %>%
    feols(Goals ~ Bosman | player_id + Date_scraped, cluster = ~player_id),
  Midfield = panel %>%
    filter(GenPosition == "Midfield") %>%
    feols(Goals ~ Bosman | player_id + Date_scraped, cluster = ~player_id),
  Defense = panel %>%
    filter(GenPosition == "Defense") %>%
    feols(Goals ~ Bosman | player_id + Date_scraped, cluster = ~player_id),
  Goalkeeper = panel %>%
    filter(GenPosition == "Goalkeeper") %>%
    feols(Goals ~ Bosman | player_id + Date_scraped, cluster = ~player_id)
)

region_models <- map(
  unique(panel$country_region),
  \(reg) {
    df <- panel %>% filter(country_region == reg)

    feols(
      Goals ~ Bosman + Age + Age * Bosman + I(Age^2) | player_id + Date_scraped,
      data = df,
      cluster = ~player_id
    )
  }
)
names(region_models) <- unique(panel$country_region)

fotmob_position_models <- list(
  Attack = panel_fotmob %>%
    filter(GenPosition == "Attack") %>%
    feols(fotmob_mean_rating ~ Bosman | player_id + Month, cluster = ~player_id),
  Midfield = panel_fotmob %>%
    filter(GenPosition == "Midfield") %>%
    feols(fotmob_mean_rating ~ Bosman | player_id + Month, cluster = ~player_id),
  Defense = panel_fotmob %>%
    filter(GenPosition == "Defense") %>%
    feols(fotmob_mean_rating ~ Bosman | player_id + Month, cluster = ~player_id),
  Goalkeeper = panel_fotmob %>%
    filter(GenPosition == "Goalkeeper") %>%
    feols(fotmob_mean_rating ~ Bosman | player_id + Month, cluster = ~player_id)
)

fotmob_region_models <- map(
  unique(panel_fotmob$country_region),
  \(reg) {
    df <- panel_fotmob %>% filter(country_region == reg)

    feols(
      fotmob_mean_rating ~ Bosman + Age + Age * Bosman + I(Age^2) | player_id + Month,
      data = df,
      cluster = ~player_id
    )
  }
)
names(fotmob_region_models) <- unique(panel_fotmob$country_region)

results_df <- map_dfr(names(region_models), function(reg) {
  model <- region_models[[reg]]
  bosman_row <- broom::tidy(model) %>%
    filter(term == "BosmanTRUE")

  tibble(
    country_region = reg,
    estimate = bosman_row$estimate,
    std_error = bosman_row$std.error,
    statistic = bosman_row$statistic,
    p_value = bosman_row$p.value,
    n_obs = nobs(model)
  )
}) %>%
  mutate(
    significance = case_when(
      p_value < 0.001 ~ "***",
      p_value < 0.01 ~ "**",
      p_value < 0.05 ~ "*",
      p_value < 0.1 ~ ".",
      TRUE ~ ""
    ),
    estimate_pretty = paste0(round(estimate, 2), significance),
    std_error = round(std_error, 2),
    p_value = round(p_value, 4)
  ) %>%
  arrange(desc(estimate))

descriptives <- tibble(
  metric = c(
    "Mean age, Bosman",
    "Mean age, non-Bosman",
    "Mean minutes, Bosman",
    "Mean minutes, non-Bosman",
    "Mean FotMob rating, Bosman",
    "Mean FotMob rating, non-Bosman",
    "Mean EU share, Bosman",
    "Mean EU share, non-Bosman"
  ),
  value = c(
    mean(panel$Age[panel$Bosman], na.rm = TRUE),
    mean(panel$Age[!panel$Bosman], na.rm = TRUE),
    mean(panel$Minutes[panel$Bosman], na.rm = TRUE),
    mean(panel$Minutes[!panel$Bosman], na.rm = TRUE),
    mean(panel_fotmob$fotmob_mean_rating[panel_fotmob$Bosman], na.rm = TRUE),
    mean(panel_fotmob$fotmob_mean_rating[!panel_fotmob$Bosman], na.rm = TRUE),
    mean(panel$EU_player[panel$Bosman], na.rm = TRUE),
    mean(panel$EU_player[!panel$Bosman], na.rm = TRUE)
  )
)

age_histogram <- ggplot(panel, aes(x = Age, fill = Bosman)) +
  geom_histogram(position = "dodge", bins = 30) +
  labs(
    x = "Age",
    y = "Count",
    title = "Age Distribution by Bosman Status"
  ) +
  theme_minimal()

age_density <- ggplot(panel, aes(x = Age, fill = Bosman, colour = Bosman)) +
  geom_density(
    kernel = "gaussian",
    alpha = 0.3,
    adjust = 2
  ) +
  labs(
    x = "Age",
    y = "Density",
    title = "Age Density: Bosman vs Non-Bosman Players"
  ) +
  theme_minimal()

panel <- panel %>%
  mutate(
    Bosman = factor(Bosman, levels = c(FALSE, TRUE), labels = c("Not Bosman", "Bosman"))
  )
