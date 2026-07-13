# FotMob Descriptive Analysis

This folder contains descriptive statistics and plots for two FotMob layers: the monthly panel variables used in the regression analysis, and the underlying match-level ratings from `data/master/fotmob_master_match_ratings.csv`.

- `fotmob_mean_rating`
- `fotmob_minutes_weighted_rating`
- match-level `rating`

The core summaries and plots use valid positive rating values only. Rows with `0` ratings are kept in the coverage tables because they are useful for diagnosing data availability, bench rows, and no-rating observations, but they are not treated as normal FotMob rating observations in the distribution plots.

## Monthly panel numeric summary

- `all_comps_strict` / `fotmob_mean_rating`: n = 136628, players = 7259, mean = 6.45, median = 6.73, sd = 1.27, variance = 1.60, p10-p90 = 5.03-7.53
- `all_comps_strict` / `fotmob_minutes_weighted_rating`: n = 136624, players = 7259, mean = 6.78, median = 6.85, sd = 0.79, variance = 0.62, p10-p90 = 6.02-7.60
- `source_league_strict` / `fotmob_mean_rating`: n = 132965, players = 7101, mean = 6.60, median = 6.79, sd = 1.10, variance = 1.21, p10-p90 = 5.80-7.55
- `source_league_strict` / `fotmob_minutes_weighted_rating`: n = 132961, players = 7101, mean = 6.85, median = 6.87, sd = 0.63, variance = 0.40, p10-p90 = 6.10-7.61

## Monthly panel coverage and zero-rating rows

- `all_comps_strict` / `fotmob_mean_rating`: positive rows = 136628 (97.3%), zero rows = 3834, missing rows = 0
- `all_comps_strict` / `fotmob_minutes_weighted_rating`: positive rows = 136624 (97.3%), zero rows = 3834, missing rows = 4
- `source_league_strict` / `fotmob_mean_rating`: positive rows = 132965 (98.0%), zero rows = 2762, missing rows = 0
- `source_league_strict` / `fotmob_minutes_weighted_rating`: positive rows = 132961 (98.0%), zero rows = 2762, missing rows = 4

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
