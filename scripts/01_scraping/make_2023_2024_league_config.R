library(dplyr)
library(readr)

input_path <- "RSpeciale/league_config_resolved.csv"
output_path <- "RSpeciale/league_config_resolved_2023_2024_clean.csv"

league_config <- read_csv(input_path, show_col_types = FALSE) %>%
  mutate(
    season_start = as.Date(sprintf(
      "%04d-%02d-%02d",
      as.integer(format(as.Date(season_start), "%Y")) - 2L,
      as.integer(format(as.Date(season_start), "%m")),
      as.integer(format(as.Date(season_start), "%d"))
    )),
    season_end = as.Date(sprintf(
      "%04d-%02d-%02d",
      as.integer(format(as.Date(season_end), "%Y")) - 2L,
      as.integer(format(as.Date(season_end), "%m")),
      as.integer(format(as.Date(season_end), "%d"))
    ))
  )

write_csv(league_config, output_path, na = "")
message("Saved 2023/2024 league config to: ", output_path)
