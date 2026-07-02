# FotMob Regression Summary

This folder contains the current FotMob contract-expiry regressions, RDD checks, heterogeneity splits, and design diagnostics. Last full regeneration: 2026-07-02, after (a) the full-season 2024/25 top-5-league match-rating scrape, (b) the crosswalk recovery passes (~1,130 additional rated players), and (c) the addition of league-standardized outcomes.

## Leakage Fix

The expiry/Bosman variables are based on contract information observed at the player-month: `DaysToExpiry`, `Bosman`, and `expiry_bin_6m` are contemporaneous contract-status measures.

The leaky renewal variables have been removed from the main outputs. The previous `ever_signed_new_contract`, `first_sign_month`, `post_new_contract`, and `sign_bin_6m` setup used the full observed future path of each player. Current results use only `signed_new_contract` and `post_observed_renewal`, where post-renewal status is based on contract extensions already observed before the current player-month.

## Outcome Standardization

Alongside the raw outcomes (`fotmob_mean_rating`, `fotmob_minutes_weighted_rating`), all models are run on ratings z-scored within `fotmob_source_league x season` and within `fotmob_source_league x Month` (positive ratings only). Raw and standardized results diverge in instructive ways: league composition was masking some within-league patterns. Standardized coefficients are the preferred read.

## Sample Coverage

`fotmob_regression_sample_coverage.csv` after the 2024/25 rebuild:

- `all_comps_strict` (59,306 rows total)
  - `2022/2023`: 5,090 rows, 638 players.
  - `2023/2024`: 6,620 rows, 853 players.
  - `2024/2025`: 14,811 rows, 3,682 players (now covers Aug 2024 - Jun 2025; previously only Mar-Jun 2025).
  - `2025/2026`: 32,785 rows, 5,131 players.
- `source_league_strict` (50,889 rows total)
  - `2022/2023`: 5,090 rows, 638 players.
  - `2023/2024`: 6,620 rows, 853 players.
  - `2024/2025`: 11,349 rows, 2,358 players.
  - `2025/2026`: 27,830 rows, 4,855 players.

The old 2024/25 hole (Aug 2024 - Feb 2025) was caused by that season having been scraped through FotMob's truncated recent-matches endpoint; it has been re-scraped match-by-match for the top-5 leagues. The remaining ~31 leagues for 2024/25 are being scraped and will add further rows.

Crosswalk status: 9,639 merge-safe pairs. Of 15,515 rated FotMob players, ~8,600 are matched; ~6,300 of the unmatched have no counterpart in the Transfermarkt contract universe at all (documented sample limitation, not recoverable); ~640 remain in manual review (`data/crosswalk_manual_review_remaining.xlsx`).

## Main Regression Takeaways

Preferred outcome: `z_mean_rating_league_season` (league-season standardized mean rating), all-comps strict sample.

- `bosman_fe` (pooled)
  - No pooled Bosman effect: `+0.031`, `p = 0.19` (all-comps); `+0.002`, `p = 0.95` (source-league).
- **Bosman x age (heterogeneity, the headline result)**
  - `u23`: `+0.198`, `p = 0.011`
  - `23_28`: `+0.128`, `p = 0.0004`
  - `29_plus`: `-0.040`, `p = 0.25`
  - The pooled null hides offsetting groups: players with careers still to build perform better in the Bosman window; older players do not. Robust to the 2024/25 data expansion.
- `expiry_bin_6m_fe`
  - `48+` months to expiry: `-0.093`, `p = 0.0017` (all-comps). Likely contract-sorting/selection, not a clean treatment; the source-league estimate is smaller and insignificant (`-0.034`, `p = 0.27`).
- `observed_renewal_status_fe`
  - `post_observed_renewal`: `-0.097`, `p < 0.0001` — the most robust pattern in the panel. Within-league relative ratings decline after signing an extension.
  - `signing_month`: `-0.067`, `p = 0.0017`.
  - Renewal splits: strongest for attackers (`-0.128`, `p = 0.003`) and outside the top-5 (`-0.124`, `p = 0.0005`); absent for age 29+.
  - These remain descriptive conditional associations: renewal timing is endogenous to expected value, club plans, and prior performance.

Multiple-testing caveat: with ~11 subgroups per hypothesis, isolated `p < 0.05` cells are expected by chance. The age gradient is credible because it is monotone with one cell at `p = 0.0004`; treat single-cell subgroup findings with care.

## RDD Takeaways

Main estimates in `fotmob_rdd_results.csv`, robustness in `fotmob_rdd_robustness.csv`. Local linear models around `DaysToExpiry = 180` with Month FE, clustered by player.

The RDD remains unusable as primary causal evidence:

- Implausibly large estimates persist (e.g. `source_league`, minutes-weighted, 30-day bandwidth: `~19.3`, `p < 0.001` on a 0-10 rating scale).
- Placebo cutoffs still fire after the data expansion (mean rating, 90-day bandwidth): cutoff 150: `+3.34` (`p = 0.003`) source-league / `+4.26` (`p = 0.0001`) all-comps; cutoff 210: `-2.09` (`p = 0.002`) / `-1.94` (`p = 0.006`).
- Interpretation: local support/composition patterns around contract-time thresholds, not a discontinuity at the legal Bosman cutoff. Keep the RDD as a descriptive robustness exhibit only.

## Design Diagnostics

- `fotmob_design_sample_funnel.csv`, `fotmob_design_rdd_support.csv`, `fotmob_design_near_cutoff_balance.csv` (all regenerated on the rebuilt panel).
- Near-cutoff balance still shows small composition differences (inside-cutoff rows slightly older), consistent with the placebo failures.

## Descriptive Summary Takeaways

- `fotmob_observed_renewal_summary.csv` (raw, unstandardized):
  - `no_observed_renewal_yet`: 37,429 rows, weighted raw rating ~6.17.
  - `signing_month`: 2,452 rows, ~6.33.
  - `post_observed_renewal`: 19,425 rows, ~6.56.
  - Note the raw post-renewal average is *higher* while the within-player standardized effect is negative — selection into renewal (better players get renewed) versus within-player decline after renewal.

## Research Interpretation

The defensible narrative has sharpened since the first pass:

1. No broad Bosman performance boost, but a robust positive Bosman-window effect for players under ~29, consistent with career-concerns incentives concentrated among players with future contracts to win.
2. A robust within-player post-renewal rating decline, consistent with incentive slack after locking in security — though endogenous renewal timing precludes a clean causal claim.
3. The RDD fails placebo diagnostics and should not be presented as causal evidence.

## Remaining Improvements

1. Finish the 2024/25 scrape for the ~31 non-top-5 leagues (in progress), then rebuild and rerun.
2. Scrape non-top-5 leagues for 2022/23 and 2023/24 (and 2021/22 if the endpoint allows).
3. Manual crosswalk review of the remaining ~640 ambiguous players (`data/crosswalk_manual_review_remaining.xlsx`).
4. Consider event-study specification around observed renewal dates to sharpen the post-renewal finding.
