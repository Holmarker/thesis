# Results notes — frozen pass (2026-07-16, commit be86ec1 + D10/D11)

Observations to carry into the Results rewrite. Numbers are final unless a
logged decision changes them. Stars: * p<0.05, ** p<0.01, *** p<0.001.

## Intensive margin (standardized rating, all_comps_strict)

The ladder (no controls, N = 142,722 throughout):

| Design | b | p |
|---|---|---|
| Player + month | +0.025* | 0.022 |
| Player + league×month | +0.001 | 0.95 |
| Spell + month | −0.017 | 0.17 |
| **Spell + league×month (primary)** | −0.020 | 0.105 |

Primary design, six variants (N = 142,722):

| Variant | b | p |
|---|---|---|
| No controls | −0.020 | 0.105 |
| Minute-weighted | −0.013 | 0.25 |
| + win share | **−0.026*** | 0.030 |
| + win share, weighted | −0.018 | 0.096 |
| + events | −0.018 | 0.075 |
| + events, weighted | −0.012 | 0.20 |

- **Win-share observation:** the control most justified by the measurement
  (rating loads on team results) makes the primary estimate MORE negative and
  significant (−0.026*, p=0.03). Direction: conditional on team results,
  near-expiry ratings are slightly worse. Write as "if anything slightly
  negative; the range across variants is −0.012 to −0.026; one of six crosses
  5% — consistent with a small negative, never with the contract-year premium."
  Do NOT headline the single significant cell (anti-overclaim).
- MDE (80% power) in primary cell ≈ 0.034 SD — the precision claim.

## Extensive margin (D10: FotMob-only primary, covered league-months)

All spell + league×month:

| Outcome | b | p | N |
|---|---|---|---|
| played_fotmob (primary) | **−0.8pp*** | 0.031 | 168,823 |
| fotmob_minutes (primary) | **−5.7**\*\* | 0.0015 | 168,823 |
| played_any (combined) | −0.2pp | 0.60 | 207,308 |
| played_tm (TM-only) | +2.3pp*** | <0.0001 | 207,308 |
| club×month FE (within teammates), played | +1.2pp* | 0.013 | 212,047 |
| club×month FE, minutes | +0.5 | 0.82 | 212,047 |

- Present as measurement-bounded: 0 to ≈ −1pp / −6 min. TM-only sign-flip is
  the permanent cautionary exhibit (coverage artifact). Within-teammates
  comparison does NOT corroborate the decline (positive, different sample and
  outcome base) → another reason for "bounded, not robust".

## Threshold / functional form (raw ratings, player+month unless noted)

| Model | b | p | N |
|---|---|---|---|
| final_180, mean rating (source) | +0.018** | 0.006 | 145,599 |
| final_180, weighted (source) | +0.017** | 0.009 | 145,576 |
| final_365, mean rating (source) | +0.016** | 0.007 | ~145,600 |
| final_365, mean rating (all comps) | +0.020*** | 0.0006 | ~149,000 |
| expiry window 0–180 (ref 181–360) | +0.010 | 0.16 | 145,599 |
| expiry window 721+ | **−0.029***\* | <0.001 | 145,599 |
| **final_365, spell+league×month (source)** | **−0.031***\* | 0.0001 | ~139,700 |
| **final_365, spell+league×month (all comps)** | **−0.025***\* | 0.0009 | ~142,700 |

- **final_365 is the literature's treatment definition** (added post-freeze as
  flagged comparability variant, D11): the naive design replicates the
  published premium almost exactly; the primary design REVERSES it into a
  significant decline.
- Third independent strict-design negative (win-control −0.026, the 721+ dip,
  final_365). Story firms from "null" toward "no premium; a small conditional
  DECLINE in the final year, ~0.03 rating points (~4% of within-player SD)".
- Cautions before headlining: post-freeze variant (flagged, D11);
  identification needs spells observed >1 year (composition of long spells);
  direction consistent with turmoil/insecurity (Roderick, Sverke) and
  mean-reversion (Krautmann) as well as effort. Frame as: "the contract-year
  premium is not merely absent — under the literature's own definition and
  this design, the point estimate is significantly negative."

## Inference

- Cluster: player (primary). Robustness in primary cell: player SE 0.0120,
  club 0.0129, player×club two-way 0.0127 — nothing hangs on the choice.

## Standing language rules (from LITERATURE.md anti-overclaim notes)

- "at most a small decline", "measurement-bounded", "event-visible
  performance", name Krautmann for the 721+ dip; the extensive margin is
  never "robust"; single significant cells are ranges, not headlines.
