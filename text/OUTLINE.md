# Thesis outline & progress

> Companion docs: [DECISIONS.md](DECISIONS.md) (data/spec decisions log — read
> before changing any definition) · [LITERATURE.md](LITERATURE.md)

Status legend: `todo` · `skeleton` (headers/notes only) · `draft` (full text, unpolished) · `revised` (edited once) · `final`

## Headline (SETTLED 2026-07-15)

*A well-audited null on the performance margin — naive specs reproduce the
literature's contract-year premium, the audit ladder (league×month, spell FE)
dismantles it — plus a small surviving decline in playing probability. The
contrast with Frick's (2011) positive journalist-rating result suggests
narrative in the rater, not effort on the pitch. The decisions log / ex-ante
freeze is a methodological contribution in its own right.*

## Manuscript

| # | Section | Status | Notes |
|---|---------|--------|-------|
| 0 | Abstract | skeleton | Write last |
| 1 | Introduction | **draft** | 5-paragraph arc drafted 2026-07-15; §3 numbers await final pass; commits thesis to DECISIONS appendix |
| 2 | Literature Review | draft | Holmström/Lazear–Rosen in place; "This paper ..." placeholder; needs contract-year empirics paragraph (Frick 2011, Stiroh, Krautmann, AEL 2026) and non-sports analogues (see LITERATURE.md arc) |
| 3 | Background | draft | Labor market, Bosman, FotMob subsections; user-authored, needs one polish pass |
| 4 | Data | **revised** | Rewritten 2026-07-13: sources / cleaning+aggregation (D2–D4 documented) / linkage / temporal alignment / panel + macros / descriptives. TODO: soften "TM defines playing time for full universe" (D6 addendum); disclose TM coverage gap; add DOB-verification sentence after D8 |
| 5 | Empirical strategy | revised | Effort model (FOC → predictions → estimand → selection expectation) added 2026-07-13; threats rewrite done. TODO: one paragraph on the flexible duration profile (spline) if adopted |
| 6 | Results | **stale** | All numbers predate the final pass. Rewrite around the audit-ladder arc after final estimation. Subsections: descriptives / intensive (null + ladder) / what the rating measures / extensive (played_any grid, honest fragility) / event study / rejected designs / heterogeneity / synthesis |
| 7 | Discussion | skeleton+ | FotMob subsection **drafted** (6 arguments, [NUMBER] placeholders); injury selection = rough user notes needing rewrite; mechanical-selection/transfers, term-limits external validity, limitations = stubs |
| 8 | Conclusion | skeleton | Header + TODO |
| A–D | Appendix | skeleton | A descriptives · B event-study/robustness detail · C rejected RDD · D data construction. **Add E: decisions log** (promised by the Introduction) |

## Critical path (in order)

1. ⏳ **DOB scrape** running (~25% at last check) → **D8 verification** (script ready, dry-run tested; review mismatch count before `apply`)
2. **Final estimation pass** under frozen spec: rebuild with verified crosswalk → full chain + audit battery (restrictions already wired in). ONE run.
3. **Fill numbers**: `% [NUMBER]` markers in Introduction + FotMob discussion; MDE calc; rating-anatomy R²; regenerate tables/numbers.tex
4. **Rewrite Results** (§6) around the ladder arc; update synthesis
5. **Write Discussion** subsections (mechanical selection, term limits, limitations, injury rewrite)
6. **Lit review completion** (contract-year empirics + analogues paragraphs)
7. **Conclusion, Abstract, polish** (\\ → blank lines, plain-text cites → \citep, standalone .tex files deleted or \input'd)

## Blocked / deferred

- Transfer/terminal-outcome analysis (S8, threat 2) — needs transfer histories; framed as future work
- Spec-freeze supervisor blessing — S1–S8 decided by author 2026-07-15; supervisor sign-off still valuable before final pass
- Parquet for 683MB clean CSV (nice-to-have)
- Lee (2009) bound on the rating outcome — estimator upgrade for the partial-identification section; decide at final pass whether in-scope or future work

## Figures & tables plan

Main text target: ~8 tables, ~4 figures; everything else → appendix dump zones.

- [x] Tab: summary stats, Bosman means, composition, intensive FE ladder, extensive, heterogeneity, rejected, robustness (auto-synced via make_latex_tables.py)
- [x] Fig: days-to-expiry histogram (in Data §; regenerate post-final-pass)
- [ ] Fig: contract-cycle event study (played_any + z_rating versions, post-final-pass)
- [ ] Fig: raw playing time by months-to-expiry (note June/July sawtooth → S7)
- [ ] Decide: Cole Palmer quarterly arc as motivating figure (intro/background hook)
- [ ] Decide: excl-8 robustness — own table or row in tab_robustness (moot if S2 makes it primary — then FULL-league set is the robustness row)
- [ ] Appendix inventory after final pass

## Administrative

- Submission deadline: **[fill in]**
- Target length: **[fill in — AU Econ norm ~60–80 pp]**
- Supervisor: **[name]** — last meeting: [date]; next: [date] — bring: spec freeze + S1–S8 + D6 definition (one-pager on request)
- [ ] Danish/English abstract requirements checked
- [ ] AU formatting/front-page requirements checked
- [ ] Plagiarism/AI-declaration requirements checked

## References

23 verified entries in references.bib (theory, sports canon, term limits, labor
analogues, Frick 2011, Deutscher–Büschemann 2016). Remaining:

- [ ] Boeri & Garibaldi 2024 — pull citation from PDF in Speciale folder
- [ ] AEL 2026 NBA contract-year paper — DOI-only entry (online-first)
- [ ] Engellandt–Riphahn 2005, Dechow–Sloan 1991, Brogaard et al. 2018, PLOS One 2019 — add when lit-review paragraphs are written
- [ ] Convert plain-text citations in main.tex to `\citep`/`\citet`
