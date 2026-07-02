library(dplyr)
library(ggplot2)
library(readr)
library(tidyr)

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates) | dir.exists(candidates)]

  if (length(existing) > 0) {
    return(existing[[1]])
  }

  candidates[[1]]
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

source_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_source_league_strict.csv")
all_comps_panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
match_ratings_path <- resolve_path("data", "master", "fotmob_master_match_ratings.csv")
results_dir <- resolve_path("results", "fotmob_descriptives")
ensure_dir(results_dir)

load_panel <- function(path, sample_name) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      sample_name = sample_name,
      Month = as.Date(Month),
      ContractExpiryDate = as.Date(ContractExpiryDate),
      LastExtensionDate = as.Date(LastExtensionDate),
      player_id = as.integer(player_id),
      fotmob_player_id = as.integer(fotmob_player_id),
      Age = as.numeric(Age),
      DaysToExpiry = as.numeric(DaysToExpiry),
      GenPosition = if_else(is.na(GenPosition) | GenPosition == "", "Unknown", GenPosition),
      fotmob_source_league = if_else(
        is.na(fotmob_source_league) | fotmob_source_league == "",
        "Unknown",
        fotmob_source_league
      )
    )
}

make_expiry_bin_6m <- function(days_to_expiry) {
  months_to_expiry <- days_to_expiry / 30.44

  cut(
    months_to_expiry,
    breaks = c(0, 6, 12, 18, 24, 30, 36, 48, Inf),
    right = FALSE,
    include.lowest = TRUE,
    labels = c("0:6", "6:12", "12:18", "18:24", "24:30", "30:36", "36:48", "48+")
  )
}

rating_vars <- c("fotmob_mean_rating", "fotmob_minutes_weighted_rating")

panel <- bind_rows(
  load_panel(source_panel_path, "source_league_strict"),
  load_panel(all_comps_panel_path, "all_comps_strict")
) %>%
  mutate(expiry_bin_6m = make_expiry_bin_6m(DaysToExpiry))

ratings_long <- panel %>%
  select(
    sample_name,
    player_id,
    fotmob_player_id,
    Month,
    Age,
    GenPosition,
    fotmob_source_league,
    expiry_bin_6m,
    fotmob_minutes,
    all_of(rating_vars)
  ) %>%
  pivot_longer(
    cols = all_of(rating_vars),
    names_to = "rating_variable",
    values_to = "rating_value"
  ) %>%
  mutate(
    has_positive_rating = !is.na(rating_value) & rating_value > 0,
    rating_variable_label = recode(
      rating_variable,
      fotmob_mean_rating = "Mean rating",
      fotmob_minutes_weighted_rating = "Minutes-weighted rating"
    )
  )

coverage_summary <- ratings_long %>%
  group_by(sample_name, rating_variable) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(player_id),
    missing_rows = sum(is.na(rating_value)),
    zero_rows = sum(rating_value == 0, na.rm = TRUE),
    positive_rows = sum(has_positive_rating),
    positive_players = n_distinct(player_id[has_positive_rating]),
    positive_share = positive_rows / n_rows,
    .groups = "drop"
  )

numeric_summary <- ratings_long %>%
  filter(has_positive_rating) %>%
  group_by(sample_name, rating_variable) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(player_id),
    mean = mean(rating_value),
    median = median(rating_value),
    variance = var(rating_value),
    sd = sd(rating_value),
    min = min(rating_value),
    p10 = quantile(rating_value, 0.10),
    p25 = quantile(rating_value, 0.25),
    p75 = quantile(rating_value, 0.75),
    p90 = quantile(rating_value, 0.90),
    max = max(rating_value),
    mean_minutes = mean(fotmob_minutes, na.rm = TRUE),
    .groups = "drop"
  )

