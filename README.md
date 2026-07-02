# RSpeciale — Bosman Effect Thesis

Master's thesis studying whether football players approaching contract expiry (the Bosman free-transfer window) show performance changes, using FotMob match ratings merged with Transfermarkt contract data.

All scripts are run from the project root (the RStudio project working directory).

## Layout

- `scripts/01_scraping/` — FotMob scraping and league configuration (completed one-time work; checkpointed into `data/checkpoints` and `data/historical`)
- `scripts/02_crosswalk/` — FotMob ↔ Transfermarkt player ID matching and merge-coverage checks
- `scripts/03_build/` — cleaning ratings, building the master dataset and the analysis panels in `data/panel`
- `scripts/04_analysis/` — regressions, RDD, diagnostics, descriptive statistics, and plots (outputs to `results/`)
- `scripts/archive/` — one-off fixes and superseded drafts, kept for reference
- `config/` — league ID configs and season scrape targets used by the scraping scripts
- `data/` — all datasets (git-ignored; ~530 MB, lives in OneDrive)
- `results/` — output tables and figures, tracked in git; each subfolder has a `SUMMARY.md`

## Pipeline order

1. `01_scraping`: `resolve_league_ids.R` → `make_*_league_config.R` → `fotmob_integration_starter.R` / `fotmob_ratings_2024_2025_from_existing_players.R` / `scrape_historical_fotmob_match_ratings.R` → `prepare_historical_fotmob_stats.R`
2. `02_crosswalk`: `prepare_fotmob_crosswalk_review.R` → (manual review) → `finalize_fotmob_crosswalk.R`; `check_fotmob_merge_coverage.R` audits coverage
3. `03_build`: `clean_fotmob_ratings.R` → `refresh_fotmob_monthly_from_clean_fast.R` → `integrate_historical_fotmob_ratings.R` → `build_fotmob_master_dataset.R` → `build_fotmob_analysis_panel.R` → `augment_fotmob_panels_from_existing.R`
4. `04_analysis`: any of the `run_*.R` / `plot_*.R` scripts, which read `data/panel/*.csv` and write to `results/`

Note: `build_fotmob_analysis_panel.R` also reads from an external Dropbox valuation database (see paths at the top of the script), which is not part of this repository.

## Key results

See `results/fotmob_regressions/SUMMARY.md` for current regression, RDD, and diagnostic takeaways, and `results/thesis_descriptive_statistics/SUMMARY.md` for the descriptive-statistics section.
