# FotMob Regression Summary

This folder contains the current FotMob contract-expiry regressions, RDD checks, and design diagnostics.

## Leakage Fix

The expiry/Bosman variables are based on contract information observed at the player-month: `DaysToExpiry`, `Bosman`, and `expiry_bin_6m` are contemporaneous contract-status measures.

The leaky renewal variables have been removed from the main outputs. The previous `ever_signed_new_contract`, `first_sign_month`, `post_new_contract`, and `sign_bin_6m` setup used the full observed future path of each player. The regenerated results now use only `signed_new_contract` and `post_observed_renewal`, where post-renewal status is based on contract extensions already observed before the current player-month.

## Sample Coverage

The strict panels now refresh FotMob monthly ratings onto existing player-month rows and add missing rated months when contract state can be rolled forward. This fixed the older-season bottleneck where valid 2022/23 and 2023/24 FotMob master rows existed but were not entering the strict sample.

See `fotmob_regression_sample_coverage.csv` for the season split:

- `all_comps_strict`
  - `2022/2023`: 4,318 rows, 633 players.
  - `2023/2024`: 6,046 rows, 850 players.
  - `2024/2025`: 9,186 rows, 3,617 players.
  - `2025/2026`: 32,785 rows, 5,131 players.
- `source_league_strict`
  - `2022/2023`: 4,318 rows, 633 players.
  - `2023/2024`: 6,046 rows, 850 players.
  - `2024/2025`: 5,596 rows, 2,258 players.
  - `2025/2026`: 27,830 rows, 4,855 players.

The new design funnel is saved to `fotmob_design_sample_funnel.csv`. It shows that most matched older-season master rows now enter the strict panel:

- 2022/23 all-comps: 5,595 master monthly rows, 4,841 exact panel overlaps, 4,318 strict rows.
- 2023/24 all-comps: 7,312 master monthly rows, 6,818 exact panel overlaps, 6,046 strict rows.

Remaining sample limitations are mainly upstream: crosswalk coverage, top-five-only older-season scraping, and no 2021/22 FotMob monthly ratings yet.

## Main Regression Takeaways

- `bosman_fe`
  - No meaningful Bosman effect appears in either sample or outcome.
  - P-values remain well above conventional significance thresholds.

- `expiry_bin_6m_fe`
  - Most expiry-bin coefficients are small or not statistically significant.
  - The clearest result is in `all_comps_strict` for `fotmob_mean_rating`:
    - `expiry_bin_6m::48+ = -0.1492`
    - `p = 0.0089`
  - The corresponding `source_league_strict` estimate is smaller and not statistically significant:
    - `expiry_bin_6m::48+ = -0.0394`
    - `p = 0.4765`
  - Interpretation should be cautious: a `48+` month contract is likely a selected contract state, not a clean treatment.

- `observed_renewal_status_fe`
  - `signed_new_contractTRUE`, `fotmob_mean_rating`: `-0.0775`, `p = 0.0909`
  - `post_observed_renewalTRUE`, `fotmob_mean_rating`: `-0.0922`, `p = 0.0295`
  - `signed_new_contractTRUE`, `fotmob_minutes_weighted_rating`: `0.0505`, `p = 0.2135`
  - `post_observed_renewalTRUE`, `fotmob_minutes_weighted_rating`: `-0.0067`, `p = 0.8416`

The renewal coefficients are descriptive conditional associations. Renewal timing is endogenous to expected player value, club plans, negotiation dynamics, and prior performance.

## RDD Takeaways

The main RDD estimates are stored in `fotmob_rdd_results.csv`, with expanded robustness checks in `fotmob_rdd_robustness.csv`. The RDD uses local linear models around `DaysToExpiry = 180`:

`outcome ~ post_cutoff + running + post_cutoff:running | Month`

with standard errors clustered by `player_id`.

The main RDD estimates still include implausibly large effects relative to the FotMob rating scale:

- `source_league`, `fotmob_minutes_weighted_rating`, 30-day bandwidth: `19.2712`, `p < 0.001`.
- `all_comps`, `fotmob_minutes_weighted_rating`, 30-day bandwidth: `6.7530`, `p = 0.0040`.

The expanded placebo-cutoff checks weaken the causal interpretation. For `fotmob_mean_rating`, placebo cutoffs at 150 and 210 days are also statistically significant in both samples:

- `source_league`, cutoff 150: `3.31`, `p = 0.0035`.
- `source_league`, cutoff 210: `-2.08`, `p = 0.0024`.
- `all_comps`, cutoff 150: `4.25`, `p < 0.001`.
- `all_comps`, cutoff 210: `-1.94`, `p = 0.0062`.

This suggests the RDD is picking up local support/composition patterns around contract-time thresholds, not a clean discontinuity at the legal Bosman cutoff.

## Design Diagnostics

New diagnostics are saved in:

- `fotmob_design_sample_funnel.csv`
- `fotmob_design_rdd_support.csv`
- `fotmob_design_near_cutoff_balance.csv`

The 180-day RDD has substantial support. In the 90-day bandwidth:

- `all_comps`: 7,132 rows above cutoff, 9,805 rows inside cutoff.
- `source_league`: 7,049 rows above cutoff, 9,691 rows inside cutoff.

But the near-cutoff balance table shows small composition differences. Inside-cutoff rows are slightly older on average than above-cutoff rows, and placebo cutoff results are not quiet. That makes the RDD useful as a descriptive robustness check, not a primary causal design.

## Descriptive Summary Takeaways

- `fotmob_expiry_6m_summary.csv`
  - Expiry-bin averages vary across bins, but the raw descriptive means do not imply a simple monotonic expiry-performance pattern.
  - In `all_comps_strict`, weighted raw ratings range from about `5.91` to `6.54`.
  - In `source_league_strict`, weighted raw ratings range from about `6.27` to `6.69`.

- `fotmob_observed_renewal_summary.csv`
  - `no_observed_renewal_yet`: 35,430 rows, weighted raw rating about `6.11`.
  - `signing_month`: 2,322 rows, weighted raw rating about `6.25`.
  - `post_observed_renewal`: 14,583 rows, weighted raw rating about `6.48`.

## Research Interpretation

The strongest defensible conclusion is modest:

The FotMob panel shows little evidence of a broad Bosman performance boost. Some long-contract bins and post-renewal states differ from reference periods, but those differences are plausibly driven by contract sorting, player selection, and club decision-making rather than clean incentive effects.

The RDD should not be presented as decisive causal evidence unless additional diagnostics are added and the placebo-cutoff problem is resolved.

## Best Next Improvements

1. Expand or repair the FotMob-Transfermarkt crosswalk; many scraped rated players still do not safely match.
2. Scrape the remaining non-top-five leagues for 2022/23 and 2023/24.
3. Add 2021/22 FotMob ratings if the endpoint supports it.
4. Add heterogeneity splits: age groups, starters vs bench players, position groups, and league tiers.
5. Standardize ratings within league-season or league-month before interpreting coefficient sizes.
6. Treat RDD as secondary unless placebo cutoffs and support diagnostics become much cleaner.
