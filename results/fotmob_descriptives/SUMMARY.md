# FotMob Descriptive Analysis

This folder contains descriptive statistics and plots for two FotMob layers: the monthly panel variables used in the regression analysis, and the underlying match-level ratings from `data/master/fotmob_master_match_ratings.csv`.

- `fotmob_mean_rating`
- `fotmob_minutes_weighted_rating`
- match-level `rating`

The core summaries and plots use valid positive rating values only. Rows with `0` ratings are kept in the coverage tables because they are useful for diagnosing data availability, bench rows, and no-rating observations, but they are not treated as normal FotMob rating observations in the distribution plots.

## Monthly panel numeric summary

- `all_comps_strict` / `fotmob_mean_rating`: n = 119955, players = 7202, mean = 6.39, median = 6.70, sd = 1.32, variance = 1.74, p10-p90 = 4.71-7.50
- `all_comps_strict` / `fotmob_minutes_weighted_rating`: n = 119952, players = 7202, mean = 6.76, median = 6.82, sd = 0.81, variance = 0.65, p10-p90 = 6.00-7.59
- `source_league_strict` / `fotmob_mean_rating`: n = 116292, players = 7033, mean = 6.55, median = 6.75, sd = 1.15, variance = 1.31, p10-p90 = 5.67-7.53
- `source_league_strict` / `fotmob_minutes_weighted_rating`: n = 116289, players = 7033, mean = 6.84, median = 6.85, sd = 0.63, variance = 0.40, p10-p90 = 6.10-7.60

## Monthly panel coverage and zero-rating rows

- `all_comps_strict` / `fotmob_mean_rating`: positive rows = 119955 (96.9%), zero rows = 3834, missing rows = 0
- `all_comps_strict` / `fotmob_minutes_weighted_rating`: positive rows = 119952 (96.9%), zero rows = 3834, missing rows = 3
- `source_league_strict` / `fotmob_mean_rating`: positive rows = 116292 (97.7%), zero rows = 2762, missing rows = 0
- `source_league_strict` / `fotmob_minutes_weighted_rating`: positive rows = 116289 (97.7%), zero rows = 2762, missing rows = 3

## Match-level numeric summary

- `match_level_all_comps`: n = 180170, players = 7474, matches = 14615, mean = 6.86, median = 6.80, sd = 0.80, variance = 0.64, p10-p90 = 6.00-7.90
- `match_level_source_league`: n = 131961, players = 6911, matches = 8931, mean = 6.86, median = 6.80, sd = 0.79, variance = 0.63, p10-p90 = 6.00-7.90

## Match-level coverage and zero-rating rows

- `match_level_all_comps`: positive rows = 180170 (65.4%), zero rows = 95293, invalid-rating rows = 95293, date range = 2025-03-09 to 2026-03-24
- `match_level_source_league`: positive rows = 131961 (69.6%), zero rows = 57683, invalid-rating rows = 57683, date range = 2025-03-22 to 2026-03-24

## Match-level transformed summary

- `match_level_all_comps` / `log_rating`: mean = 1.92, median = 1.92, sd = 0.12, variance = 0.01, p10-p90 = 1.79-2.07
- `match_level_all_comps` / `standardized_within_sample`: mean = 0.00, median = -0.08, sd = 1.00, variance = 1.00, p10-p90 = -1.08-1.29
- `match_level_source_league` / `log_rating`: mean = 1.92, median = 1.92, sd = 0.12, variance = 0.01, p10-p90 = 1.79-2.07
- `match_level_source_league` / `standardized_within_sample`: mean = 0.00, median = -0.07, sd = 1.00, variance = 1.00, p10-p90 = -1.08-1.31

## Output tables

- `fotmob_rating_coverage_summary.csv`
- `fotmob_rating_numeric_summary.csv`
- `fotmob_rating_by_position_summary.csv`
- `fotmob_rating_by_expiry_bin_summary.csv`
- `fotmob_rating_by_month_summary.csv`
- `fotmob_rating_by_top_league_summary.csv`
- `fotmob_match_rating_coverage_summary.csv`
- `fotmob_match_rating_numeric_summary.csv`
- `fotmob_match_rating_transformed_summary.csv`
- `fotmob_match_rating_by_position_summary.csv`
- `fotmob_match_rating_by_minutes_summary.csv`
- `fotmob_match_rating_by_month_summary.csv`
- `fotmob_match_rating_by_competition_summary.csv`

## Output plots

- `fotmob_rating_distribution_histogram.png`
- `fotmob_rating_distribution_density.png`
- `fotmob_rating_by_position_boxplot.png`
- `fotmob_rating_by_month.png`
- `fotmob_rating_by_expiry_bin.png`
- `fotmob_rating_vs_minutes.png`
- `fotmob_match_rating_distribution_histogram.png`
- `fotmob_match_rating_distribution_density.png`
- `fotmob_match_rating_standardized_density.png`
- `fotmob_match_rating_log_density.png`
- `fotmob_match_rating_transform_comparison.png`
- `fotmob_match_rating_by_position_boxplot.png`
- `fotmob_match_rating_by_month.png`
- `fotmob_match_rating_by_minutes_bin.png`
- `fotmob_match_rating_by_competition.png`
