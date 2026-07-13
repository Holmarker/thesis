# Thesis outline & progress

Tracks `text/latex/main.tex`. Update the status column as you go.

Status legend: `todo` · `skeleton` (headers/notes only) · `draft` (full text, unpolished) · `revised` (edited once) · `final`

## Manuscript

| # | Section | Status | Notes |
|---|---------|--------|-------|
| 0 | Introduction | todo | Empty. Write LAST, after headline framing is fixed |
| 1 | Literature Review | draft | Holmström 79/82, Lazear–Rosen in place; has "This paper ..." placeholder; needs contract-cycle empirics (Stiroh, Krautmann/Solow, term-limits) |
| 2 | Background | draft | |
| 2.1 | — Football labor market | draft | FIFA RSTP + Diarra cited |
| 2.2 | — Bosman | draft | |
| 2.3 | — FotMob ratings | draft | |
| 3 | Data | draft | |
| 3.1 | — Sources and construction | draft | Update after clean-file rebuild (dedupe + encoding fix, 2026-07-13) |
| 3.2 | — Descriptive statistics | draft | tab_summary now 13 vars × 8 stats; re-check numbers post-rebuild |
| 3.3 | — Data engineering / panel construction | draft | |
| 4 | Empirical strategy | revised | |
| 4.1–4.9 | — Identification, margins, ladder, event study, partial ID, RDD rejection, inference, robustness | revised | |
| 4.10 | — Threats to identification | revised | Rewritten 2026-07-13: threat 1 contained (constant 28-league set, excl-8); threats 2–3 stand |
| 5 | Results | draft | |
| 5.1 | — Descriptive patterns | draft | |
| 5.2 | — Intensive margin | draft | Verify coefficients post-rebuild |
| 5.3 | — What the rating measures | draft | |
| 5.4 | — Extensive margin | draft | |
| 5.5 | — Contract-cycle event study | draft | |
| 5.6 | — Rejected designs | draft | |
| 5.7 | — Financial heterogeneity | draft | |
| 5.8 | — Synthesis | revised | Composition caveat updated 2026-07-13 |
| 6 | Discussion | skeleton | All subsections now stubbed: injury selection, FotMob ratings, mechanical selection/transfers, term-limits external validity, limitations |
| 7 | Conclusion | skeleton | Header + TODO note in place |
| — | Abstract | skeleton | `\begin{abstract}` stub in place |
| A–D | Appendix | skeleton | Four dump zones: descriptives, event-study/robustness, rejected RDD, data construction |

## Pipeline / analysis status

- [x] 2022/23 + 2023/24 ratings backfill (scraped Jul 12; 8 leagues never rated)
- [x] Excl-8 robustness regressions (`fotmob_regression_results_excl_unrated_leagues.csv`)
- [x] LaTeX tables auto-sync → `text/latex/tables/` (`make_latex_tables.py`)
- [ ] Clean-file rebuild (encoding + dedupe + minutes cap) → masters → panels → full re-run **(in progress 2026-07-13)**
- [ ] Re-run stale: `run_fotmob_sub_adjusted_ratings.R`, tenure/nationality
- [ ] Verify manuscript numbers against post-rebuild results
- [ ] Commit everything (safety point)
- [ ] Transfer/terminal-outcome analysis (deferred; addresses threat 2)

## Figures & tables plan

Main text (target ~8 tables, ~4 figures — everything else to appendix):

- [ ] Fig: days-to-expiry histogram (`figure1_days_to_expiry_histogram.png` — in `pictures/`, regenerate post-rebuild)
- [ ] Fig: contract-cycle event study (`fotmob_expiry_event_study.png`)
- [ ] Fig: raw playing time by months-to-expiry (`raw_playing_by_months_to_expiry.png`)
- [ ] Fig: motivating single-player arc (Cole Palmer quarterly — optional, intro/background hook)
- [x] Tab: summary statistics (`tab_summary`)
- [x] Tab: Bosman-window means (`tab_bosman_means`)
- [x] Tab: sample composition by season (`tab_composition`)
- [x] Tab: intensive-margin FE ladder (`tab_intensive_fe`)
- [x] Tab: extensive margin (`tab_extensive`)
- [x] Tab: heterogeneity (`tab_heterogeneity`)
- [x] Tab: rejected designs (`tab_rejected`)
- [x] Tab: robustness (`tab_robustness`)
- [ ] Decide: excl-8 constant-league-set robustness — own table or a row in `tab_robustness`?
- [ ] Appendix inventory (event-study by age, RDD support plots, balance tables, …)

## Administrative

- Submission deadline: **[fill in]**
- Target length: **[fill in — AU Econ norm ~60–80 pp]**
- Supervisor: **[name]** — last meeting: [date]; next: [date]
- [ ] Danish/English abstract requirements checked
- [ ] AU formatting/front-page requirements checked
- [ ] Plagiarism/AI-declaration requirements checked

## Questions for supervisor

- Is the precisely-estimated-null framing acceptable as a headline, or do they want the expiry-gradient/post-signing dip front and center?
- Main text vs appendix split for the rejected designs (RDD) section — keep full subsection or compress?
- Transfer/terminal-outcome extension: in scope for submission or explicitly "future work"?

## References

15 entries added 2026-07-13 (theory: Holmström ×2, Lazear–Rosen, Fama, Gibbons–Murphy,
Lazear 2000; sports: Lehn, Krautmann, Berri–Krautmann, Stiroh, Frick; labor:
Ichino–Riphahn; term limits: Besley–Case, List–Sturm, Alt et al.). Remaining:

- [ ] Deutscher & Büschemann (Bundesliga contract year, Kicker ratings) — verify exact title/year before adding; closest neighbor, must cite and differentiate
- [ ] Boeri & Garibaldi 2024 (PDF already in Speciale folder) — pull exact citation
- [ ] Gürtler/Prinz/Weimar Bundesliga shirking papers — locate
- [ ] Convert plain-text citations in main.tex to `\citep`/`\citet` (Holmström, Lazear–Rosen, Besley–Case, List–Sturm, Alt et al. all currently plain text)

## Headline decision (open)

Candidate framing: *precisely estimated null on the effort margin (robust to
coverage, league set, spell FE) + robust playing-time decline near expiry +
post-signing/long-contract dip (with mean-reversion caveat — Cole Palmer
example).* Introduction and abstract hang on confirming this after the rebuild.
