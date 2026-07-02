# load libraries
library(ggplot2)
library(dplyr)
library(tidyr)
library(DBI)
library(RSQLite)
library(openxlsx)
library(lubridate)
library(stringr)


# define con path
con <- dbConnect(RSQLite::SQLite(), "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/OTP-PVM-4.0/valuation_db.sqlite")

# load playerstats data from database
playerstats <- dbGetQuery(con, "SELECT * FROM playerstats_processed")

# load contract information bios 

playerbios <- read.xlsx("/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller data.xlsx")

playerhist <- read.xlsx("/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller historik_arkiv.xlsx")

# turn Date into a date


# monthly playerstats

#  playerstats_monthly2 <- playerstats %>%
 #   mutate(
  #    Date = dmy(Date),
      Month = floor_date(Date, "month")
    ) %>%
    group_by(PlayerID, Month) %>%
    summarise(
      Season = first(Season),
      ClubID = first(ClubID),
      Club = first(Club),
      Matches = n(),
      Minutes = sum(Minutes, na.rm = FALSE),
      Goals = sum(Goals, na.rm = TRUE),
      Assists = sum(Assists, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      Goals_per90 = if_else(Minutes > 0, Goals / Minutes * 90, NA_real_),
      Assists_per90 = if_else(Minutes > 0, Assists / Minutes * 90, NA_real_),
      GA_per90 = if_else(Minutes > 0, (Goals + Assists) / Minutes * 90, NA_real_)
    )

library(dplyr)
library(lubridate)
library(tidyr)

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
  complete(
    Month = seq.Date(min(Month), max(Month), by = "month")
  ) %>%
  arrange(PlayerID, Month) %>%
  fill(ClubID, Club, .direction = "downup") %>%
  mutate(
    Matches = coalesce(Matches, 0L),
    Minutes = coalesce(Minutes, 0),
    Goals = coalesce(Goals, 0),
    Assists = coalesce(Assists, 0)
  ) %>%
  ungroup()

playerstats_monthly <- playerstats_monthly %>%
  mutate(
    Goals_per90 = if_else(Minutes > 0, Goals / Minutes * 90, NA_real_),
    Assists_per90 = if_else(Minutes > 0, Assists / Minutes * 90, NA_real_),
    GA_per90 = if_else(Minutes > 0, (Goals + Assists) / Minutes * 90, NA_real_)
  )

# define Season

playerstats_monthly <- playerstats_monthly %>%
  mutate(
    Season = if_else(month(Month) >= 8, year(Month), year(Month) - 1)
  )


# month ID

playerstats_monthly <- playerstats_monthly %>%
  mutate(
    MonthID = as.integer(format(Month, "%Y%m"))
  )

# remove player that DONT have NA in OnLoanFrom

playerbios <- playerbios %>%
  filter(is.na(OnLoanFrom))

# fix date fromatting

playerbios$Date_scraped <- as.Date(playerbios$Date_scraped, origin = "1899-12-30")

playerhist$Date_scraped <- as.Date(playerhist$Date_scraped, origin = "1899-12-30")

playerbios %>%
  count(player_id) %>%
  summary()


contract_snapshot <- playerbios %>%
  group_by(player_id) %>%
  summarise(
    n_obs = n(),
    n_expiry = n_distinct(ContractExpiryDate),
    .groups = "drop"
  ) %>%
  count(n_expiry)

snapshots <- playerbios %>%
  mutate(year = lubridate::year(Date_scraped)) %>%
  count(year)


snapshots <- playerbios %>%
  select(
    player_id,
    Date_scraped,
    ContractExpiryDate,
    LastExtensionDate
  )

snapshots$Date_scraped <- as.Date(snapshots$Date_scraped)
snapshots$ContractExpiryDate <- dmy(snapshots$ContractExpiryDate)
snapshots$LastExtensionDate <- dmy(snapshots$LastExtensionDate)


setDT(snapshots)

setkey(snapshots, player_id, Date_scraped)

playerstats_monthly$Month <- as.Date(playerstats_monthly$Month)

stats <- playerstats_monthly %>%
  select(
    PlayerID,
    Month,
    Minutes,
    Goals,
    Assists,
    Goals_per90,
    Assists_per90,
    GA_per90
  )

setDT(stats)
setnames(stats, "PlayerID", "player_id")

setkey(stats, player_id, Month)

snapshots <- snapshots %>% 
  mutate(player_id = as.integer(player_id))

panel <- snapshots[stats, roll = TRUE]

panel <- panel %>% 
  mutate(
    ContractExpiryDate = as.Date(ContractExpiryDate),
    Date_scraped = as.Date(Date_scraped)
  )


panel[, DaysToExpiry := as.numeric(ContractExpiryDate - Date_scraped)]

# remove NAs in panel

panel <- panel %>%
  filter(!is.na(DaysToExpiry))

# remove negtive values in DaysToExpiry
panel <- panel %>%
  filter(DaysToExpiry >= 0)

panel[, Bosman := DaysToExpiry <= 183]

table(panel$Bosman)

panel[, ExpiryBin := cut(
  DaysToExpiry,
  breaks = c(0, 90, 180, 365, 730, 1500, Inf),
  labels = c("0-3m", "3-6m", "6-12m", "1-2y", "2-4y", "4y+")
)]
table(panel$ExpiryBin)

summary(panel$DaysToExpiry)
hist(panel$ExpiryBin)

summary(panel$Minutes)

summary(panel$Goals)




plot_data <- panel %>%
  filter(!is.na(ExpiryBin)) %>%
  group_by(ExpiryBin) %>%
  summarise(
    mean_goals = mean(Goals, na.rm = TRUE),
    n = n()
  )

ggplot(plot_data, aes(x = ExpiryBin, y = mean_goals)) +
  geom_col(fill = "steelblue") +
  labs(
    x = "Days to Contract Expiry",
    y = "Average Goals per 90",
    title = "Player Goals by Contract Expiry Phase"
  ) +
  theme_minimal()

plot_minnutes <- panel %>%
  filter(!is.na(ExpiryBin)) %>%
  group_by(ExpiryBin) %>%
  summarise(
    mean_minutes = mean(Minutes, na.rm = TRUE),
    n = n()
  )

ggplot(plot_minnutes, aes(x = ExpiryBin, y = mean_minutes)) +
  geom_col(fill = "steelblue") +
  labs(
    x = "Days to Contract Expiry",
    y = "Average Minutes Played",
    title = "Player Minutes by Contract Expiry Phase"
  ) +
  theme_minimal()

plot_goals_per90 <- panel %>%
  filter(!is.na(ExpiryBin)) %>%
  group_by(ExpiryBin) %>%
  summarise(
    mean_goals_per90 = mean(Goals_per90, na.rm = TRUE),
    n = n()
  )
ggplot(plot_goals_per90, aes(x = ExpiryBin, y = mean_goals_per90)) +
  geom_col(fill = "steelblue") +
  labs(
    x = "Days to Contract Expiry",
    y = "Average Goals per 90",
    title = "Player Goals per 90 by Contract Expiry Phase"
  ) +
  theme_minimal()

plot_assists <- panel %>%
  filter(!is.na(ExpiryBin)) %>%
  group_by(ExpiryBin) %>%
  summarise(
    mean_assists = mean(Assists, na.rm = TRUE),
    n = n()
  )

ggplot(plot_assists, aes(x = ExpiryBin, y = mean_assists)) +
  geom_col(fill = "steelblue") +
  labs(
    x = "Days to Contract Expiry",
    y = "Average Assists",
    title = "Player Assists by Contract Expiry Phase"
  ) +
  theme_minimal()


# panel filtered df

panel_filtered <- panel %>%
  filter(Minutes >= 90)

plot_goals_per90_filtered <- panel_filtered %>%
  filter(!is.na(ExpiryBin)) %>%
  group_by(ExpiryBin) %>%
  summarise(
    mean_goals_per90 = mean(Goals_per90, na.rm = TRUE),
    n = n()
  )
ggplot(plot_goals_per90_filtered, aes(x = ExpiryBin, y = mean_goals_per90)) +
  geom_col(fill = "steelblue") +
  labs(
    x = "Days to Contract Expiry",
    y = "Average Goals per 90",
    title = "Player Goals per 90 by Contract Expiry Phase (90+ Minutes)"
  ) +
  theme_minimal()

model <- lm(Minutes ~ Bosman, data = panel)

summary(model)

goal_model <- lm(Goals ~ Bosman, data = panel)
summary(goal_model)

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
  )