position_summary <- ratings_long %>%
  filter(has_positive_rating) %>%
  group_by(sample_name, rating_variable, GenPosition) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(player_id),
    mean = mean(rating_value),
    median = median(rating_value),
    variance = var(rating_value),
    sd = sd(rating_value),
    .groups = "drop"
  ) %>%
  arrange(sample_name, rating_variable, desc(n_rows))

expiry_summary <- ratings_long %>%
  filter(has_positive_rating, !is.na(expiry_bin_6m)) %>%
  group_by(sample_name, rating_variable, expiry_bin_6m) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(player_id),
    mean = mean(rating_value),
    median = median(rating_value),
    variance = var(rating_value),
    sd = sd(rating_value),
    .groups = "drop"
  )

monthly_summary <- ratings_long %>%
  filter(has_positive_rating) %>%
  group_by(sample_name, rating_variable, Month) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(player_id),
    mean = mean(rating_value),
    median = median(rating_value),
    sd = sd(rating_value),
    .groups = "drop"
  )

top_league_summary <- ratings_long %>%
  filter(has_positive_rating, fotmob_source_league != "Unknown") %>%
  group_by(sample_name, rating_variable, fotmob_source_league) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(player_id),
    mean = mean(rating_value),
    median = median(rating_value),
    sd = sd(rating_value),
    .groups = "drop"
  ) %>%
  group_by(sample_name, rating_variable) %>%
  slice_max(n_rows, n = 20, with_ties = FALSE) %>%
  ungroup()

match_ratings_raw <- read_csv(match_ratings_path, show_col_types = FALSE) %>%
  mutate(
    match_date = as.Date(match_date),
    Month = as.Date(Month),
    tm_player_id = as.integer(tm_player_id),
    fotmob_player_id = as.integer(fotmob_player_id),
    match_id = as.integer(match_id),
    rating = as.numeric(rating),
    minutes_played = as.numeric(minutes_played),
    fotmob_position_group = if_else(
      is.na(fotmob_position_group) | fotmob_position_group == "",
      "Unknown",
      fotmob_position_group
    ),
    source_league_name = if_else(
      is.na(source_league_name) | source_league_name == "",
      "Unknown",
      source_league_name
    ),
    competition_league_name = if_else(
      is.na(competition_league_name) | competition_league_name == "",
      "Unknown",
      competition_league_name
    )
  )

match_ratings <- bind_rows(
  match_ratings_raw %>%
    mutate(sample_name = "match_level_all_comps"),
  match_ratings_raw %>%
    filter(is_source_league_match) %>%
    mutate(sample_name = "match_level_source_league")
) %>%
  mutate(
    has_positive_rating = !is.na(rating) & rating > 0 & has_valid_rating,
    minutes_bin = cut(
      minutes_played,
      breaks = c(-Inf, 0, 15, 30, 45, 60, 75, 90, Inf),
      labels = c("0", "1:15", "16:30", "31:45", "46:60", "61:75", "76:90", "90+")
    )
  )

match_coverage_summary <- match_ratings %>%
  group_by(sample_name) %>%
  summarise(
    n_rows = n(),
    n_tm_players = n_distinct(tm_player_id),
    n_fotmob_players = n_distinct(fotmob_player_id),
    n_matches = n_distinct(match_id),
    missing_rows = sum(is.na(rating)),
    zero_rows = sum(rating == 0, na.rm = TRUE),
    invalid_rating_rows = sum(!has_valid_rating, na.rm = TRUE),
    positive_rows = sum(has_positive_rating),
    positive_players = n_distinct(fotmob_player_id[has_positive_rating]),
    positive_share = positive_rows / n_rows,
    min_match_date = min(match_date, na.rm = TRUE),
    max_match_date = max(match_date, na.rm = TRUE),
    .groups = "drop"
  )

