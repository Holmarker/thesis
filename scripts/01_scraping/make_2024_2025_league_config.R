library(dplyr)
library(readr)

input_path <- "RSpeciale/league_config_resolved.csv"
output_path <- "RSpeciale/league_config_resolved_2024_2025.csv"

league_config <- read_csv(input_path, show_col_types = FALSE) %>%
  mutate(
    season_start = as.Date(season_start) - 365,
    season_end = as.Date(season_end) - 365
  )

write_csv(league_config, output_path, na = "")
message("Saved 2024/2025 league config to: ", output_path)
