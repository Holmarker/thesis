# Thesis Descriptive Statistics

This folder contains the clean descriptive statistics section requested for the thesis. The main sample is `all_comps` from `data/panel/fotmob_analysis_panel_all_comps.csv`, so earlier contract-panel seasons are included.

Positive FotMob rating variables are used for rating means and plots. Zero ratings are treated as no-rating observations and set to missing in `fotmob_mean_rating_clean` and `fotmob_minutes_weighted_rating_clean`. Earlier seasons can contribute to contract timing, Bosman status, player, club, and Transfermarkt variables even when FotMob ratings are unavailable.

## Sample Overview

- Observations: 152817
- Players: 5695
- Clubs: 1448
- Seasons: 5
- First month: 2022-06-01
- Last month: 2026-03-01
- Bosman-window observations: 14298
- Non-Bosman observations: 138519

Season-level coverage is saved in `season_coverage.csv`.

## FotMob Rating Availability

The contract panel now covers older seasons, but FotMob rating coverage is not available for every historical season in the local files. Rating coverage by season is saved in `fotmob_rating_availability_by_season.csv`; the historical rating checkpoint audit is saved in `historical_rating_file_audit.csv`.

- `2021/2022`: observations = 19, positive mean-rating rows = 0 (0.0%)
- `2022/2023`: observations = 26447, positive mean-rating rows = 5090 (19.2%)
- `2023/2024`: observations = 40097, positive mean-rating rows = 6620 (16.5%)
- `2024/2025`: observations = 45480, positive mean-rating rows = 14087 (31.0%)
- `2025/2026`: observations = 40774, positive mean-rating rows = 30322 (74.4%)

The 2024/25 ratings from `data/historical/checkpoints/ratings` are also read directly and summarised in this folder:

- 2024/25 checkpoint ratings: observations = 316581, positive ratings = 204741, players = 13860, matches = 10691, date range = 2022-08-05 to 2025-06-01, mean rating = 6.85, panel-matched positive ratings = 119870

- `historical_2024_2025_checkpoint_rating_overview.csv`
- `historical_2024_2025_checkpoint_rating_by_month.csv`
- `historical_2024_2025_checkpoint_rating_by_league.csv`
- `historical_2024_2025_checkpoint_rating_histogram.png`

## Table 1

Full sample summary statistics are saved in `table1_full_sample_summary_statistics.csv`.

- `Age`: n = 152320, mean = 25.17, sd = 4.20, median = 25.00
- `Assists_per90_tm`: n = 109247, mean = 0.12, sd = 0.82, median = 0.00
- `Assists_tm`: n = 152817, mean = 0.19, sd = 0.53, median = 0.00
- `DaysToExpiry`: n = 152817, mean = 783.90, sd = 452.49, median = 730.00
- `Goals_per90_tm`: n = 109247, mean = 0.16, sd = 0.76, median = 0.00
- `Goals_tm`: n = 152817, mean = 0.26, sd = 0.70, median = 0.00
- `Minutes_tm`: n = 152817, mean = 162.91, sd = 163.48, median = 117.00
- `fotmob_assists`: n = 66150, mean = 0.20, sd = 0.52, median = 0.00
- `fotmob_goals`: n = 66150, mean = 0.30, sd = 0.72, median = 0.00
- `fotmob_matches`: n = 66150, mean = 3.72, sd = 1.67, median = 4.00
- `fotmob_mean_rating_clean`: n = 56119, mean = 5.92, sd = 1.71, median = 6.55
- `fotmob_minutes`: n = 66150, mean = 196.71, sd = 152.43, median = 180.00
- `fotmob_minutes_weighted_rating_clean`: n = 56119, mean = 6.66, sd = 0.98, median = 6.81

## Table 2

Comparison of means between player-months inside and outside the Bosman window is saved in `table2_bosman_window_mean_comparison_ttests.csv`.

- `DaysToExpiry`: Bosman mean = 116.72, outside mean = 852.77, diff = -736.05, p = <0.001
- `Age`: Bosman mean = 27.63, outside mean = 24.92, diff = 2.71, p = <0.001
- `Minutes_tm`: Bosman mean = 145.99, outside mean = 164.65, diff = -18.66, p = <0.001
- `Goals_tm`: Bosman mean = 0.21, outside mean = 0.26, diff = -0.06, p = <0.001
- `Assists_tm`: Bosman mean = 0.15, outside mean = 0.19, diff = -0.04, p = <0.001
- `Goals_per90_tm`: Bosman mean = 0.14, outside mean = 0.16, diff = -0.02, p = 0.142
- `Assists_per90_tm`: Bosman mean = 0.11, outside mean = 0.12, diff = -0.01, p = 0.443
- `fotmob_matches`: Bosman mean = 3.52, outside mean = 3.73, diff = -0.21, p = <0.001
- `fotmob_minutes`: Bosman mean = 174.35, outside mean = 198.86, diff = -24.51, p = <0.001
- `fotmob_goals`: Bosman mean = 0.23, outside mean = 0.31, diff = -0.08, p = <0.001
- `fotmob_assists`: Bosman mean = 0.16, outside mean = 0.21, diff = -0.05, p = <0.001
- `fotmob_mean_rating_clean`: Bosman mean = 5.79, outside mean = 5.93, diff = -0.14, p = <0.001
- `fotmob_minutes_weighted_rating_clean`: Bosman mean = 6.68, outside mean = 6.66, diff = 0.02, p = 0.124

## Table 3

Signing event summary statistics for the renewal analysis subsample are saved in `table3_renewal_signing_event_summary.csv`. The file `renewal_subsample_overview.csv` gives the overall renewal-sample counts.

## Figures

- `figure1_days_to_expiry_histogram.png`
- `figure2_binned_rating_scatter_around_threshold.png`