player_demo <- player_demo %>% 
  mutate(DateOfBirth = as.Date(DateOfBirth))

panel <- panel %>% select(-c(DateOfBirth, PlayerHeight, PreferredFoot, PlayerPosition, nationality_new, Age))

panel <- panel %>% select(-c(Age))

panel <- panel %>%
  mutate(player_id = as.character(player_id)) %>% 
  left_join(
    player_demo %>% select(player_id, DateOfBirth, PlayerHeight, PreferredFoot, PlayerPosition, nationality_new),
    by = "player_id"
  )

panel <- panel %>%
  mutate(
    DateOfBirth = lubridate::dmy(DateOfBirth),
    Age = as.numeric((Date_scraped - DateOfBirth) / 365.25)
  )
class(panel$DateOfBirth)
str(panel$DateOfBirth)


panel <- panel %>%
  mutate(
    Age = floor(as.numeric((Date_scraped - DateOfBirth) / 365.25))
  )

age_model <- lm(Minutes ~ Bosman + Age + DaysToExpiry + Bosman*Age, data = panel)
summary(age_model)


feols(
  Minutes ~ Bosman| player_id + Date_scraped,
  data = panel,
  cluster = ~player_id
)

simple_ols <- lm(Minutes ~ Bosman + Age + I(Age^2), data = panel)
summary(simple_ols)