match_numeric_summary <- match_ratings %>%
  filter(has_positive_rating) %>%
  group_by(sample_name) %>%
  summarise(
    n_rows = n(),
    n_tm_players = n_distinct(tm_player_id),
    n_fotmob_players = n_distinct(fotmob_player_id),
    n_matches = n_distinct(match_id),
    mean = mean(rating),
    median = median(rating),
    variance = var(rating),
    sd = sd(rating),
    min = min(rating),
    p10 = quantile(rating, 0.10),
    p25 = quantile(rating, 0.25),
    p75 = quantile(rating, 0.75),
    p90 = quantile(rating, 0.90),
    max = max(rating),
    mean_minutes = mean(minutes_played, na.rm = TRUE),
    .groups = "drop"
  )

match_transformed_ratings <- match_ratings %>%
  filter(has_positive_rating) %>%
  group_by(sample_name) %>%
  mutate(
    rating_z = as.numeric(scale(rating)),
    rating_log = log(rating)
  ) %>%
  ungroup()

match_transformed_summary <- match_transformed_ratings %>%
  pivot_longer(
    cols = c(rating_z, rating_log),
    names_to = "transformation",
    values_to = "value"
  ) %>%
  mutate(
    transformation = recode(
      transformation,
      rating_z = "standardized_within_sample",
      rating_log = "log_rating"
    )
  ) %>%
  group_by(sample_name, transformation) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(fotmob_player_id),
    n_matches = n_distinct(match_id),
    mean = mean(value),
    median = median(value),
    variance = var(value),
    sd = sd(value),
    min = min(value),
    p10 = quantile(value, 0.10),
    p25 = quantile(value, 0.25),
    p75 = quantile(value, 0.75),
    p90 = quantile(value, 0.90),
    max = max(value),
    .groups = "drop"
  )

match_position_summary <- match_ratings %>%
  filter(has_positive_rating) %>%
  group_by(sample_name, fotmob_position_group) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(fotmob_player_id),
    mean = mean(rating),
    median = median(rating),
    variance = var(rating),
    sd = sd(rating),
    .groups = "drop"
  ) %>%
  arrange(sample_name, desc(n_rows))

match_minutes_summary <- match_ratings %>%
  filter(has_positive_rating, !is.na(minutes_bin)) %>%
  group_by(sample_name, minutes_bin) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(fotmob_player_id),
    mean = mean(rating),
    median = median(rating),
    variance = var(rating),
    sd = sd(rating),
    .groups = "drop"
  )

match_monthly_summary <- match_ratings %>%
  filter(has_positive_rating) %>%
  group_by(sample_name, Month) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(fotmob_player_id),
    n_matches = n_distinct(match_id),
    mean = mean(rating),
    median = median(rating),
    sd = sd(rating),
    .groups = "drop"
  )

match_competition_summary <- match_ratings %>%
  filter(has_positive_rating, competition_league_name != "Unknown") %>%
  group_by(sample_name, competition_league_name) %>%
  summarise(
    n_rows = n(),
    n_players = n_distinct(fotmob_player_id),
    n_matches = n_distinct(match_id),
    mean = mean(rating),
    median = median(rating),
    sd = sd(rating),
    .groups = "drop"
  ) %>%
  group_by(sample_name) %>%
  slice_max(n_rows, n = 20, with_ties = FALSE) %>%
  ungroup()

