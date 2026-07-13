# Thesis Descriptive Statistics

This folder contains the clean descriptive statistics section requested for the thesis. The main sample is `all_comps` from `data/panel/fotmob_analysis_panel_all_comps.csv`, so earlier contract-panel seasons are included.

Positive FotMob rating variables are used for rating means and plots. Zero ratings are treated as no-rating observations and set to missing in `fotmob_mean_rating_clean` and `fotmob_minutes_weighted_rating_clean`. Earlier seasons can contribute to contract timing, Bosman status, player, club, and Transfermarkt variables even when FotMob ratings are unavailable.

## Sample Overview

- Observations: 232055
- Players: 8199
- Clubs: 1788
- Seasons: 5
- First month: 2022-06-01
- Last month: 2026-06-01
- Bosman-window observations: 25475
- Non-Bosman observations: 206580

Season-level coverage is saved in `season_coverage.csv`.

## FotMob Rating Availability

The contract panel now covers older seasons, but FotMob rating coverage is not available for every historical season in the local files. Rating coverage by season is saved in `fotmob_rating_availability_by_season.csv`; the historical rating checkpoint audit is saved in `historical_rating_file_audit.csv`.

- `2021/2022`: observations = 20, positive mean-rating rows = 0 (0.0%)
- `2022/2023`: observations = 44639, positive mean-rating rows = 30580 (68.5%)
- `2023/2024`: observations = 54923, positive mean-rating rows = 32866 (59.8%)
- `2024/2025`: observations = 65995, positive mean-rating rows = 37861 (57.4%)
- `2025/2026`: observations = 66478, positive mean-rating rows = 47284 (71.1%)

The 2024/25 ratings from `data/historical/checkpoints/ratings` are also read directly and summarised in this folder:

- 2024/25 checkpoint ratings: observations = 1584464, positive ratings = 1078727, players = 33568, matches = 40677, date range = 2022-07-01 to 2026-06-30, mean rating = 6.84, panel-matched positive ratings = 519600

- `historical_2024_2025_checkpoint_rating_overview.csv`
- `historical_2024_2025_checkpoint_rating_by_month.csv`
- `historical_2024_2025_checkpoint_rating_by_league.csv`
- `historical_2024_2025_checkpoint_rating_histogram.png`

## Table 1

Full sample summary statistics are saved in `table1_full_sample_summary_statistics.csv`.

- `Age`: n = 231269, mean = 25.12, sd = 4.33, median = 25.00
- `Assists_per90_tm`: n = 157936, mean = 0.11, sd = 0.79, median = 0.00
- `Assists_tm`: n = 232055, mean = 0.17, sd = 0.50, median = 0.00
- `DaysToExpiry`: n = 232055, mean = 758.86, sd = 454.66, median = 699.00
- `Goals_per90_tm`: n = 157936, mean = 0.16, sd = 0.83, median = 0.00
- `Goals_tm`: n = 232055, mean = 0.25, sd = 0.68, median = 0.00
- `Minutes_tm`: n = 232055, mean = 155.43, sd = 162.55, median = 103.00
- `fotmob_assists`: n = 177249, mean = 0.18, sd = 0.50, median = 0.00
- `fotmob_goals`: n = 177249, mean = 0.27, sd = 0.67, median = 0.00
- `fotmob_matches`: n = 177249, mean = 3.51, sd = 1.50, median = 3.00
- `fotmob_mean_rating_clean`: n = 148591, mean = 6.84, sd = 0.57, median = 6.82
- `fotmob_minutes`: n = 177249, mean = 184.51, sd = 146.63, median = 176.00
- `fotmob_minutes_weighted_rating_clean`: n = 148569, mean = 6.88, sd = 0.58, median = 6.89

## Table 2

Comparison of means between player-months inside and outside the Bosman window is saved in `table2_bosman_window_mean_comparison_ttests.csv`.

- `DaysToExpiry`: Bosman mean = 112.26, outside mean = 838.60, diff = -726.34, p = <0.001
- `Age`: Bosman mean = 27.58, outside mean = 24.82, diff = 2.76, p = <0.001
- `Minutes_tm`: Bosman mean = 135.60, outside mean = 157.88, diff = -22.28, p = <0.001
- `Goals_tm`: Bosman mean = 0.19, outside mean = 0.25, diff = -0.06, p = <0.001
- `Assists_tm`: Bosman mean = 0.14, outside mean = 0.18, diff = -0.04, p = <0.001
- `Goals_per90_tm`: Bosman mean = 0.14, outside mean = 0.16, diff = -0.01, p = 0.0581
- `Assists_per90_tm`: Bosman mean = 0.10, outside mean = 0.11, diff = -0.01, p = 0.1300
- `fotmob_matches`: Bosman mean = 3.51, outside mean = 3.51, diff = 0.00, p = 0.6968
- `fotmob_minutes`: Bosman mean = 183.04, outside mean = 184.69, diff = -1.65, p = 0.1430
- `fotmob_goals`: Bosman mean = 0.24, outside mean = 0.28, diff = -0.04, p = <0.001
- `fotmob_assists`: Bosman mean = 0.17, outside mean = 0.19, diff = -0.02, p = <0.001
- `fotmob_mean_rating_clean`: Bosman mean = 6.82, outside mean = 6.84, diff = -0.02, p = <0.001
- `fotmob_minutes_weighted_rating_clean`: Bosman mean = 6.86, outside mean = 6.88, diff = -0.03, p = <0.001

## Table 3

Signing event summary statistics for the renewal analysis subsample are saved in `table3_renewal_signing_event_summary.csv`. The file `renewal_subsample_overview.csv` gives the overall renewal-sample counts.

## Figures

- `figure1_days_to_expiry_histogram.png`
- `figure2_binned_rating_scatter_around_threshold.png`
