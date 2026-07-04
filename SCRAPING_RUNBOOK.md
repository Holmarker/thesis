# FotMob Scraping Runbook

How to run the match-rating scrapes on any machine, what still needs scraping, and how to get the results back into the pipeline. Written 2026-07-04.

## What still needs scraping (priority order)

1. **2024/25, remaining leagues** — 30 of 36 done locally. Still missing or partial:
   - Ukrainian Premier Liga, Serbian Super Liga, Romanian Liga 1, Bulgarian Parva Liga, Hungarian Nemzeti Bajnoksag, Belgian Challenger Pro League, Czech First League (partial: 43 rows).
   - Check current status any time: `data/historical/fotmob_match_rating_scrape_manifest_2024_2025.csv` (`processed_matches == 0` means missing) — but the ground truth is the per-league files in `data/historical/checkpoints/ratings/*_2024-2025_ratings.csv` (a 1-line file = header only = not scraped).
2. **2025/26 full season** — fills the missing Apr-May 2026 season run-in (current data stops 2026-03-26). Config is ready: `config/league_config_resolved_2025_2026.csv`. The resume logic skips already-scraped matches, so running the full season config is safe and only fetches what is new.
3. **2022/23 and 2023/24, non-top-5 leagues** — currently only PL, LaLiga, Bundesliga, Serie A, Ligue 1 exist for these seasons. Use the full league config for each season. This roughly balances panel composition across seasons (the single biggest design weakness).
4. **2021/22 (experimental)** — unknown whether the endpoint serves it; test with one league and `limit_matches` first.

## What you need on the new machine

- R (4.x) with packages: `dplyr`, `jsonlite`, `lubridate`, `readr`, `stringr`, `tibble`.
- The repo: `git clone https://github.com/Holmarker/thesis.git` — scripts and configs are in git.
- **Not in git** (data/ is gitignored) — copy from the main machine or OneDrive:
  - `data/historical/fotmob_cookie.txt` (auth; scraper reads it via `FOTMOB_COOKIE_FILE`).
  - Optionally the existing `data/historical/checkpoints/ratings/*.csv` for the season you scrape, so resume-skipping works and you only fetch what's missing. If you skip this, you re-scrape from zero into fresh files (fine, just slower).
- Create the expected dirs if absent: `data/historical/checkpoints/ratings/`, `data/historical/match_fixtures/`, `data/historical/logs/`.

## The command

Always run from the repo root:

```bash
FOTMOB_COOKIE_FILE=data/historical/fotmob_cookie.txt \
FOTMOB_REQUEST_DELAY=1 \
Rscript scripts/01_scraping/scrape_historical_fotmob_match_ratings.R \
  "<SEASON>" <LEAGUE_CONFIG> [limit_leagues] [limit_matches]
```

- `<SEASON>`: e.g. `"2024/2025"`, `"2025/2026"`, `"2023/2024"`.
- `<LEAGUE_CONFIG>`: e.g. `config/league_config_resolved_2024_2025.csv` (2024/25 and earlier seasons) or `config/league_config_resolved_2025_2026.csv` (2025/26). The config's `season_start`/`season_end` matter for calendar-year leagues (Argentina, Brazil, Norway, Sweden) — use the config matching the season.
- Optional 3rd/4th args: limit to first N leagues / N matches per league — use `... "2021/2022" config/league_config_resolved.csv 1 10` for a cheap endpoint test.

To scrape only specific leagues, make a filtered config (header + wanted rows):

```bash
head -1 config/league_config_resolved_2024_2025.csv > /tmp/remaining.csv
grep -E 'Ukrainian|Serbian|Romanian|Bulgarian|Hungarian|Challenger|Czech' \
  config/league_config_resolved_2024_2025.csv >> /tmp/remaining.csv
```

## Rate limiting (important)

FotMob serves roughly 600-4,000 requests per window, then silently returns **empty** responses (no errors — the log just shows `Saved fixtures for X: 0` or leagues producing 0 rows). The block clears after ~45-90 minutes.

- Run with `FOTMOB_REQUEST_DELAY=1` (seconds between requests). Higher delay does not clearly prevent blocks; the loop-and-wait pattern matters more.
- Pattern that works: run → when it starts returning zeros, wait an hour → run again. Re-runs are cheap: fixtures are re-fetched, already-scraped match IDs are skipped.
- Simple loop (bash):

```bash
for i in $(seq 1 12); do
  FOTMOB_COOKIE_FILE=data/historical/fotmob_cookie.txt FOTMOB_REQUEST_DELAY=1 \
    Rscript scripts/01_scraping/scrape_historical_fotmob_match_ratings.R \
    "2024/2025" config/league_config_resolved_2024_2025.csv
  sleep 3600
done
```

- Keep the machine awake (macOS: prefix with `caffeinate -is`; the run dies silently if the laptop sleeps).
- **Never run two scrapers against the same checkpoint files simultaneously** (e.g. two machines on a shared OneDrive folder, or overlapping local runs) — concurrent writes corrupt the CSVs. One machine per season at a time; if the checkpoints live in synced storage, pause sync or use a local copy.

## Outputs and how to verify

- Ratings: `data/historical/checkpoints/ratings/<leagueid>_<slug>_<season>_ratings.csv` (one file per league-season; written after each league completes).
- Fixtures cache: `data/historical/match_fixtures/<season>/`.
- Manifest: `data/historical/fotmob_match_rating_scrape_manifest_<season>.csv` — per-league `fixtures`, `processed_matches`, `rating_rows`. A league is done when `processed_matches == fixtures` (a few missing matches are normal: postponed/void fixtures).
- Sanity check a file: expect ~40-50 rating rows per match, `rating` in (0,10], dates spanning the whole season (e.g. Aug-May for European leagues).

## Getting results back into the pipeline (main machine)

1. Copy the new/updated `*_ratings.csv` files into `data/historical/checkpoints/ratings/` on the main machine (overwrite: files are per-league-season, complete replacements are safe; do NOT merge by hand).
2. Integrate into the master monthly files, once per season slug:
   ```bash
   FOTMOB_HISTORICAL_SEASON_SLUG=2024-2025 Rscript scripts/03_build/integrate_historical_fotmob_ratings.R
   ```
   (slug format `YYYY-YYYY`; the script dedupes on league+player+match and drops malformed rows.)
3. Refresh the panels: `Rscript scripts/03_build/augment_fotmob_panels_from_existing.R`
4. Rerun analyses (order doesn't matter): `run_fotmob_panel_regressions.R`, `run_fotmob_heterogeneity.R`, `run_fotmob_spell_fe_regressions.R`, `run_fotmob_selection_margin.R`, `run_fotmob_expiry_event_study.R` (+ `_age`, `_active_months`), `run_fotmob_club_month_fe.R`, `run_fotmob_additional_robustness.R`, `run_fotmob_rating_anatomy.R`, `run_thesis_descriptive_statistics.R`.

## Known quirks

- Calendar-year leagues (Argentina, Brazil A/B, Norway, Sweden) need `season_start` beginning Jan 1 in the config; the scraper then queries FotMob with plain years. The 2025 South American/Nordic seasons for "2024/25" came out empty historically — verify these separately and don't burn request budget on them first.
- FotMob player names in raw files contain `<c3><a7>`-style byte escapes; downstream cleaning handles decoding — don't "fix" the raw files.
- One rating of 12.6 has been seen (extra-time glitch); the cleaning step now clamps ratings to (0,10].