unique(panel$nationality_new)


panel <- panel %>%
  mutate(country_region = case_when(
    
    # Northern Europe
    nationality_new %in% c(
      "Denmark","Sweden","Norway","Finland","Iceland","Faroe Islands"
    ) ~ "Northern Europe",
    
    # Western Europe
    nationality_new %in% c(
      "England","Ireland","Scotland","Wales",
      "Germany","Netherlands","Belgium","France",
      "Austria","Switzerland","Luxembourg"
    ) ~ "Western Europe",
    
    # Southern Europe
    nationality_new %in% c(
      "Spain","Portugal","Italy","Greece","Cyprus","Malta"
    ) ~ "Southern Europe",
    
    # Eastern Europe
    nationality_new %in% c(
      "Poland","Czech Republic","Slovakia","Hungary","Romania","Bulgaria",
      "Ukraine","Russia","Belarus","Serbia","Croatia","Bosnia-Herzegovina",
      "Slovenia","Montenegro","North Macedonia","Albania","Kosovo",
      "Moldova","Georgia","Armenia","Azerbaijan","Estonia","Latvia","Lithuania"
    ) ~ "Eastern Europe",
    
    # North America
    nationality_new %in% c(
      "United States","Canada","Mexico"
    ) ~ "North America",
    
    # Caribbean
    nationality_new %in% c(
      "Jamaica","Haiti","Dominican Republic","Curacao","Guadeloupe",
      "Martinique","Bermuda","St. Kitts & Nevis","Grenada",
      "Antigua and Barbuda","Guyana","Suriname"
    ) ~ "Caribbean",
    
    # South America
    nationality_new %in% c(
      "Brazil","Argentina","Chile","Uruguay","Colombia","Peru",
      "Ecuador","Paraguay","Bolivia","Venezuela"
    ) ~ "South America",
    
    # Middle East
    nationality_new %in% c(
      "Saudi Arabia","Iran","Iraq","Israel","Jordan","Syria",
      "Palestine","Palästina","Bahrain"
    ) ~ "Middle East",
    
    # Asia
    nationality_new %in% c(
      "Japan","Korea, South","China","Vietnam","Indonesia",
      "Bangladesh","Uzbekistan","Tajikistan","Philippines"
    ) ~ "Asia",
    
    # Africa
    nationality_new %in% c(
      "Nigeria","Senegal","Ghana","Cameroon","DR Congo","Congo",
      "Morocco","Algeria","Tunisia","Egypt","South Africa",
      "Kenya","Tanzania","Zimbabwe","Zambia","Rwanda","Burundi",
      "Niger","Chad","Gabon","Benin","Togo","Liberia",
      "Sierra Leone","Central African Republic","Equatorial Guinea",
      "Guinea","Guinea-Bissau","Mali","Mauritania",
      "Namibia","Madagascar","Mozambique","Burkina Faso","Burkina",
      "Cote d'Ivoire","Cape Verde","Comoros","The Gambia"
    ) ~ "Africa",
    
    # Oceania
    nationality_new %in% c(
      "Australia","New Zealand"
    ) ~ "Oceania",
    
    TRUE ~ "Other"
  ))

# define EU player
panel <- panel %>%
  mutate(
    EU_player = if_else(country_region %in% c("Northern Europe", "Western Europe", "Southern Europe", "Eastern Europe"), 1, 0)
  )
table(panel$EU_player)


results <- list()

for (reg in unique(panel$country_region)) {
  
  df <- panel %>% filter(country_region == reg)
  
  model <- feols(
    Goals ~ Bosman + Age + Age*Bosman + Age^2 | player_id + Date_scraped,
    data = df,
    cluster = ~player_id
  )
  
  results[[reg]] <- model
}

results


