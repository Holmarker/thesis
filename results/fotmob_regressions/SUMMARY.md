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

Multiple-testing caveat: with ~11 subgroups per hypothesis, isolated `p < 0.05` cells are expected by chance. `fotmob_heterogeneity_results.csv` now carries Benjamini-Hochberg adjusted q-values (`p_bh_within_family`, adjusted across subgroups within each model x outcome x term family). Several age-group cells survive BH — but BH does not repair the season-stability failure; pooled significance that vanishes within every season should be treated as an artifact of composition shifts across seasons (the panel's league mix changes drastically from 2022/23 to 2025/26).

## Specification Robustness: Contract-Spell and League-Month FE

`run_fotmob_spell_fe_regressions.R` re-estimates the Bosman and expiry-bin models under four FE structures (`fotmob_spell_fe_results.csv`): the baseline `player + Month`, `player + league x Month` (absorbs league-time composition), `player-contract-spell + Month` (within-spell identification: expiry approaches deterministically with time), and `spell + league x Month`. Identification is real: 2,082 of 5,412 players have multiple observed contract spells (7,901 spells).

- Bosman (all-comps, z league-season): `+0.031` (player+month), `+0.041` (player+league-month), `-0.077` (spell+month, `p = 0.004`), `-0.038` (spell+league-month, `p = 0.16`). The sign is not even stable across FE structures — no defensible Bosman effect.
- `48+` expiry bin: `-0.09` to `-0.11` and significant under player FE, but insignificant and sign-unstable under spell FE — confirming the earlier suspicion that the 48+ result reflects sorting across contracts, not within-contract behavior.
- Minimum detectable effect (80% power, 5% two-sided) for the Bosman coefficient is ~0.07 SD in all specifications: the null is informative — effects larger than ~0.07 SD of within-league-season rating are ruled out with good power.

## Additional Robustness (two-way clustering, position standardization, Lee bounds)

`run_fotmob_additional_robustness.R` (`fotmob_additional_robustness.csv`):

- Two-way clustering (player and month) leaves the Bosman rating null unchanged in both FE structures.
- Standardizing ratings within league x season x position group (keepers vs outfield) changes nothing (`+0.024` / `-0.042`, both insignificant).
- Lee-style trimming bounds: because Bosman players play ~5pp less, the conditional-on-playing comparison is selected. Trimming the over-observed control group by the differential observation share bounds the Bosman rating gap at roughly `[-0.31, +0.19]` SD around the untrimmed `-0.02`. The bounds comfortably include zero: given the extensive-margin selection, the conditional rating data cannot even sign a Bosman performance effect — reinforcing that the extensive margin is where the identifiable action is.

## Rating Measurement Properties and Club-Month FE

Full measurement diagnostics are consolidated in `../fotmob_descriptives/RATING_ANATOMY.md` (reproducible via `run_fotmob_rating_anatomy.R`). Diagnostics on the rating variable itself (match level, n=336,797): mean 6.86, sd 0.79, 0.1 granularity; a goal is worth ~+1.1; ratings rise mechanically with minutes played (6.24 below 15 minutes vs 7.09 for full matches — the monthly mean rating correlates 0.37 with monthly minutes, the minutes-weighted version 0.20, flat above ~270 min/month). Within-player match-to-match sd (0.74) is more than twice the between-player sd of averages (0.31): a single match rating is mostly noise. About 31% of match-level rating variance sits at the team-match level (ratings co-move with team results), similarly 32% at team-season level. One out-of-range rating (12.6, extra-time glitch) led to a 0-10 validity rule in the cleaning step.

`run_fotmob_club_month_fe.R` (`fotmob_club_month_fe_results.csv`) therefore compares players to their own teammates (club x month FE, spell FE, clustered by club):

- Playing: `-2.4pp` (`p = 0.0002`); minutes: `-5.3` (`p = 0.04`) — the extensive-margin effect survives the within-teammates comparison.
- Mean rating: marginal `-0.064` (`p = 0.04`), but this is the mechanical minutes channel: the minutes-weighted rating is null (`-0.017`, `p = 0.51`) and both are null among regulars with 270+ minutes (`p = 0.20` / `p = 0.38`), where the minutes-rating gradient is flat.

## Selection Into Playing (Extensive Margin)

`run_fotmob_selection_margin.R` estimates whether contract status predicts playing itself, on the FULL panels (152,817 player-months) with always-observed Transfermarkt outcomes (`fotmob_selection_margin_results.csv`).

The one result that survives all four FE structures:

- Bosman-window players are 4.4-6.6pp less likely to play at all (`played_tm`), with fewer matches and minutes; significant in every spec including spell + league x month (`-4.6pp`, `p = 0.0003`).
- The `0:6` months-to-expiry bin is stronger still: `-18.8pp` playing probability in the strictest spec (`p < 0.0001`).
- Within FotMob-covered league-months, conditional playing probability shows no effect — consistent with the TM effect operating at the squad-role level.

Implications: (1) the rating regressions condition on playing, and playing is where the contract-status action is — surviving players are positively selected, so intensive-margin rating estimates are upward-biased for any true negative effect; (2) the defensible substantive finding of the panel is "no detectable intensive-margin performance effect (MDE ~0.07 SD), but a robust extensive-margin reduction in playing time as contracts run down."

Caveats: part of the extensive-margin effect may be mechanical — mid-season transfer timing (expiry proximity peaks before January moves), injuries running contracts down, or clubs protecting sale value. Distinguishing these channels requires transfer-event data.

## Contract-Cycle Event Study (replaces the RDD as the main exhibit)

`run_fotmob_expiry_event_study.R` estimates outcomes as a function of months-to-expiry (24+ down to 0, reference 18 months), within player x contract spell with league x month FE (primary) and player + month FE (comparison). Results in `fotmob_expiry_event_study.csv`, figure in `fotmob_expiry_event_study.png`.

- Playing probability and minutes decline smoothly and monotonically from roughly 12 months before expiry, reaching about -25pp playing probability and -70 minutes/month in the expiry month (primary spec).
- There is no jump at the 6-month Bosman threshold: the decline is a smooth ramp through it. This is direct evidence for why the RDD finds nothing real at 180 days — the theory-consistent pattern is anticipatory and continuous, not discontinuous.
- Standardized rating conditional on playing is flat across the entire contract cycle in the primary spec (CIs straddle zero everywhere): the intensive-margin null, shown rather than asserted.
- Both FE structures agree qualitatively.
- Age robustness (`run_fotmob_expiry_event_study_age.R`, `fotmob_expiry_event_study_age.png`): the profile is unchanged by quadratic age controls, and the decline is equally present for players under 24 at spell start — for whom aging raises playing time — so the contract-cycle decline cannot be an aging artifact.
- Off-season robustness (`run_fotmob_expiry_event_study_active_months.R`): 88% of month-0 observations fall in June, raising a mechanical no-games concern; but the league x month FE compare expiring players to same-league-same-month peers, and restricting to active league-months (>=25% of players with minutes) leaves the profile unchanged (month 0: -0.261 vs -0.255; month 6: -0.071 vs -0.069).
- Transfer-window timing: ratings show no Bosman x pre-window interaction (p = 0.86); the playing-time penalty deepens marginally before windows (-1.6pp, p = 0.056), weakly consistent with a departure-anticipation channel.

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
