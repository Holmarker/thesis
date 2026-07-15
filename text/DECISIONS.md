# Decisions log

Every non-obvious data or specification decision, with its motivation and date.
Rule: decisions are motivated by *measurement facts or design principles*, never
by the coefficients they produce. When a decision was made after seeing results,
that is flagged honestly.

## Data construction (2026-07-13)

**Status: D1–D6 are all implemented and executed.** Full rebuild ran 2026-07-13
(clean 14:04 → masters 14:43 → panels 15:16 → regressions 15:17, plus the
18-script audit battery). Verification: clean file 1.74M rows / 0 malformed
lines / 0 duplicate player-matches / max match minutes 120; season funnel
matches the per-league scrape manifests (22/23: 46.5k monthly rows, 23/24:
51.4k). Commits `ad57183`, `8edab09`.

| # | Decision | Motivation | Result-contaminated? |
|---|----------|-----------|---------------------|
| D1 | Rebuild `fotmob_ratings_clean.csv` with a reader that does not truncate on raw non-ASCII bytes | `read.csv(fileEncoding="UTF-8")` silently dropped every row after the first raw byte in a file (~500k rows lost; English Championship 22/23 kept 203 of 17,788 rows). Verified against per-league scrape manifests. | No — acceptance test is row counts vs manifests, not regressions |
| D2 | One row per player-match; prefer source-league copy, then rows with a rating, then most minutes | Players scraped under two source leagues (mid-season transfers) carried the same match twice, double-counting minutes/goals (~15k player-matches, exactly 180 min/match artifacts) | No — duplication is a fact independent of outcomes |
| D3 | Per-match minutes > 120 set to missing | A football match cannot exceed ~120 minutes. Affects 12 of 2.1M raw rows (0.0006%): 11 from a single glitched FotMob match record (Lillestrøm–Kristiansund cup, 2025-07-09, values 4,025–4,926) plus one 135-minute entry (LaLiga2, possibly genuine ET+stoppage) | No |
| D4 | Ratings outside (0,10] set to missing; the row (appearance, minutes) is kept | Rating 0 is FotMob's "no rating assigned" code (228,142 rows, short cameos), not a performance score; 1 row exceeds 10; 480,833 rows have no rating field. Dropping whole rows would delete ~709k real appearances and recreate false zeros on the playing-time margin | No (pre-existing rule; counts documented 2026-07-13) |
| D5 | Crosswalk joined on player ID only, not player×league | The crosswalk's league is metadata from the matching season, not an identity key; joining on it dropped all months a player spent in another covered league. Same fix as commit 0ef70ff for the incremental path. | No — but note it changed the panel by +14k player-months |
| D6 | Extensive-margin outcomes `played_any` / `minutes_any` (TM **or** FotMob evidence); TM-only kept as robustness | 22,429 panel months have FotMob minutes > 0 but TM minutes = 0: the TM appearance log does not cover all competitions, so TM-only coding creates false zeros concentrated near contract transitions. **Addendum 2026-07-13 (data owner):** the TM appearance data comes from older scrapes that sometimes crashed mid-run, so TM zeros are unreliable for a second, result-independent reason; FotMob minutes are the more trustworthy playing-time source where the two disagree. `minutes_any = max(TM, FotMob)` is robust to TM undercounting from either cause | **Partly.** The 22k-gap fact was found after observing that D5 flipped the TM-only coefficient; the scrape-reliability rationale is prior operator knowledge, independent of any result. Mitigation: both definitions reported; supervisor to bless the definition without seeing the grid |

| D7 | Monthly source-league label = league of the month's actual source-league matches (fallback: first observed) | `first(source_league_name)` after an alphabetical sort could label a month with a stale roster tag (e.g. a Rangers month labeled Argentine Primera via a cup row), corrupting league×month FE cells and league standardization. Impact: 2,052 of 529k months relabeled (0.39%); full grid re-estimated, all conclusions unchanged (third-decimal movements) | No — labeling correctness, independent of outcomes |

## Specification freeze (2026-07-13) — TO BE CONFIRMED before further estimation

- **Primary FE structure:** spell + league×month — chosen because the strategy
  chapter argues within-contract, within-league-time comparisons are the
  strictest available design. Chosen for that reason, not for its estimates.
- **Full grid always reported:** all four FE structures × both outcome
  definitions. No single-cell claims; fragility is reported as fragility.
- **Primary outcomes:** intensive = monthly minutes-weighted rating;
  extensive = `played_any`. Robustness: unweighted rating, standardized
  variants, TM-only outcomes, drop-gap sample.
- **Inference:** cluster by player (cluster robustness table as check).

## Sample restrictions — OPEN, decide ex ante (proposals, not yet applied)

The current estimation sample is essentially unrestricted. Each restriction
below is proposed on design grounds; none has been run. Decide, log, then run
ONCE.

| # | Proposed restriction | Rationale | Recommendation |
|---|---------------------|-----------|----------------|
| S1 | Drop 2021/22 (20 stray rows) | No rating coverage; noise | Yes |
| S2 | Drop the 8 never-rated leagues in all seasons (rating outcomes) | Constant league composition; already standard in the excl-8 runs | Yes, as primary for rating outcomes |
| S3 | Require ≥ 6 observed months per player | FE with 1–2 months contributes nothing but noise; standard panel practice | Yes |
| S4 | Drop player-months after age 36 / before age 17 | Retirement/youth dynamics are different processes | Discuss |
| S5 | Trim months-to-expiry > 48 into a 48+ bin (already done in bins); restrict spline/event-study support to ≤ 48 | Thin, heavily selected support | Yes |
| S6 | Goalkeepers: report separately or exclude from rating outcomes | Rating algorithm treats GKs differently; position-standardized outcomes partly handle this | Discuss |
| S7 | June/July months in extensive-margin outcomes | Off-season months mechanically have no matches; month FE absorb league-wide timing but not player-specific off-season exposure near June-30 expiries | Discuss — this interacts directly with expiry clustering and could matter; must be decided BEFORE seeing what it does |
| S8 | Loan spells | Loans change who controls playing time; currently indistinguishable from permanent deals without transfer data | Defer (needs transfer histories) |

## Process rules

1. New decisions get a row here before the code changes.
2. Anything decided after seeing results is flagged in the last column.
3. The frozen specification is edited only with a dated entry explaining why.
