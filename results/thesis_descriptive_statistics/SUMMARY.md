# Thesis Descriptive Statistics

This folder contains the clean descriptive statistics section requested for the thesis. The main sample is `all_comps` from `data/panel/fotmob_analysis_panel_all_comps.csv`, so earlier contract-panel seasons are included.

Positive FotMob rating variables are used for rating means and plots. Zero ratings are treated as no-rating observations and set to missing in `fotmob_mean_rating_clean` and `fotmob_minutes_weighted_rating_clean`. Earlier seasons can contribute to contract timing, Bosman status, player, club, and Transfermarkt variables even when FotMob ratings are unavailable.

## Sample Overview

- Observations: 234735
- Players: 8375
- Clubs: 1816
- Seasons: 5
- First month: 2022-06-01
- Last month: 2026-06-01
- Bosman-window observations: 25911
- Non-Bosman observations: 208824

Season-level coverage is saved in `season_coverage.csv`.

## FotMob Rating Availability

The contract panel now covers older seasons, but FotMob rating coverage is not available for every historical season in the local files. Rating coverage by season is saved in `fotmob_rating_availability_by_season.csv`; the historical rating checkpoint audit is saved in `historical_rating_file_audit.csv`.

- `2021/2022`: observations = 20, positive mean-rating rows = 0 (0.0%)
- `2022/2023`: observations = 45279, positive mean-rating rows = 31031 (68.5%)
- `2023/2024`: observations = 55373, positive mean-rating rows = 33177 (59.9%)
- `2024/2025`: observations = 66831, positive mean-rating rows = 38134 (57.1%)
- `2025/2026`: observations = 67232, positive mean-rating rows = 46675 (69.4%)

The 2024/25 ratings from `data/historical/checkpoints/ratings` are also read directly and summarised in this folder:

- 2024/25 checkpoint ratings: observations = 1584464, positive ratings = 1078727, players = 33568, matches = 40677, date range = 2022-07-01 to 2026-06-30, mean rating = 6.84, panel-matched positive ratings = 526441

- `historical_2024_2025_checkpoint_rating_overview.csv`
- `historical_2024_2025_checkpoint_rating_by_month.csv`
- `historical_2024_2025_checkpoint_rating_by_league.csv`
- `historical_2024_2025_checkpoint_rating_histogram.png`

## Table 1

Full sample summary statistics are saved in `table1_full_sample_summary_statistics.csv`.

- `Age`: n = 233923, mean = 25.11, sd = 4.33, median = 25.00
- `Assists_per90_tm`: n = 159209, mean = 0.11, sd = 0.79, median = 0.00
- `Assists_tm`: n = 234735, mean = 0.17, sd = 0.50, median = 0.00
- `DaysToExpiry`: n = 234735, mean = 757.23, sd = 454.37, median = 699.00
- `Goals_per90_tm`: n = 159209, mean = 0.16, sd = 0.86, median = 0.00
- `Goals_tm`: n = 234735, mean = 0.24, sd = 0.67, median = 0.00
- `Minutes_tm`: n = 234735, mean = 154.69, sd = 162.36, median = 101.00
- `fotmob_assists`: n = 178053, mean = 0.18, sd = 0.49, median = 0.00
- `fotmob_goals`: n = 178053, mean = 0.27, sd = 0.66, median = 0.00
- `fotmob_matches`: n = 178053, mean = 3.46, sd = 1.45, median = 3.00
- `fotmob_mean_rating_clean`: n = 149017, mean = 6.84, sd = 0.57, median = 6.82
- `fotmob_minutes`: n = 178053, mean = 181.70, sd = 144.54, median = 174.00
- `fotmob_minutes_weighted_rating_clean`: n = 148995, mean = 6.88, sd = 0.58, median = 6.89

## Table 2

Comparison of means between player-months inside and outside the Bosman window is saved in `table2_bosman_window_mean_comparison_ttests.csv`.

- `DaysToExpiry`: Bosman mean = 112.25, outside mean = 837.26, diff = -725.01, p = <0.001
- `Age`: Bosman mean = 27.56, outside mean = 24.81, diff = 2.75, p = <0.001
- `Minutes_tm`: Bosman mean = 135.09, outside mean = 157.12, diff = -22.03, p = <0.001
- `Goals_tm`: Bosman mean = 0.19, outside mean = 0.25, diff = -0.06, p = <0.001
- `Assists_tm`: Bosman mean = 0.13, outside mean = 0.18, diff = -0.04, p = <0.001
- `Goals_per90_tm`: Bosman mean = 0.14, outside mean = 0.16, diff = -0.02, p = 0.0425
- `Assists_per90_tm`: Bosman mean = 0.10, outside mean = 0.11, diff = -0.01, p = 0.1465
- `fotmob_matches`: Bosman mean = 3.50, outside mean = 3.46, diff = 0.04, p = <0.001
- `fotmob_minutes`: Bosman mean = 182.37, outside mean = 181.61, diff = 0.75, p = 0.4990
- `fotmob_goals`: Bosman mean = 0.24, outside mean = 0.27, diff = -0.03, p = <0.001
- `fotmob_assists`: Bosman mean = 0.17, outside mean = 0.18, diff = -0.02, p = <0.001
- `fotmob_mean_rating_clean`: Bosman mean = 6.81, outside mean = 6.84, diff = -0.03, p = <0.001
- `fotmob_minutes_weighted_rating_clean`: Bosman mean = 6.85, outside mean = 6.88, diff = -0.03, p = <0.001

## Table 3

Signing event summary statistics for the renewal analysis subsample are saved in `table3_renewal_signing_event_summary.csv`. The file `renewal_subsample_overview.csv` gives the overall renewal-sample counts.

## Figures

- `figure1_days_to_expiry_histogram.png`
- `figure2_binned_rating_scatter_around_threshold.png`
