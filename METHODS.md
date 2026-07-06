# Empirical Methodology

Consolidated reference for every estimation choice in the thesis. Each section names the implementing script (all in `scripts/04_analysis/`, run from the repo root) and the output files (in `results/fotmob_regressions/` unless noted). Current results discussed in `results/fotmob_regressions/SUMMARY.md`; measurement diagnostics in `results/fotmob_descriptives/RATING_ANATOMY.md`.

## 1. Data structure

Player-month panel, ~159k observations (full panel) / ~71k with positive FotMob ratings (strict panel), seasons 2022/23-2025/26, ~36 leagues. Contract variables (expiry date, days to expiry, Bosman-window indicator) observed monthly from Transfermarkt snapshots; playing outcomes from Transfermarkt (all rows) and FotMob (covered league-months); performance ratings from FotMob match data aggregated to player-month.

Key timing conventions:
- All contract-status variables are **contemporaneous** (as observed at that month's snapshot); no future information enters any regressor (leakage audit: `results/fotmob_regressions/LEAKAGE_AUDIT.md`).
- Monthly snapshots imply up to one month of misclassification at contract transitions (e.g. a March 17 extension may register in March or April). This attenuates estimates toward zero; effects are lower bounds in this respect.
- Club financial variables are **season-lagged**: each season uses the financial year ending at its start. A previously significant result obtained under time-averaged (look-ahead) assignment did not survive this correction and is documented as a caution.

## 2. Outcomes

**Extensive margin** (primary): `played` (any TM minutes in the month), `Minutes_tm`, `Matches_tm` — fully observed for all player-months, no selection, no measurement formula.

**Intensive margin** (conditional on playing): FotMob monthly ratings. Because the raw rating is minutes-dependent, team-correlated, and shrunk toward its anchor for substitutes (see RATING_ANATOMY.md), results are estimated across a battery of outcome treatments:
- mean and minutes-weighted monthly rating;
- z-scores within league x season, league x month, and league x season x position;
- sub-shrinkage corrections (>=60-minute appearances only; minutes-bin rescaling);
- percentile ranks within league x month (immune to skew/outliers/shrinkage);
- regulars restriction (270+ minutes/month, where the mechanical minutes-rating gradient is flat).

No conclusion in the project depends on which treatment is used.

## 3. Fixed-effects structures

All main models are estimated under multiple FE structures (`fixest::feols`):

1. `player + month` — the naive baseline;
2. `player + league x month` — absorbs league-time composition shocks (the panel's league mix changes drastically across seasons);
3. `player x contract-spell + month` — within-spell identification: a spell is a run of months under one contract (spell breaks when the observed expiry date jumps > 90 days); within a spell, time-to-expiry advances deterministically, so expiry proximity is not a chosen state;
4. `spell + league x month` — the strictest general spec;
5. `spell + club x month` — compares a player to his own teammates in the same month, stripping the ~31% team component of ratings (clustered by club).

A result is treated as robust only if stable across structures. Scripts: `run_fotmob_spell_fe_regressions.R`, `run_fotmob_club_month_fe.R`.

## 4. Contract-cycle event study (main exhibit)

`run_fotmob_expiry_event_study.R`: outcomes on months-to-expiry dummies (24+ down to 0, reference 18), spell + league x month FE. Replaces an RDD (see §8). Robustness: quadratic age controls and age-at-spell-start splits (`_age.R` — a decline present for U24 players, for whom aging raises playing time, cannot be an aging artifact); active-league-months restriction (`_active_months.R` — 88% of month-0 observations are June; excluding low-activity league-months leaves the profile unchanged).

## 5. Selection into playing

Ratings exist only when a player plays, and playing responds to contract status — so intensive-margin estimates condition on an outcome of treatment. Addressed three ways:
- extensive-margin outcomes estimated directly on the full panel (`run_fotmob_selection_margin.R`);
- Lee (2009)-style trimming bounds on the Bosman rating gap (`run_fotmob_additional_robustness.R`): the over-observed control group is trimmed by the differential observation share within league-month cells; bounds span zero, so conditional rating data cannot sign the effect. Described as Lee-*style*: trimming within cells without player FE, an adaptation of the randomized-treatment original;
- interpretation discipline: the robust extensive-margin effect implies surviving players are positively selected, biasing conditional rating estimates upward.

## 6. Inference

- Standard errors clustered by player (default); two-way player x month and club-level clustering as robustness (`run_fotmob_additional_robustness.R`, club-month script).
- Multiple testing: Benjamini-Hochberg q-values within each model x outcome x term family across subgroups (`fotmob_heterogeneity_results.csv`, column `p_bh_within_family`).
- Minimum detectable effects reported alongside nulls (~2.8 x SE: 80% power, 5% two-sided). The headline intensive-margin null excludes effects larger than ~0.06-0.07 SD of within-league-season rating.
- Pre-declared tests for new hypotheses (e.g. the two continuous financial interactions in `run_fotmob_wage_continuous_tests.R`), reported regardless of outcome.

## 7. Robustness auditing (applied to every candidate finding)

1. **Season stability**: re-estimate within each season; pooled significance that vanishes in every season is treated as cross-season composition artifact (killed the Bosman x age gradient and the post-renewal decline; `run_fotmob_robustness_audit_bosman.R`, `_renewal.R`).
2. **Specification grid**: the FE structures of §3 (killed the 48+ months-to-expiry bin — contract sorting, not behavior).
3. **Placebo tests**: fake thresholds/timing (killed the RDD).
4. **Event-time inspection**: raw event paths against pooled coefficients (exposed mean reversion in the renewal result).
5. **Correct temporal assignment**: no look-ahead in conditioning variables (killed the wages-to-revenue tercile gradient).

## 8. Rejected designs (kept as negative exhibits)

- **RDD at 180 days to expiry**: monthly running variable gives no within-bandwidth support (120 vs 906 observations at bw=30); the headline estimate (+19.3 on a 0-10 scale) is a slope-extrapolation artifact opposite in sign to the raw means gap (0.08); placebo cutoffs at 150/210 days fire; near-cutoff covariate balance fails; and no discontinuous treatment exists at the legal threshold (eligibility is perfectly anticipated). Scripts: `run_fotmob_rdd.R`, `run_fotmob_rdd_robustness.R`, `run_fotmob_design_diagnostics.R`.
- **Naive TWFE renewal dummy**: contradicted by within-season estimates and the event path (mean reversion). A staggered-adoption estimator (Sun-Abraham / Callaway-Sant'Anna) is the correct formalization; noted as an extension rather than implemented.

## 9. Data-construction choices that matter

- FotMob-Transfermarkt crosswalk: only merge-safe (uniquely matched) player pairs enter; recovery rules (age+nationality uniqueness, exact name + club with a learned club-alias table) documented in `data/` and `coverage_diagnostics/`. ~6,300 rated FotMob players have no Transfermarkt counterpart (universe limitation, stated, not fixable).
- Ratings validity rule: (0, 10] enforced at cleaning (one extra-time glitch observed).
- Club financials matched by normalized name within league; terciles league-relative and league-specific (promoted/relegated clubs are classified relative to the league they play in).

## 10. Summary of the identification stance

No experiment exists here. The design philosophy is: (i) prefer outcomes that are fully observed (playing) over selected, formula-mediated ones (ratings); (ii) identify from within-contract time variation with league-time and teammate comparisons; (iii) subject every candidate effect to audits designed to destroy it; (iv) report nulls with power and bounds. The surviving claims are deliberately modest: playing time declines smoothly and substantially over the contract cycle in every specification; per-minute performance shows no detectable change, and given the selection structure, could not have been credibly signed from this data anyway.
