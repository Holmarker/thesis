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
- **Bosman x age (heterogeneity) — suggestive only, fails season-stability audit**
  - Pooled: `u23`: `+0.198`, `p = 0.011`; `23_28`: `+0.128`, `p = 0.0004`; `29_plus`: `-0.040`, `p = 0.25`.
  - Audit (`run_fotmob_robustness_audit_bosman.R`): no single season is individually significant for u23, and the estimate declines monotonically as coverage improves (2023/24: `+0.26`; 2024/25: `+0.18`; 2025/26 — the best-measured season: `+0.06`, `p = 0.61`). The minutes-weighted version is `p = 0.056`. Only 533 u23 Bosman rows / 219 players drive the pooled result.
  - Read as suggestive of a career-concerns pattern at most; do not present as a robust effect.
- `expiry_bin_6m_fe`
  - `48+` months to expiry: `-0.093`, `p = 0.0017` (all-comps). Likely contract-sorting/selection, not a clean treatment; the source-league estimate is smaller and insignificant (`-0.034`, `p = 0.27`).
- `observed_renewal_status_fe` — **does not survive the audit**
  - Pooled: `post_observed_renewal` `-0.097`, `p < 0.0001`; `signing_month` `-0.067`, `p = 0.0017`.
  - Audit (`run_fotmob_robustness_audit_renewal.R`): within every single season the post-renewal coefficient is insignificant (`p = 0.16-0.73`, mixed signs), and the event-study around the first observed renewal shows within-league z ratings slightly *rising* after signing (`+0.08` SD by months +4 to +6). The pooled negative coefficient appears to be mean reversion plus cross-season composition, not a within-player decline.

Multiple-testing caveat: with ~11 subgroups per hypothesis, isolated `p < 0.05` cells are expected by chance. Pooled significance that vanishes within every season should be treated as an artifact of composition shifts across seasons (the panel's league mix changes drastically from 2022/23 to 2025/26).

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

After the robustness audit (2026-07-02), the defensible narrative is a careful null:

1. No robust Bosman performance effect — pooled or within any age group — once season-stability is required. The u23/23-28 pooled positives are suggestive of a career-concerns pattern but shrink toward zero in the best-measured seasons.
2. No robust post-renewal effect. The pooled negative coefficient is contradicted by within-season estimates and by the event-study path; it is best explained by mean reversion and cross-season composition shifts.
3. The RDD fails placebo diagnostics and raw means near the cutoff differ by ~0.08 in the opposite direction of the headline estimate (which is a local-slope extrapolation artifact with a 120-vs-906 support imbalance at the 30-day bandwidth).
4. A well-audited null on contract-timing incentives in the FotMob panel is the honest headline. Composition change across seasons (top-5-only in 2022/23-2023/24 vs ~40 leagues later) is the single largest threat to any pooled estimate in this design.

## Remaining Improvements

1. Finish the 2024/25 scrape for the ~31 non-top-5 leagues (in progress), then rebuild and rerun.
2. Scrape non-top-5 leagues for 2022/23 and 2023/24 (and 2021/22 if the endpoint allows).
3. Manual crosswalk review of the remaining ~640 ambiguous players (`data/crosswalk_manual_review_remaining.xlsx`).
4. Consider event-study specification around observed renewal dates to sharpen the post-renewal finding.