write_csv(coverage_summary, file.path(results_dir, "fotmob_rating_coverage_summary.csv"), na = "")
write_csv(numeric_summary, file.path(results_dir, "fotmob_rating_numeric_summary.csv"), na = "")
write_csv(position_summary, file.path(results_dir, "fotmob_rating_by_position_summary.csv"), na = "")
write_csv(expiry_summary, file.path(results_dir, "fotmob_rating_by_expiry_bin_summary.csv"), na = "")
write_csv(monthly_summary, file.path(results_dir, "fotmob_rating_by_month_summary.csv"), na = "")
write_csv(top_league_summary, file.path(results_dir, "fotmob_rating_by_top_league_summary.csv"), na = "")
write_csv(match_coverage_summary, file.path(results_dir, "fotmob_match_rating_coverage_summary.csv"), na = "")
write_csv(match_numeric_summary, file.path(results_dir, "fotmob_match_rating_numeric_summary.csv"), na = "")
write_csv(match_transformed_summary, file.path(results_dir, "fotmob_match_rating_transformed_summary.csv"), na = "")
write_csv(match_position_summary, file.path(results_dir, "fotmob_match_rating_by_position_summary.csv"), na = "")
write_csv(match_minutes_summary, file.path(results_dir, "fotmob_match_rating_by_minutes_summary.csv"), na = "")
write_csv(match_monthly_summary, file.path(results_dir, "fotmob_match_rating_by_month_summary.csv"), na = "")
write_csv(match_competition_summary, file.path(results_dir, "fotmob_match_rating_by_competition_summary.csv"), na = "")

plot_theme <- theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    plot.title.position = "plot",
    legend.position = "bottom"
  )

positive_ratings <- ratings_long %>%
  filter(has_positive_rating)

distribution_plot <- ggplot(positive_ratings, aes(x = rating_value, fill = sample_name)) +
  geom_histogram(binwidth = 0.1, alpha = 0.65, position = "identity", boundary = 0) +
  facet_wrap(~rating_variable_label, ncol = 1, scales = "free_y") +
  labs(
    title = "Distribution of positive FotMob ratings",
    x = "FotMob rating",
    y = "Rows",
    fill = "Sample"
  ) +
  plot_theme

density_plot <- ggplot(positive_ratings, aes(x = rating_value, color = sample_name, fill = sample_name)) +
  geom_density(alpha = 0.16, linewidth = 0.9) +
  facet_wrap(~rating_variable_label, ncol = 1) +
  labs(
    title = "Density of positive FotMob ratings",
    x = "FotMob rating",
    y = "Density",
    color = "Sample",
    fill = "Sample"
  ) +
  plot_theme

position_plot <- positive_ratings %>%
  filter(GenPosition != "Unknown") %>%
  ggplot(aes(x = reorder(GenPosition, rating_value, median), y = rating_value, fill = GenPosition)) +
  geom_boxplot(outlier.alpha = 0.15, width = 0.7) +
  coord_flip() +
  facet_grid(rating_variable_label ~ sample_name) +
  labs(
    title = "FotMob rating distribution by position",
    x = "Position",
    y = "FotMob rating"
  ) +
  guides(fill = "none") +
  plot_theme

monthly_plot <- ggplot(monthly_summary, aes(x = Month, y = mean, color = sample_name)) +
  geom_line(linewidth = 0.9) +
  geom_point(aes(size = n_rows), alpha = 0.6) +
  facet_wrap(~rating_variable, ncol = 1, scales = "free_y") +
  labs(
    title = "Average FotMob rating by month",
    x = "Month",
    y = "Average rating",
    color = "Sample",
    size = "Rows"
  ) +
  plot_theme

expiry_plot <- ggplot(expiry_summary, aes(x = expiry_bin_6m, y = mean, color = sample_name, group = sample_name)) +
  geom_line(linewidth = 0.9) +
  geom_point(aes(size = n_rows), alpha = 0.8) +
  facet_wrap(~rating_variable, ncol = 1, scales = "free_y") +
  labs(
    title = "Average FotMob rating by months to contract expiry",
    x = "Months to expiry",
    y = "Average rating",
    color = "Sample",
    size = "Rows"
  ) +
  plot_theme

minutes_plot <- positive_ratings %>%
  filter(!is.na(fotmob_minutes), fotmob_minutes > 0) %>%
  ggplot(aes(x = fotmob_minutes, y = rating_value, color = sample_name)) +
  geom_point(alpha = 0.18, size = 1) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, linewidth = 0.9) +
  facet_wrap(~rating_variable_label, ncol = 1, scales = "free_y") +
  labs(
    title = "FotMob rating against monthly FotMob minutes",
    x = "Monthly FotMob minutes",
    y = "FotMob rating",
    color = "Sample"
  ) +
  plot_theme

