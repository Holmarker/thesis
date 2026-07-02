# Thesis Descriptive Statistics

This folder contains the clean descriptive statistics section requested for the thesis. The main sample is `all_comps` from `data/panel/fotmob_analysis_panel_all_comps.csv`, so earlier contract-panel seasons are included.

Positive FotMob rating variables are used for rating means and plots. Zero ratings are treated as no-rating observations and set to missing in `fotmob_mean_rating_clean` and `fotmob_minutes_weighted_rating_clean`. Earlier seasons can contribute to contract timing, Bosman status, player, club, and Transfermarkt variables even when FotMob ratings are unavailable.

## Sample Overview

- Observations: 146485
- Players: 5695
- Clubs: 1448
- Seasons: 5
- First month: 2022-06-01
- Last month: 2026-03-01
- Bosman-window observations: 12727
- Non-Bosman observations: 133758

Season-level coverage is saved in `season_coverage.csv`.

## FotMob Rating Availability

The contract panel now covers older seasons, but FotMob rating coverage is not available for every historical season in the local files. Rating coverage by season is saved in `fotmob_rating_availability_by_season.csv`; the historical rating checkpoint audit is saved in `historical_rating_file_audit.csv`.

- `2021/2022`: observations = 19, positive mean-rating rows = 0 (0.0%)
- `2022/2023`: observations = 26395, positive mean-rating rows = 0 (0.0%)
- `2023/2024`: observations = 39938, positive mean-rating rows = 0 (0.0%)
- `2024/2025`: observations = 44668, positive mean-rating rows = 8058 (18.0%)
- `2025/2026`: observations = 35465, positive mean-rating rows = 26688 (75.3%)

The 2024/25 ratings from `data/historical/checkpoints/ratings` are also read directly and summarised in this folder:

- 2024/25 checkpoint ratings: observations = 86666, positive ratings = 51157, players = 11323, matches = 5456, date range = 2024-08-02 to 2025-05-31, mean rating = 6.87, panel-matched positive ratings = 25185

- `historical_2024_2025_checkpoint_rating_overview.csv`
- `historical_2024_2025_checkpoint_rating_by_month.csv`
- `historical_2024_2025_checkpoint_rating_by_league.csv`
- `historical_2024_2025_checkpoint_rating_histogram.png`

## Table 1

Full sample summary statistics are saved in `table1_full_sample_summary_statistics.csv`.

- `Age`: n = 146017, mean = 25.15, sd = 4.18, median = 25.00
- `Assists_per90_tm`: n = 109247, mean = 0.12, sd = 0.82, median = 0.00
- `Assists_tm`: n = 146485, mean = 0.20, sd = 0.54, median = 0.00
- `DaysToExpiry`: n = 146485, mean = 794.30, sd = 451.95, median = 759.00
- `Goals_per90_tm`: n = 109247, mean = 0.16, sd = 0.76, median = 0.00
- `Goals_tm`: n = 146485, mean = 0.27, sd = 0.71, median = 0.00
- `Minutes_tm`: n = 146485, mean = 169.95, sd = 163.35, median = 135.00
- `fotmob_assists`: n = 40492, mean = 0.21, sd = 0.54, median = 0.00
- `fotmob_goals`: n = 40492, mean = 0.32, sd = 0.76, median = 0.00
- `fotmob_matches`: n = 40492, mean = 3.96, sd = 1.83, median = 4.00
- `fotmob_mean_rating_clean`: n = 34746, mean = 5.48, sd = 1.86, median = 6.18
- `fotmob_minutes`: n = 40492, mean = 208.14, sd = 159.66, median = 180.00
- `fotmob_minutes_weighted_rating_clean`: n = 34746, mean = 6.53, sd = 1.11, median = 6.76

## Table 2

Comparison of means between player-months inside and outside the Bosman window is saved in `table2_bosman_window_mean_comparison_ttests.csv`.

- `DaysToExpiry`: Bosman mean = 115.31, outside mean = 858.91, diff = -743.59, p = <0.001
- `Age`: Bosman mean = 27.57, outside mean = 24.92, diff = 2.65, p = <0.001
- `Minutes_tm`: Bosman mean = 164.01, outside mean = 170.51, diff = -6.50, p = <0.001
- `Goals_tm`: Bosman mean = 0.23, outside mean = 0.27, diff = -0.04, p = <0.001
- `Assists_tm`: Bosman mean = 0.17, outside mean = 0.20, diff = -0.03, p = <0.001
- `Goals_per90_tm`: Bosman mean = 0.14, outside mean = 0.16, diff = -0.02, p = 0.142
- `Assists_per90_tm`: Bosman mean = 0.11, outside mean = 0.12, diff = -0.01, p = 0.443
- `fotmob_matches`: Bosman mean = 3.57, outside mean = 3.99, diff = -0.42, p = <0.001
- `fotmob_minutes`: Bosman mean = 188.39, outside mean = 209.95, diff = -21.56, p = <0.001
- `fotmob_goals`: Bosman mean = 0.26, outside mean = 0.33, diff = -0.07, p = <0.001
- `fotmob_assists`: Bosman mean = 0.18, outside mean = 0.22, diff = -0.04, p = <0.001
- `fotmob_mean_rating_clean`: Bosman mean = 5.63, outside mean = 5.47, diff = 0.16, p = <0.001
- `fotmob_minutes_weighted_rating_clean`: Bosman mean = 6.66, outside mean = 6.52, diff = 0.13, p = <0.001

## Table 3

Signing event summary statistics for the renewal analysis subsample are saved in `table3_renewal_signing_event_summary.csv`. The file `renewal_subsample_overview.csv` gives the overall renewal-sample counts.

## Figures

- `figure1_days_to_expiry_histogram.png`
- `figure2_binned_rating_scatter_around_threshold.png`
