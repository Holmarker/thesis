library(dplyr)
library(ggplot2)
library(openxlsx)
library(readr)
library(tidyr)
library(lubridate)

parse_mixed_date <- function(x) {
  x_chr <- trimws(as.character(x))
  x_chr[x_chr %in% c("", "-", "NA", "NaN")] <- NA_character_
  d1 <- suppressWarnings(dmy(x_chr))
  d2 <- suppressWarnings(ymd(x_chr))
  d3 <- suppressWarnings(mdy(x_chr))
  coalesce(d1, d2, d3)
}

load_latest_playerbios <- function(path) {
  read.xlsx(path) %>%
    transmute(
      player_id = as.integer(player_id),
      Date_scraped = as.Date(Date_scraped, origin = "1899-12-30"),
      OnLoanFrom = na_if(as.character(OnLoanFrom), ""),
      ContractExpiryDate = parse_mixed_date(ContractExpiryDate),
      ContractThereExpires = parse_mixed_date(ContractThereExpires)
    ) %>%
    filter(!is.na(player_id), !is.na(Date_scraped)) %>%
    arrange(player_id, desc(Date_scraped)) %>%
    group_by(player_id) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(
      contract_date_used = if_else(!is.na(OnLoanFrom), ContractThereExpires, ContractExpiryDate),
      contract_type = if_else(!is.na(OnLoanFrom), "loan", "permanent"),
      DaysToExpiry = as.numeric(contract_date_used - Date_scraped)
    ) %>%
    filter(!is.na(contract_date_used), !is.na(DaysToExpiry), DaysToExpiry >= 0)
}

make_distribution <- function(df, sample_name) {
  df %>%
    mutate(years_remaining = pmin(floor(DaysToExpiry / 365.25), 6L)) %>%
    count(years_remaining) %>%
    complete(years_remaining = 0:6, fill = list(n = 0)) %>%
    mutate(
      sample_name = sample_name,
      pct = 100 * n / sum(n)
    ) %>%
    select(sample_name, years_remaining, n, pct)
}

make_contract_type_summary <- function(df, sample_name) {
  df %>%
    count(contract_type) %>%
    mutate(
      sample_name = sample_name,
      pct = 100 * n / sum(n)
    ) %>%
    select(sample_name, contract_type, n, pct)
}

make_plot <- function(dist_df, sample_name) {
  ggplot(dist_df, aes(x = factor(years_remaining), y = pct)) +
    geom_col(fill = "black", width = 0.72) +
    labs(
      title = paste0(sample_name, ": current contract years remaining"),
      subtitle = "Uses latest playerbios snapshot; loan players use ContractThereExpires",
      x = "Number of Years Remaining",
      y = "Percentage"
    ) +
    coord_cartesian(ylim = c(0, max(dist_df$pct) * 1.08)) +
    theme_minimal(base_size = 14) +
    theme(
      panel.background = element_rect(fill = "white", color = "#bfbfbf", linewidth = 0.8),
      plot.background = element_rect(fill = "white", color = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = "#d9d9d9", linewidth = 0.5),
      plot.title = element_text(hjust = 0.5, size = 18),
      plot.subtitle = element_text(hjust = 0.5, size = 11),
      axis.title = element_text(size = 14),
      axis.text = element_text(size = 12, color = "#333333")
    )
}

bios_path <- "/Users/magnu/Off The Pitch Dropbox/Off The Pitch/Player Asset Database/Data_Overview/Spiller data.xlsx"
results_dir <- "RSpeciale/results/fotmob_regressions"

dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

latest <- load_latest_playerbios(bios_path)
dist <- make_distribution(latest, "playerbios")
contract_type_summary <- make_contract_type_summary(latest, "playerbios")

write_csv(dist, file.path(results_dir, "current_years_remaining_distribution.csv"))
write_csv(contract_type_summary, file.path(results_dir, "current_years_remaining_contract_type_summary.csv"))

p <- make_plot(dist, "playerbios")
ggsave(
  filename = file.path(results_dir, "current_years_remaining_distribution.png"),
  plot = p,
  width = 9,
  height = 6,
  dpi = 300
)

cat("usable_players", nrow(latest), "\n")
print(contract_type_summary)
print(dist)
