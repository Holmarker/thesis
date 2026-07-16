# Results notes — frozen pass (2026-07-16, commit be86ec1 + D10)

Observations to carry into the Results rewrite. Numbers are final unless a
logged decision changes them.

## Intensive margin (standardized rating, all_comps_strict)

Primary design = spell + league×month. Six variants:

| Variant | b | p |
|---|---|---|
| No controls | −0.020 | 0.105 |
| Minute-weighted | −0.013 | 0.25 |
| + win share | **−0.026** | **0.030** |
| + win share, weighted | −0.018 | 0.096 |
| + events | −0.018 | 0.075 |
| + events, weighted | −0.012 | 0.20 |

- Ladder: naive player+month = +0.025 (p=0.02) → league×month kills it
  (+0.001) → spell designs mildly negative.
- **Win-share observation:** the control most justified by the measurement
  (rating loads on team results) makes the primary estimate MORE negative and
  significant (−0.026, p=0.03). Direction: conditional on team results,
  near-expiry ratings are slightly worse. Write as "if anything slightly
  negative; the range across variants is −0.012 to −0.026; one of six crosses
  5% — consistent with a small negative, never with the contract-year premium."
  Do NOT headline the single significant cell (anti-overclaim).
- MDE (80% power) in primary cell ≈ 0.034 SD — the precision claim.

## Extensive margin (D10: FotMob-only primary, covered league-months)

| Outcome | b | p |
|---|---|---|
| played_fotmob (primary) | −0.008 | 0.031 |
| fotmob_minutes (primary) | −5.7 | 0.0015 |
| played_any (combined) | −0.002 | 0.60 |
| played_tm (TM-only) | +0.023 | <0.0001 |
| club×month FE (within teammates), played | +0.012 | 0.013 |

- Present as measurement-bounded: 0 to ≈ −1pp / −6 min. TM-only sign-flip is
  the permanent cautionary exhibit (coverage artifact). Within-teammates
  comparison does NOT corroborate the decline → another reason for "bounded,
  not robust".

## Threshold / functional form

- final_180 dummy (player+month): +0.017 (p=0.009) — same naive-spec premium.
- Expiry windows (ref 181–360): 0–180 = +0.010 (p=0.16); 361–720 ≈ 0;
  721+ = −0.029 (p<0.001) — the long-contract dip is the biggest feature,
  consistent with post-signing/selection, mean-reversion caveat (Krautmann)
  applies.
- **final_365 ("final contract year", the literature's treatment definition;
  added post-freeze as a flagged comparability variant, logged):**
  - player+month (naive): +0.016 to +0.020, p<0.02 — replicates the published
    contract-year premium almost exactly.
  - spell+league×month (primary): **−0.031 (source, p=0.0001) / −0.025
    (all comps, p=0.0009)** — significantly NEGATIVE.
  - Third independent strict-design negative (with win-control −0.026 and the
    721+ dip). The story firms from "null" toward "no premium; a small
    conditional DECLINE in the final year, ~0.03 rating points (~4% of
    within-player SD)".
  - Cautions before headlining: post-freeze variant (flagged); identification
    needs spells observed >1 year (composition of long spells); direction
    consistent with turmoil/mean-reversion as well as effort. Frame as: "the
    contract-year premium is not merely absent — under the literature's own
    definition and this design, the point estimate is significantly negative."

## Inference

- Cluster: player (primary). Robustness: club and player×club two-way —
  SEs 0.0120 / 0.0129 / 0.0127 in the primary cell; nothing hangs on it.

## Standing language rules (from LITERATURE.md anti-overclaim notes)

- "at most a small decline", "measurement-bounded", "event-visible
  performance", name Krautmann for the 721+ dip.
