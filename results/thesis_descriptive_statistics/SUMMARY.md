# Thesis Descriptive Statistics

This folder contains the clean descriptive statistics section requested for the thesis. The main sample is `all_comps` from `data/panel/fotmob_analysis_panel_all_comps.csv`, so earlier contract-panel seasons are included.

Positive FotMob rating variables are used for rating means and plots. Zero ratings are treated as no-rating observations and set to missing in `fotmob_mean_rating_clean` and `fotmob_minutes_weighted_rating_clean`. Earlier seasons can contribute to contract timing, Bosman status, player, club, and Transfermarkt variables even when FotMob ratings are unavailable.

## Sample Overview

- Observations: 159522
- Players: 5695
- Clubs: 1448
- Seasons: 5
- First month: 2022-06-01
- Last month: 2026-06-01
- Bosman-window observations: 15423
- Non-Bosman observations: 144099

Season-level coverage is saved in `season_coverage.csv`.

## FotMob Rating Availability

The contract panel now covers older seasons, but FotMob rating coverage is not available for every historical season in the local files. Rating coverage by season is saved in `fotmob_rating_availability_by_season.csv`; the historical rating checkpoint audit is saved in `historical_rating_file_audit.csv`.

- `2021/2022`: observations = 19, positive mean-rating rows = 0 (0.0%)
- `2022/2023`: observations = 26447, positive mean-rating rows = 5090 (19.2%)
- `2023/2024`: observations = 40097, positive mean-rating rows = 6620 (16.5%)
- `2024/2025`: observations = 45589, positive mean-rating rows = 20574 (45.1%)
- `2025/2026`: observations = 47370, positive mean-rating rows = 35738 (75.4%)

The 2024/25 ratings from `data/historical/checkpoints/ratings` are also read directly and summarised in this folder:

- 2024/25 checkpoint ratings: observations = 992035, positive ratings = 667781, players = 26945, matches = 26023, date range = 2022-08-05 to 2026-06-30, mean rating = 6.83, panel-matched positive ratings = 278896

- `historical_2024_2025_checkpoint_rating_overview.csv`
- `historical_2024_2025_checkpoint_rating_by_month.csv`
- `historical_2024_2025_checkpoint_rating_by_league.csv`
- `historical_2024_2025_checkpoint_rating_histogram.png`

## Table 1

Full sample summary statistics are saved in `table1_full_sample_summary_statistics.csv`.

- `Age`: n = 159005, mean = 25.22, sd = 4.21, median = 25.00
- `Assists_per90_tm`: n = 109247, mean = 0.12, sd = 0.82, median = 0.00
- `Assists_tm`: n = 159522, mean = 0.18, sd = 0.52, median = 0.00
- `DaysToExpiry`: n = 159522, mean = 782.08, sd = 453.55, median = 730.00
- `Goals_per90_tm`: n = 109247, mean = 0.16, sd = 0.76, median = 0.00
- `Goals_tm`: n = 159522, mean = 0.25, sd = 0.69, median = 0.00
- `Minutes_tm`: n = 159522, mean = 156.06, sd = 163.31, median = 100.00
- `fotmob_assists`: n = 80280, mean = 0.20, sd = 0.51, median = 0.00
- `fotmob_goals`: n = 80280, mean = 0.29, sd = 0.71, median = 0.00
- `fotmob_matches`: n = 80280, mean = 3.64, sd = 1.62, median = 4.00
- `fotmob_mean_rating_clean`: n = 68022, mean = 6.08, sd = 1.61, median = 6.60
- `fotmob_minutes`: n = 80280, mean = 192.62, sd = 150.11, median = 180.00
- `fotmob_minutes_weighted_rating_clean`: n = 68022, mean = 6.70, sd = 0.93, median = 6.82

## Table 2

Comparison of means between player-months inside and outside the Bosman window is saved in `table2_bosman_window_mean_comparison_ttests.csv`.

- `DaysToExpiry`: Bosman mean = 113.88, outside mean = 853.60, diff = -739.72, p = <0.001
- `Age`: Bosman mean = 27.76, outside mean = 24.94, diff = 2.81, p = <0.001
- `Minutes_tm`: Bosman mean = 135.34, outside mean = 158.28, diff = -22.93, p = <0.001
- `Goals_tm`: Bosman mean = 0.19, outside mean = 0.25, diff = -0.06, p = <0.001
- `Assists_tm`: Bosman mean = 0.14, outside mean = 0.19, diff = -0.05, p = <0.001
- `Goals_per90_tm`: Bosman mean = 0.14, outside mean = 0.16, diff = -0.02, p = 0.142
- `Assists_per90_tm`: Bosman mean = 0.11, outside mean = 0.12, diff = -0.01, p = 0.443
- `fotmob_matches`: Bosman mean = 3.46, outside mean = 3.66, diff = -0.20, p = <0.001
- `fotmob_minutes`: Bosman mean = 171.06, outside mean = 194.90, diff = -23.84, p = <0.001
- `fotmob_goals`: Bosman mean = 0.22, outside mean = 0.30, diff = -0.08, p = <0.001
- `fotmob_assists`: Bosman mean = 0.15, outside mean = 0.20, diff = -0.05, p = <0.001
- `fotmob_mean_rating_clean`: Bosman mean = 6.03, outside mean = 6.08, diff = -0.05, p = 0.020
- `fotmob_minutes_weighted_rating_clean`: Bosman mean = 6.71, outside mean = 6.70, diff = 0.02, p = 0.124

## Table 3

Signing event summary statistics for the renewal analysis subsample are saved in `table3_renewal_signing_event_summary.csv`. The file `renewal_subsample_overview.csv` gives the overall renewal-sample counts.

## Figures

- `figure1_days_to_expiry_histogram.png`
- `figure2_binned_rating_scatter_around_threshold.png`
