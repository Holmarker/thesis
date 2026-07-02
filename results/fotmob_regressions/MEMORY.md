# FotMob Regressions Memory

This folder stores output tables for FotMob-based regression analyses related to Bosman, contract expiry timing, and contract renewal timing.

## Files in this folder

- `fotmob_regression_results.csv`
  - Main regression output table.
  - Columns: `model_name`, `sample_name`, `outcome_name`, `term`, `estimate`, `std_error`, `t_value`, `p_value`, `nobs`.
  - Includes results for:
    - `bosman_fe`
    - `expiry_bin_6m_fe`
    - `renewal_post_fe`
    - `renewal_signing_month_fe`
    - `renewal_event_6m_fe`

- `fotmob_expiry_6m_summary.csv`
  - Descriptive summary by 6-month expiry bins.
  - Columns: `sample_name`, `expiry_bin_6m`, `n_rows`, `n_players`, `mean_rating_raw`, `weighted_rating_raw`.
  - Contains both `source_league_strict` and `all_comps_strict` samples.

- `fotmob_renewal_6m_summary.csv`
  - Descriptive summary around renewal timing bins.
  - Columns: `sample_name`, `sign_bin_6m`, `n_rows`, `n_players`, `mean_rating_raw`, `weighted_rating_raw`.
  - Currently contains `all_comps_strict`.

## Sample sizes seen in results

- `source_league_strict`: `nobs = 29642`
- `all_comps_strict`: `nobs = 37511`
- Renewal/event sample: `nobs = 12965`

## Quick interpretation memory

- The Bosman indicator is not statistically significant in the reported FotMob models.
- Expiry-bin effects are mostly weak; the clearest negative result is `expiry_bin_6m::48+` for `all_comps_strict` with `fotmob_mean_rating`.
- Renewal-related post-signing effects are the strongest pattern in this folder, especially for minutes-weighted ratings.

## Intended use

Use this folder when writing up the FotMob regression section, checking descriptive patterns by contract timing, or validating whether renewal and expiry timing show meaningful performance differences.
