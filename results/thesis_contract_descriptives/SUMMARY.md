# Contract-Cycle Descriptives

Motivational descriptives for the thesis, produced by `scripts/04_analysis/run_thesis_contract_descriptives.R` from the full all-comps panel (numbers from the 2026-07-07 run; regenerate after data merges).

## Contract outcome funnel (`contract_outcome_funnel.csv`)

Of 3,074 contracts observed entering their final 12 months (expiry within the panel window):

- **44% renewed** before expiry.
- **20% transferred** to another club before expiry.
- **19% exit the panel at expiry** (retirement, move outside covered universe, or attrition).
- **17% observed after expiry at a new club / as free agents.**

The Bosman margin is real and common: over a third of final-year contracts end with the player leaving at or after expiry.

## Raw playing profile (`raw_playing_by_months_to_expiry.csv/png`)

Unadjusted share of player-months with any minutes: 0.73 at 18 months to expiry, 0.69 at 6 months, **0.21 in the expiry month**. The raw decline is visible without any controls; the event study (spell + league-month FE) shows the same shape survives identification (and the month-0 figure is partly the June off-season, handled there).

## Renewal timing (`renewal_timing_months_left.csv/png`)

**49% of extensions are signed within the final 12 months** of the old contract; the mass rises steadily as expiry approaches (with a local spike around 2-4 months left). Renewal is a late decision — exactly why post-renewal comparisons are endogenous.

## Expiry-date clustering (`expiry_month_clustering.csv`)

**89.5% of contracts expire in June; 8.1% in December** (calendar-year leagues). This motivates (a) the June/month-0 robustness treatment in the event study and (b) why an RDD in days-to-expiry has degenerate support.

## Contract length at signing by age (`contract_length_at_signing_by_age.csv`)

Monotone sorting: mean new-contract length falls from **3.8 years for players 21 and under to 1.3 years for 34+**. Contract length is chosen, and chosen differently by age - the direct motivation for identifying within contract spells rather than across them.

## League x season rating coverage (`league_season_rating_coverage.csv`)

Rated player-months by league and season: full grid for 2024/25-2025/26, top-5-only for 2022/23-2023/24. The honest map of where the intensive-margin evidence comes from.

## Treatment/control composition by position and age (`treatment_control_composition*.csv`)

Bosman-window vs outside-window player-months:

- **Age composition differs drastically**: players 31+ make up 30.8% of the Bosman group but only 10.3% of the control group; players 24 and under are 27.9% vs 49.2%. Short remaining contracts are an old-player state - the single clearest illustration of why pooled Bosman comparisons are confounded by age/composition and why the audits and spell FE matter.
- **Position composition differs mildly** (slightly fewer attackers, slightly more keepers in the Bosman window).
- **The playing gap appears within every cell**: roughly 10-20pp lower playing share for the Bosman group within each position and each age band - the extensive-margin effect is not a composition artifact.
- **Raw ratings conditional on playing are near-identical in every cell** (max gap 0.18, typically <0.05): the intensive-margin null, visible cell by cell without any regression.
