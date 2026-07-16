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

| D9 | Club friendlies (FotMob league_id 489, incl. "Hybrid Friendlies") excluded from all monthly aggregates (minutes, ratings, goals); rows retained in the archive file | Friendlies are not competitive club allocation: preseason line-ups are experimentation, not selection. 5,957 player-match rows; 2,432 player-months consisted of nothing but friendly/NT football and were wrongly coded as "played". Decided 2026-07-16, before any restricted estimation | No — definitional, quantified before any estimate was run on the restricted definition |

| D9b | All national-team football excluded from monthly aggregates: NT friendlies, World Cup qualifiers, continental tournaments, youth internationals (explicit 22-id list in `data/international_competition_ids.csv`, 21,562 rows incl. D9, + name-pattern fallback for future scrapes). FIFA **Club** World Cup kept (club competition). League matches untouched by construction (they carry the league's own id) | NT minutes are the national coach's allocation, not the club's; decided by author 2026-07-16 before any restricted estimation | No — definitional, quantified before estimation |

| D8 | Crosswalk verified on exact date of birth against a full FotMob DOB scrape (10,532 of 10,570 ids, 99.6%) | **Executed 2026-07-16.** Rules fixed and committed before the data existed (commit 0b1ee20). Results: 9,844 of 10,564 approved pairs verified (93%); **112 wrong-namesake pairs demoted** (birth years differ — generic-name collisions, e.g. Brazilian mononyms); 111 same-year DOB discrepancies kept as verified-with-flag (site data-entry differences); 21 unsafe conflicts resolved deterministically; **292 previously unmatched players rescued** (exact DOB + name >= 85 + two-way uniqueness); 37 pairs unverifiable (no DOB on one side, retained with flag). Net merge-safe: 9,667 -> ~9,868 | No — rules pre-committed; the same-year refinement was made after inspecting mismatch *composition* (name-identical small-gap pairs), not any regression |

## Specification freeze (2026-07-13) — **CONFIRMED by author 2026-07-16**, before the final estimation pass

- **Primary FE structure:** spell + league×month — chosen because the strategy
  chapter argues within-contract, within-league-time comparisons are the
  strictest available design. Chosen for that reason, not for its estimates.
- **Full grid always reported:** all four FE structures × both outcome
  definitions. No single-cell claims; fragility is reported as fragility.
- **Primary outcomes (AMENDED 2026-07-16, post-freeze — see D10):**
  intensive = monthly minutes-weighted rating; extensive = `played_fotmob` /
  `fotmob_minutes` on FotMob-covered league-months. Robustness: combined
  `played_any`/`minutes_any`, TM-only outcomes, unweighted and standardized
  rating variants.
- **Inference:** cluster by player (cluster robustness table as check).

## D10 — extensive-margin outcomes switched to FotMob-only (2026-07-16)

**Decision (data owner):** both margins are measured from FotMob alone;
extensive-margin outcomes are `played_fotmob` and `fotmob_minutes`, estimated
on FotMob-covered league-months. TM-based and combined outcomes remain in
every output as robustness rows.

**Result-independent rationale:** the TM appearance log comes from older
scrapes that sometimes crashed (owner statement, D6 addendum); it misses
22,429 player-months of verified play (coverage gaps); and it is not a single
consistent source across leagues and competitions. FotMob is one source, one
collection method, DOB-verified identities, with coverage that can be
delimited explicitly (covered league-months).

**Contamination flag — stated plainly:** this amendment was made AFTER the
frozen pass revealed that the three outcome definitions disagree (TM-only
+2.3pp, combined ~0, FotMob-only −0.8pp in the primary design). The
result-independent case for FotMob-only is genuine, but the timing is not
innocent. Mitigations: (i) all three definitions reported side by side in the
extensive-margin table, permanently; (ii) the thesis text must present the
extensive margin as measurement-bounded (0 to ≈−1pp), never as a robust
effect; (iii) supervisor to adjudicate the measurement question as promised
under D6.

## D11 — final_365 comparability variant (2026-07-16, post-freeze, flagged)

Added a final-contract-year (DaysToExpiry <= 365) treatment dummy to the
threshold models, in the naive and primary designs. Rationale: the
contract-year literature defines treatment as the final YEAR; comparability
required it. Flag: added after the frozen pass (result-independent rationale,
non-innocent timing — same protocol as D10). Result recorded in
RESULTS_NOTES.md regardless of direction: naive replicates the literature's
premium; the primary design reverses it (−0.03, p<0.001).

## Sample restrictions — DECIDED 2026-07-15, ex ante (no restricted estimates seen)

Decided by the author before any restricted-sample estimation was run. To be
applied in ONE final estimation pass, together with the DOB-verified crosswalk
(D8), under the frozen specification.

| # | Restriction | Decision | Rationale |
|---|-------------|----------|-----------|
| S1 | Drop 2021/22 (20 stray rows) | **Yes** | No rating coverage; noise |
| S2 | Drop the 8 never-rated leagues in all seasons | **Yes — primary for rating outcomes**; full league set retained for playing-time outcomes | Constant league composition across all four seasons |
| S3 | Minimum panel presence | **≥ 6 observed months per player** | Player FE needs within-variation; half a season |
| S4 | Age limits | **None** | Maximal sample; age-band heterogeneity results already locate where effects live; retirement margin kept as part of the story |
| S5 | Months-to-expiry support | **Trim to ≤ 48 (48+ binned)** for bins/splines/event studies | Thin, heavily selected support beyond 48 |
| S6 | Goalkeepers | **Included; by-position split reported** as measurement check | Player FE absorbs level differences; GK effort least event-visible — split shows it |
| S7 | Off-season months | **AMENDED 2026-07-16 (before any restricted estimation):** drop league-months in which the league played **zero league fixtures** (friendlies do not count), per a fixture calendar derived from the match data (`data/league_month_fixture_calendar.csv`); applied only within league-seasons that have fixture coverage; extensive-margin analyses only, rating outcomes unaffected | Original rule (drop June+July) assumed June-30 expiries; calendar-year leagues (Norway, Sweden, Brazil, Argentina: 77–96% December expiries) have opposite seasons, so June/July is their mid-season and Dec–Feb their true off-season. Denmark's long winter break (and the 2022 World Cup pause) defeat any fixed-month rule; an activity-share threshold fails too, since winter friendlies keep break months above any cutoff. Zero-league-fixtures is threshold-free and league-specific. Verified: removes all Danish Januaries + Dec 2022, keeps championship-round Junes. Amendment motivated by the expiry-month composition table, not by any estimate |
| S8 | Loan spells | **Deferred** | Needs transfer-event data (see open items) |

## Process rules

1. New decisions get a row here before the code changes.
2. Anything decided after seeing results is flagged in the last column.
3. The frozen specification is edited only with a dated entry explaining why.