positive_match_ratings <- match_transformed_ratings

match_distribution_plot <- ggplot(positive_match_ratings, aes(x = rating, fill = sample_name)) +
  geom_histogram(binwidth = 0.1, alpha = 0.65, position = "identity", boundary = 0) +
  labs(
    title = "Distribution of positive match-level FotMob ratings",
    x = "Match rating",
    y = "Player-match rows",
    fill = "Sample"
  ) +
  plot_theme

match_density_plot <- ggplot(positive_match_ratings, aes(x = rating, color = sample_name, fill = sample_name)) +
  geom_density(alpha = 0.16, linewidth = 0.9) +
  labs(
    title = "Density of positive match-level FotMob ratings",
    x = "Match rating",
    y = "Density",
    color = "Sample",
    fill = "Sample"
  ) +
  plot_theme

match_standardized_density_plot <- ggplot(positive_match_ratings, aes(x = rating_z, color = sample_name, fill = sample_name)) +
  geom_density(alpha = 0.16, linewidth = 0.9) +
  geom_vline(xintercept = 0, linewidth = 0.4, linetype = "dashed", color = "grey35") +
  labs(
    title = "Density of standardized match-level FotMob ratings",
    subtitle = "Ratings are z-scored within each sample",
    x = "Standardized match rating",
    y = "Density",
    color = "Sample",
    fill = "Sample"
  ) +
  plot_theme

match_log_density_plot <- ggplot(positive_match_ratings, aes(x = rating_log, color = sample_name, fill = sample_name)) +
  geom_density(alpha = 0.16, linewidth = 0.9) +
  labs(
    title = "Density of log match-level FotMob ratings",
    x = "log(match rating)",
    y = "Density",
    color = "Sample",
    fill = "Sample"
  ) +
  plot_theme

match_transform_comparison_plot <- positive_match_ratings %>%
  select(sample_name, rating, rating_z, rating_log) %>%
  pivot_longer(
    cols = c(rating, rating_z, rating_log),
    names_to = "scale",
    values_to = "value"
  ) %>%
  mutate(
    scale = recode(
      scale,
      rating = "Raw rating",
      rating_z = "Standardized rating",
      rating_log = "Log rating"
    )
  ) %>%
  ggplot(aes(x = value, color = sample_name, fill = sample_name)) +
  geom_density(alpha = 0.16, linewidth = 0.9) +
  facet_wrap(~scale, scales = "free", ncol = 1) +
  labs(
    title = "Match-level FotMob rating distributions under different transformations",
    x = NULL,
    y = "Density",
    color = "Sample",
    fill = "Sample"
  ) +
  plot_theme

match_position_plot <- positive_match_ratings %>%
  filter(fotmob_position_group != "Unknown") %>%
  ggplot(aes(x = reorder(fotmob_position_group, rating, median), y = rating, fill = fotmob_position_group)) +
  geom_boxplot(outlier.alpha = 0.08, width = 0.7) +
  coord_flip() +
  facet_wrap(~sample_name) +
  labs(
    title = "Match-level FotMob ratings by position group",
    x = "Position group",
    y = "Match rating"
  ) +
  guides(fill = "none") +
  plot_theme

match_monthly_plot <- ggplot(match_monthly_summary, aes(x = Month, y = mean, color = sample_name)) +
  geom_line(linewidth = 0.9) +
  geom_point(aes(size = n_rows), alpha = 0.6) +
  labs(
    title = "Average match-level FotMob rating by month",
    x = "Month",
    y = "Average match rating",
    color = "Sample",
    size = "Rows"
  ) +
  plot_theme

