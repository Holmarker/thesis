# Thesis Descriptive Statistics

This folder contains the clean descriptive statistics section requested for the thesis. The main sample is `all_comps` from `data/panel/fotmob_analysis_panel_all_comps.csv`, so earlier contract-panel seasons are included.

Positive FotMob rating variables are used for rating means and plots. Zero ratings are treated as no-rating observations and set to missing in `fotmob_mean_rating_clean` and `fotmob_minutes_weighted_rating_clean`. Earlier seasons can contribute to contract timing, Bosman status, player, club, and Transfermarkt variables even when FotMob ratings are unavailable.

## Sample Overview

- Observations: 219714
- Players: 7741
- Clubs: 1784
- Seasons: 5
- First month: 2022-06-01
- Last month: 2026-06-01
- Bosman-window observations: 23322
- Non-Bosman observations: 196392

Season-level coverage is saved in `season_coverage.csv`.

## FotMob Rating Availability

The contract panel now covers older seasons, but FotMob rating coverage is not available for every historical season in the local files. Rating coverage by season is saved in `fotmob_rating_availability_by_season.csv`; the historical rating checkpoint audit is saved in `historical_rating_file_audit.csv`.

- `2021/2022`: observations = 20, positive mean-rating rows = 0 (0.0%)
- `2022/2023`: observations = 33642, positive mean-rating rows = 10782 (32.0%)
- `2023/2024`: observations = 52150, positive mean-rating rows = 25056 (48.0%)
- `2024/2025`: observations = 66780, positive mean-rating rows = 38023 (56.9%)
- `2025/2026`: observations = 67122, positive mean-rating rows = 46099 (68.7%)

The 2024/25 ratings from `data/historical/checkpoints/ratings` are also read directly and summarised in this folder:

- 2024/25 checkpoint ratings: observations = 1134529, positive ratings = 764588, players = 28190, matches = 29469, date range = 2022-08-05 to 2026-06-30, mean rating = 6.84, panel-matched positive ratings = 387539

- `historical_2024_2025_checkpoint_rating_overview.csv`
- `historical_2024_2025_checkpoint_rating_by_month.csv`
- `historical_2024_2025_checkpoint_rating_by_league.csv`
- `historical_2024_2025_checkpoint_rating_histogram.png`

## Table 1

Full sample summary statistics are saved in `table1_full_sample_summary_statistics.csv`.

- `Age`: n = 219018, mean = 25.07, sd = 4.35, median = 25.00
- `Assists_per90_tm`: n = 157819, mean = 0.11, sd = 0.79, median = 0.00
- `Assists_tm`: n = 219714, mean = 0.18, sd = 0.51, median = 0.00
- `DaysToExpiry`: n = 219714, mean = 768.58, sd = 457.02, median = 729.00
- `Goals_per90_tm`: n = 157819, mean = 0.16, sd = 0.83, median = 0.00
- `Goals_tm`: n = 219714, mean = 0.26, sd = 0.69, median = 0.00
- `Minutes_tm`: n = 219714, mean = 164.05, sd = 162.71, median = 124.00
- `fotmob_assists`: n = 145165, mean = 0.18, sd = 0.49, median = 0.00
- `fotmob_goals`: n = 145165, mean = 0.26, sd = 0.66, median = 0.00
- `fotmob_matches`: n = 145165, mean = 3.46, sd = 1.51, median = 3.00
- `fotmob_mean_rating_clean`: n = 119960, mean = 6.39, sd = 1.32, median = 6.70
- `fotmob_minutes`: n = 145165, mean = 178.14, sd = 146.39, median = 164.00
- `fotmob_minutes_weighted_rating_clean`: n = 119952, mean = 6.76, sd = 0.81, median = 6.82

## Table 2

Comparison of means between player-months inside and outside the Bosman window is saved in `table2_bosman_window_mean_comparison_ttests.csv`.

- `DaysToExpiry`: Bosman mean = 111.91, outside mean = 846.56, diff = -734.65, p = <0.001
- `Age`: Bosman mean = 27.55, outside mean = 24.77, diff = 2.78, p = <0.001
- `Minutes_tm`: Bosman mean = 147.93, outside mean = 165.96, diff = -18.03, p = <0.001
- `Goals_tm`: Bosman mean = 0.21, outside mean = 0.26, diff = -0.05, p = <0.001
- `Assists_tm`: Bosman mean = 0.15, outside mean = 0.19, diff = -0.04, p = <0.001
- `Goals_per90_tm`: Bosman mean = 0.14, outside mean = 0.16, diff = -0.01, p = 0.0574
- `Assists_per90_tm`: Bosman mean = 0.10, outside mean = 0.11, diff = -0.01, p = 0.1334
- `fotmob_matches`: Bosman mean = 3.41, outside mean = 3.47, diff = -0.06, p = <0.001
- `fotmob_minutes`: Bosman mean = 169.43, outside mean = 179.14, diff = -9.71, p = <0.001
- `fotmob_goals`: Bosman mean = 0.23, outside mean = 0.27, diff = -0.04, p = <0.001
- `fotmob_assists`: Bosman mean = 0.15, outside mean = 0.18, diff = -0.03, p = <0.001
- `fotmob_mean_rating_clean`: Bosman mean = 6.38, outside mean = 6.39, diff = -0.01, p = 0.6218
- `fotmob_minutes_weighted_rating_clean`: Bosman mean = 6.76, outside mean = 6.76, diff = 0.01, p = 0.3199

## Table 3

Signing event summary statistics for the renewal analysis subsample are saved in `table3_renewal_signing_event_summary.csv`. The file `renewal_subsample_overview.csv` gives the overall renewal-sample counts.

## Figures

- `figure1_days_to_expiry_histogram.png`
- `figure2_binned_rating_scatter_around_threshold.png`