results_df <- map_dfr(names(results), function(reg) {
  
  model <- results[[reg]]
  
  tidy_model <- broom::tidy(model)
  
  bosman_row <- tidy_model %>%
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
      p_value < 0.01  ~ "**",
      p_value < 0.05  ~ "*",
      p_value < 0.1   ~ ".",
      TRUE ~ ""
    ),
    estimate_pretty = paste0(round(estimate, 2), significance),
    std_error = round(std_error, 2),
    p_value = round(p_value, 4)
  ) %>%
  arrange(desc(estimate))

results_df



# Descriptives 


# mean age in Bosman
mean(panel$Age[panel$Bosman == TRUE], na.rm = TRUE)
# mean age in non-Bosman
mean(panel$Age[panel$Bosman == FALSE], na.rm = TRUE)

# age distribution in Bosman
ggplot(panel, aes(x = Age, fill = Bosman)) +
  geom_histogram(position = "dodge", bins = 30) +
  labs(
    x = "Age",
    y = "Count",
    title = "Age Distribution by Bosman Status"
  ) +
  theme_minimal()

# mean minutes in Bosman
mean(panel$Minutes[panel$Bosman == TRUE], na.rm = TRUE)
# mean minutes in non-Bosman
mean(panel$Minutes[panel$Bosman == FALSE], na.rm = TRUE)

# mean EU Player in Bosman
mean(panel$EU_player[panel$Bosman == TRUE], na.rm = TRUE)
# mean EU Player in non-Bosman
mean(panel$EU_player[panel$Bosman == FALSE], na.rm = TRUE)


# different apporh

panel <- panel %>%
  mutate(
    months_to_expiry = round(DaysToExpiry / 30)
  )

panel <- panel %>%
  mutate(
    months_to_expiry = pmax(pmin(months_to_expiry, 24), -6)
  )


model_event <- feols(
  Goals_per90 ~ i(ExpiryBin, ref = "2-4y") | player_id + Date_scraped,
  data = panel,
  cluster = ~player_id
)
summary(model_event)

iplot(model_event)



# create a new position variable, whih strips everything after the first word
panel <- panel %>%
  mutate(
    GenPosition = word(PlayerPosition, 1)
  )
table(panel$GenPosition)

# make attack "Attack", and midfield "Midfield"

panel <- panel %>%
  mutate(
    GenPosition = case_when(
      GenPosition %in% c("attack", "Attacker", "Forward") ~ "Attack",
      GenPosition %in% c("midfield", "Midfielder") ~ "Midfield",
      GenPosition %in% c("Defender", "Defense") ~ "Defense",
      GenPosition %in% c("Goalkeeper", "Keeper") ~ "Goalkeeper",
      TRUE ~ GenPosition
    )
  )
table(panel$GenPosition)

model_position <- panel %>%
  filter(GenPosition == "Attack") %>%
  feols(
    Goals ~ Bosman | player_id + Date_scraped,
    cluster = ~player_id
  )
summary(model_position)

model_midfield <- panel %>%
  filter(GenPosition == "Midfield") %>%
  feols(
    Goals ~ Bosman | player_id + Date_scraped,
    cluster = ~player_id
  )
summary(model_midfield)

model_defender <- panel %>%
  filter(GenPosition == "Defense") %>%
  feols(
    Goals ~ Bosman | player_id + Date_scraped,
    cluster = ~player_id
  )
summary(model_defender)

model_goalkeeper <- panel %>%
  filter(GenPosition == "Goalkeeper") %>%
  feols(
    Goals ~ Bosman | player_id + Date_scraped,
    cluster = ~player_id
  )
summary(model_goalkeeper)


# density plot of age in panel
ggplot(panel, aes(x = Age)) +
  geom_density(fill = "steelblue", alpha = 0.5) +
  labs(
    x = "Age",
    y = "Density",
    title = "Density of Player Age in Panel"
  ) +
  theme_minimal()


ggplot(panel, aes(x = Age)) +
  geom_density(
    kernel = "gaussian",
    fill = "steelblue",
    alpha = 0.5,
    adjust = 2
  ) +
  labs(
    x = "Age",
    y = "Density",
    title = "Density of Player Age in Panel"
  ) +
  theme_minimal()

ggplot(panel, aes(x = Age, fill = Bosman)) +
  geom_density(
    kernel = "gaussian",
    alpha = 0.4,
    adjust = 2
  ) +
  labs(
    x = "Age",
    y = "Density",
    title = "Density of Player Age: Bosman vs Non-Bosman",
    fill = "Bosman status"
  ) +
  theme_minimal()

ggplot(panel, aes(x = Age, fill = Bosman, colour = Bosman)) +
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


panel$Bosman <- factor(panel$Bosman,
                       levels = c(FALSE, TRUE),
                       labels = c("Not Bosman", "Bosman"))




