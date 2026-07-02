# FotMob Regressions Memory

This folder stores output tables for FotMob-based regression analyses related to Bosman, contract expiry timing, and contract renewal timing. Last regenerated 2026-07-02 on the rebuilt panel (full 2024/25 top-5 ratings + recovered crosswalk).

## Files in this folder

- `fotmob_regression_results.csv`
  - Main regression output (108 rows).
  - Columns: `model_name`, `sample_name`, `outcome_name`, `term`, `estimate`, `std_error`, `t_value`, `p_value`, `nobs`.
  - Models: `bosman_fe`, `expiry_bin_6m_fe`, `observed_renewal_status_fe`.
  - Outcomes: raw (`fotmob_mean_rating`, `fotmob_minutes_weighted_rating`) plus z-scores within league-season and league-month (`z_*_league_season`, `z_*_league_month`).

- `fotmob_heterogeneity_results.csv` / `fotmob_heterogeneity_subgroup_sizes.csv`
  - Same models run per subgroup: `age_group` (u23 / 23_28 / 29_plus), `position_group`, `squad_role` (starter vs rotation_bench via starts share), `league_tier` (top5 vs other).
  - Standardized outcomes only.

- `fotmob_expiry_6m_summary.csv`, `fotmob_observed_renewal_summary.csv` — descriptive summaries by expiry bin / renewal status.
- `fotmob_rdd_results.csv`, `fotmob_rdd_robustness.csv` — RDD at DaysToExpiry=180 plus placebo cutoffs/bandwidths.
- `fotmob_design_*.csv` — sample funnel, RDD support, near-cutoff balance.
- `coverage_diagnostics/` — crosswalk and merge coverage audits, incl. `crosswalk_recovery_summary.csv`.

## Sample sizes (strict panels, 2026-07-02)

- `all_comps_strict`: 59,306 rows / 5,412 players.
- `source_league_strict`: 50,889 rows / 5,060 players.
- 2024/2025 now covers Aug 2024 - Jun 2025 (top-5 leagues; other leagues pending scrape).

## Quick interpretation memory

- Pooled Bosman: null. Bosman x age: robust positive for u23 (+0.20 SD) and 23-28 (+0.13 SD), null for 29+ — the headline finding.
- Post-observed-renewal: -0.10 SD within player (p<0.0001), strongest for attackers and non-top-5 leagues. Descriptive (endogenous timing).
- 48+ expiry bin: negative, likely selection.
- RDD: fails placebo cutoffs (150/210 days significant); do not use causally.
- Raw vs standardized outcomes diverge — league composition matters; use `z_*_league_season` as preferred outcome.

## Intended use

Use when writing the FotMob regression / heterogeneity / RDD sections. Check SUMMARY.md for the current narrative and caveats (multiple testing, renewal endogeneity, crosswalk universe limitation).
