# Anatomy of the FotMob Match Rating

Measurement diagnostics for the FotMob player match rating, the main performance outcome in this thesis. All numbers are reproduced by `scripts/04_analysis/run_fotmob_rating_anatomy.R`; the underlying tables live in `rating_anatomy/`. Based on ~337k rated player-matches across ~40 leagues, 2022-2026 (numbers cited below from the 2026-07-02 run; they update at each rebuild).

## Headline: what a rating is made of

An OLS decomposition of the match rating (`r2_ladder.csv`, `full_model_coefficients.csv`):

| ingredients | R² |
|---|---|
| minutes played | 0.15 |
| goals + assists | 0.31 |
| minutes + goals + assists | 0.43 |
| + cards + home | 0.45 |
| + teammates' average rating that match | 0.55 |

Implied price list (full model): **a goal = +0.93, an assist = +0.77, a red card = -1.03, a full 90 minutes = +0.90** (0.010 per minute), yellow card = -0.02, home advantage = +0.02, and a 0.62 pass-through from the teammates' average that day.

Roughly: **~45% scoreboard events + minutes, ~10% the team's day, ~45% residual** (finer positional events + noise).

## The scale

Mean 6.86, sd 0.79, effective range ~5.8-8.2 (p5-p95), 0.1 granularity, no bunching at bounds (2 observations at exactly 10.0). One out-of-range value (12.6, an extra-time source glitch) motivated the 0-10 validity rule now in `clean_fotmob_ratings.R`.

## Noise dominates signal

Among players with 5+ matches: within-player match-to-match sd is **0.74**, while the between-player sd of career means is only **0.31** (`variance_decomposition.csv`). A single match rating is mostly noise about the player; a monthly average of ~4 matches is roughly 40% signal.

## A third of the rating is the team, not the player

~31% of match-level rating variance sits at the team-match level (`team_comovement.csv`): teammates' ratings co-move because results, goals conceded, and match dominance enter everyone's rating. The same share (~32%) holds for player-season means within team-season. Consequence: ratings partially measure *team* quality; comparisons should difference out team-time (club x month FE) and errors are correlated within teams.

## The rating is a different instrument per position

(`position_decomposition.csv`)

| position | R² full | R² goals+assists only | team pass-through |
|---|---|---|---|
| attackers | 0.75 | 0.64 | 0.35 |
| midfielders | 0.64 | 0.41 | 0.48 |
| defenders | 0.48 | 0.17 | 0.73 |
| keepers | 0.23 | 0.01 | 1.10 |

Attacker ratings are largely goal involvement restated; keeper ratings are mostly team outcome (pass-through above one: conceding hurts the keeper and all teammates simultaneously) plus unobserved save events. Any pooled rating analysis mixes fundamentally different measures - hence standardization within league x season x position.

## Minutes buy rating points - even when nothing happens

In **event-free** matches (no goals, assists, or cards; 74% of all observations), the *same player* rates ~0.80 higher per 90 minutes played (player FE; `eventfree_minutes_effect.csv`). Among starters only, being left on until 90 rather than subbed at 60 is worth +0.41. Two channels, indistinguishable without event data: mechanical accumulation of micro-events (passes, duels), and reverse causality via substitutions (struggling players get pulled early - minutes encode the coach's live assessment).

## Sub ratings are shrunk priors, not measurements

(`minutes_gradient_shrinkage.csv`)

| minutes | mean | sd | share < 5.5 | share > 7.5 |
|---|---|---|---|---|
| 0-14 | 6.24 | 0.37 | 0.8% | 0.6% |
| 45-59 | 6.50 | 0.61 | 2.5% | 5.6% |
| 90+ | 7.09 | 0.83 | 3.2% | 28.5% |

A short cameo is near-guaranteed a rating in [5.5, 7.5]: not enough events accumulate to move away from the ~6.2 anchor in either direction. Bad sub appearances are rated too kindly, brilliant ones too stingily. For low-minute players the outcome has mechanically compressed variance, attenuating any estimated effect for bench/marginal players.

## Responses to the sub-shrinkage problem

Two corrected outcomes were built and re-tested (`run_fotmob_sub_adjusted_ratings.R`, `../fotmob_regressions/fotmob_sub_adjusted_rating_results.csv`): a monthly rating from >=60-minute appearances only, and match ratings z-scored within minutes-bin x league-season before aggregation. Both show the familiar signature - small positives under naive player+month FE (p ~ 0.02) that vanish under spell FE and are near-exact zeros within club-month (-0.006 / -0.005, p ~ 0.85). Correcting the shrinkage sharpens the null rather than revealing an effect. (The shrinkage itself cannot be "undone": a 10-minute cameo contains little information; one can only exclude, rescale, or down-weight it.)

## Consequences for the thesis design

1. **Minutes-weighted rating** is preferred over the plain mean (correlation with monthly minutes 0.20 vs 0.37), and the mechanical gradient is flat above ~270 minutes/month - motivating the regulars restriction.
2. **Standardize within league x season (x position)**; raw cross-league scale differences are small (6.77-6.93) but composition differences are not.
3. **Club x month FE** strip the ~31% team component: compare a player to his own teammates.
4. **The extensive margin (playing at all, minutes) is the more reliable outcome**: fully observed, no shrinkage, no formula - and it is where the robust contract-cycle effect lives (see `../fotmob_regressions/SUMMARY.md`).
5. Rating-based nulls should be stated with their power (MDE ~0.07 SD) and their selection bounds (Lee bounds span zero), not as evidence of absence of subtle effects: the individually-attributable signal in the rating is thin, especially for defenders and keepers.