match_minutes_plot <- ggplot(match_minutes_summary, aes(x = minutes_bin, y = mean, color = sample_name, group = sample_name)) +
  geom_line(linewidth = 0.9) +
  geom_point(aes(size = n_rows), alpha = 0.8) +
  labs(
    title = "Average match-level FotMob rating by minutes played",
    x = "Minutes played bin",
    y = "Average match rating",
    color = "Sample",
    size = "Rows"
  ) +
  plot_theme

match_competition_plot <- match_competition_summary %>%
  mutate(competition_label = reorder(competition_league_name, mean)) %>%
  ggplot(aes(x = competition_label, y = mean, fill = sample_name)) +
  geom_col(position = "dodge") +
  coord_flip() +
  facet_wrap(~sample_name, scales = "free_y") +
  labs(
    title = "Average match-level FotMob rating in the largest competitions",
    x = "Competition",
    y = "Average match rating",
    fill = "Sample"
  ) +
  plot_theme

ggsave(file.path(results_dir, "fotmob_rating_distribution_histogram.png"), distribution_plot, width = 9, height = 8, dpi = 300)
ggsave(file.path(results_dir, "fotmob_rating_distribution_density.png"), density_plot, width = 9, height = 8, dpi = 300)
ggsave(file.path(results_dir, "fotmob_rating_by_position_boxplot.png"), position_plot, width = 10, height = 7, dpi = 300)
ggsave(file.path(results_dir, "fotmob_rating_by_month.png"), monthly_plot, width = 10, height = 7, dpi = 300)
ggsave(file.path(results_dir, "fotmob_rating_by_expiry_bin.png"), expiry_plot, width = 10, height = 7, dpi = 300)
ggsave(file.path(results_dir, "fotmob_rating_vs_minutes.png"), minutes_plot, width = 9, height = 8, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_distribution_histogram.png"), match_distribution_plot, width = 9, height = 6, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_distribution_density.png"), match_density_plot, width = 9, height = 6, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_standardized_density.png"), match_standardized_density_plot, width = 9, height = 6, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_log_density.png"), match_log_density_plot, width = 9, height = 6, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_transform_comparison.png"), match_transform_comparison_plot, width = 9, height = 9, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_by_position_boxplot.png"), match_position_plot, width = 10, height = 6, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_by_month.png"), match_monthly_plot, width = 10, height = 6, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_by_minutes_bin.png"), match_minutes_plot, width = 9, height = 6, dpi = 300)
ggsave(file.path(results_dir, "fotmob_match_rating_by_competition.png"), match_competition_plot, width = 10, height = 8, dpi = 300)

fmt <- function(x, digits = 2) {
  format(round(x, digits), nsmall = digits, trim = TRUE)
}

mean_rows <- numeric_summary %>%
  mutate(
    line = paste0(
      "- `", sample_name, "` / `", rating_variable, "`: n = ", n_rows,
      ", players = ", n_players,
      ", mean = ", fmt(mean),
      ", median = ", fmt(median),
      ", sd = ", fmt(sd),
      ", variance = ", fmt(variance),
      ", p10-p90 = ", fmt(p10), "-", fmt(p90)
    )
  ) %>%
  pull(line)

coverage_rows <- coverage_summary %>%
  mutate(
    line = paste0(
      "- `", sample_name, "` / `", rating_variable, "`: positive rows = ",
      positive_rows, " (", fmt(100 * positive_share, 1), "%), zero rows = ", zero_rows,
      ", missing rows = ", missing_rows
    )
  ) %>%
  pull(line)

match_mean_rows <- match_numeric_summary %>%
  mutate(
    line = paste0(
      "- `", sample_name, "`: n = ", n_rows,
      ", players = ", n_fotmob_players,
      ", matches = ", n_matches,
      ", mean = ", fmt(mean),
      ", median = ", fmt(median),
      ", sd = ", fmt(sd),
      ", variance = ", fmt(variance),
      ", p10-p90 = ", fmt(p10), "-", fmt(p90)
    )
  ) %>%
  pull(line)

match_coverage_rows <- match_coverage_summary %>%
  mutate(
    line = paste0(
      "- `", sample_name, "`: positive rows = ", positive_rows,
      " (", fmt(100 * positive_share, 1), "%), zero rows = ", zero_rows,
      ", invalid-rating rows = ", invalid_rating_rows,
      ", date range = ", min_match_date, " to ", max_match_date
    )
  ) %>%
  pull(line)

match_transformed_rows <- match_transformed_summary %>%
  mutate(
    line = paste0(
      "- `", sample_name, "` / `", transformation, "`: mean = ", fmt(mean),
      ", median = ", fmt(median),
      ", sd = ", fmt(sd),
      ", variance = ", fmt(variance),
      ", p10-p90 = ", fmt(p10), "-", fmt(p90)
    )
  ) %>%
  pull(line)

summary_lines <- c(
  "# FotMob Descriptive Analysis",
  "",
  "This folder contains descriptive statistics and plots for two FotMob layers: the monthly panel variables used in the regression analysis, and the underlying match-level ratings from `data/master/fotmob_master_match_ratings.csv`.",
  "",
  "- `fotmob_mean_rating`",
  "- `fotmob_minutes_weighted_rating`",
  "- match-level `rating`",
  "",
  "The core summaries and plots use valid positive rating values only. Rows with `0` ratings are kept in the coverage tables because they are useful for diagnosing data availability, bench rows, and no-rating observations, but they are not treated as normal FotMob rating observations in the distribution plots.",
  "",
  "## Monthly panel numeric summary",
  "",
  mean_rows,
  "",
  "## Monthly panel coverage and zero-rating rows",
  "",
  coverage_rows,
  "",
  "## Match-level numeric summary",
  "",
  match_mean_rows,
  "",
  "## Match-level coverage and zero-rating rows",
  "",
  match_coverage_rows,
  "",
  "## Match-level transformed summary",
  "",
  match_transformed_rows,
  "",
  "## Output tables",
  "",
  "- `fotmob_rating_coverage_summary.csv`",
  "- `fotmob_rating_numeric_summary.csv`",
  "- `fotmob_rating_by_position_summary.csv`",
  "- `fotmob_rating_by_expiry_bin_summary.csv`",
  "- `fotmob_rating_by_month_summary.csv`",
  "- `fotmob_rating_by_top_league_summary.csv`",
  "- `fotmob_match_rating_coverage_summary.csv`",
  "- `fotmob_match_rating_numeric_summary.csv`",
  "- `fotmob_match_rating_transformed_summary.csv`",
  "- `fotmob_match_rating_by_position_summary.csv`",
  "- `fotmob_match_rating_by_minutes_summary.csv`",
  "- `fotmob_match_rating_by_month_summary.csv`",
  "- `fotmob_match_rating_by_competition_summary.csv`",
  "",
  "## Output plots",
  "",
  "- `fotmob_rating_distribution_histogram.png`",
  "- `fotmob_rating_distribution_density.png`",
  "- `fotmob_rating_by_position_boxplot.png`",
  "- `fotmob_rating_by_month.png`",
  "- `fotmob_rating_by_expiry_bin.png`",
  "- `fotmob_rating_vs_minutes.png`",
  "- `fotmob_match_rating_distribution_histogram.png`",
  "- `fotmob_match_rating_distribution_density.png`",
  "- `fotmob_match_rating_standardized_density.png`",
  "- `fotmob_match_rating_log_density.png`",
  "- `fotmob_match_rating_transform_comparison.png`",
  "- `fotmob_match_rating_by_position_boxplot.png`",
  "- `fotmob_match_rating_by_month.png`",
  "- `fotmob_match_rating_by_minutes_bin.png`",
  "- `fotmob_match_rating_by_competition.png`"
)

writeLines(summary_lines, file.path(results_dir, "SUMMARY.md"))

message("Saved FotMob descriptive outputs to: ", results_dir)
