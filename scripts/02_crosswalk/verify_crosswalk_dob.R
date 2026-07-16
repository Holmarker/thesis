# D8: verify the FotMob<->Transfermarkt crosswalk on exact date of birth
# (see text/DECISIONS.md), using data/fotmob_player_dob.csv from
# scripts/01_scraping/scrape_fotmob_player_dob.R.
#
# Three passes, rules fixed before the DOB data was seen:
#   1. VERIFY   every approved pair: TM dob == FotMob dob (+/- 1 day tolerated).
#               Mismatch -> merge_safe = FALSE, review_flag = "dob_mismatch".
#   2. RESOLVE  approved-but-unsafe conflicts: among TM claimants of one FotMob
#               id, exactly one DOB match -> winner keeps the pair
#               (merge_safe = TRUE), losers demoted (approved = FALSE,
#               review_flag = "dob_rejected"). Zero or multiple -> unchanged.
#   3. RESCUE   never-matched candidates: new pair iff exact DOB agreement
#               + name_match_score >= 85 + the pairing is unique in both
#               directions among DOB-agreeing candidates.
#
# Non-destructive: writes a dated backup of the confirmed crosswalk first and
# never deletes rows. Run without arguments for a DRY RUN (report only);
# run with "apply" to write.

library(dplyr)
library(readr)

args <- commandArgs(trailingOnly = TRUE)
apply_changes <- length(args) >= 1 && args[[1]] == "apply"

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0) return(existing[[1]])
  candidates[[1]]
}

crosswalk_path <- resolve_path("data", "fotmob_transfermarkt_crosswalk_confirmed.csv")
candidates_path <- resolve_path("data", "fotmob_all_transfermarkt_crosswalk_candidates.csv")
dob_path <- resolve_path("data", "fotmob_player_dob.csv")
report_path <- resolve_path("results", "fotmob_regressions", "coverage_diagnostics",
                            "crosswalk_dob_verification.csv")

dob <- read_csv(dob_path, show_col_types = FALSE) %>%
  filter(status == "ok") %>%
  distinct(fotmob_player_id, .keep_all = TRUE) %>%
  transmute(
    fotmob_player_id = as.integer(fotmob_player_id),
    fotmob_dob = as.Date(birth_date),
    fotmob_nationality = nationality
  )

cw <- read_csv(crosswalk_path, show_col_types = FALSE) %>%
  mutate(
    tm_player_id = as.integer(tm_player_id),
    fotmob_player_id = as.integer(fotmob_player_id),
    date_of_birth = as.Date(date_of_birth),
    approved = as.logical(approved),
    merge_safe = as.logical(merge_safe)
  )

normalize_name <- function(x) {
  x <- tolower(iconv(x, from = "", to = "ASCII//TRANSLIT"))
  gsub("[^a-z ]", "", x)
}

name_similarity <- function(a, b) {
  a <- normalize_name(a); b <- normalize_name(b)
  d <- mapply(function(x, y) utils::adist(x, y), a, b)
  100 * (1 - d / pmax(nchar(a), nchar(b), 1))
}

cands <- read_csv(candidates_path, show_col_types = FALSE) %>%
  mutate(
    tm_player_id = as.integer(tm_player_id),
    fotmob_player_id = as.integer(fotmob_player_id),
    date_of_birth = as.Date(date_of_birth),
    name_match_score = name_similarity(player_name_tm, fotmob_player_name)
  )

# exact agreement (+/- 1 day, timezone artifacts) verifies a pair. Same birth
# YEAR with a larger gap is treated as a site data-entry discrepancy for the
# same person (kept, flagged); a different birth year marks a wrong match
# (name-collision namesakes) and demotes the pair.
dob_agrees <- function(tm_dob, fm_dob) {
  !is.na(tm_dob) & !is.na(fm_dob) &
    (abs(as.numeric(tm_dob - fm_dob)) <= 1 |
       format(tm_dob, "%Y") == format(fm_dob, "%Y"))
}

# many confirmed rows carry no TM birthdate even though the candidate pool
# has one for the same tm_player_id; backfill before judging
tm_dob_lookup <- cands %>%
  filter(!is.na(date_of_birth)) %>%
  distinct(tm_player_id, .keep_all = TRUE) %>%
  select(tm_player_id, tm_dob_fill = date_of_birth)

cw <- cw %>%
  left_join(tm_dob_lookup, by = "tm_player_id") %>%
  mutate(date_of_birth = coalesce(date_of_birth, tm_dob_fill)) %>%
  select(-tm_dob_fill) %>%
  left_join(dob, by = "fotmob_player_id")

# ---- Pass 1: verify approved pairs -----------------------------------------
cw <- cw %>%
  mutate(
    dob_status = case_when(
      !approved ~ "not_approved",
      is.na(fotmob_dob) ~ "no_fotmob_dob",
      is.na(date_of_birth) ~ "no_tm_dob",
      dob_agrees(date_of_birth, fotmob_dob) ~ "verified",
      TRUE ~ "mismatch"
    )
  )

n_demoted <- sum(cw$dob_status == "mismatch" & cw$merge_safe, na.rm = TRUE)
cw <- cw %>%
  mutate(
    review_flag = if_else(dob_status == "mismatch" & merge_safe,
                          "dob_mismatch", review_flag),
    merge_safe = if_else(dob_status == "mismatch", FALSE, merge_safe)
  )

# ---- Pass 2: resolve approved-but-unsafe conflicts -------------------------
conflict_groups <- cw %>%
  filter(approved, !merge_safe, dob_status %in% c("verified", "mismatch", "no_tm_dob")) %>%
  group_by(fotmob_player_id) %>%
  summarise(
    n_claimants = n(),
    n_dob_match = sum(dob_status == "verified"),
    winner_tm = if (sum(dob_status == "verified") == 1) {
      tm_player_id[dob_status == "verified"]
    } else {
      NA_integer_
    },
    .groups = "drop"
  ) %>%
  filter(!is.na(winner_tm))

# a winner must not create a new conflict: its TM id may not already be
# merge-safe elsewhere
safe_tm <- cw %>% filter(merge_safe) %>% pull(tm_player_id)
conflict_groups <- conflict_groups %>% filter(!winner_tm %in% safe_tm)

cw <- cw %>%
  left_join(conflict_groups %>% select(fotmob_player_id, winner_tm),
            by = "fotmob_player_id") %>%
  mutate(
    is_winner = !is.na(winner_tm) & tm_player_id == winner_tm & approved & !merge_safe,
    is_loser = !is.na(winner_tm) & tm_player_id != winner_tm & approved & !merge_safe,
    merge_safe = if_else(is_winner, TRUE, merge_safe),
    review_flag = case_when(
      is_winner ~ "dob_resolved",
      is_loser ~ "dob_rejected",
      TRUE ~ review_flag
    ),
    approved = if_else(is_loser, FALSE, approved)
  ) %>%
  select(-winner_tm, -is_winner, -is_loser)

n_resolved <- nrow(conflict_groups)

# ---- Pass 3: rescue never-matched candidates -------------------------------
matched_tm <- cw %>% filter(approved) %>% pull(tm_player_id)
matched_fm <- cw %>% filter(approved) %>% pull(fotmob_player_id)

rescue_pool <- cands %>%
  filter(!tm_player_id %in% matched_tm, !fotmob_player_id %in% matched_fm) %>%
  left_join(dob, by = "fotmob_player_id") %>%
  filter(dob_agrees(date_of_birth, fotmob_dob), name_match_score >= 85)

rescues <- rescue_pool %>%
  group_by(tm_player_id) %>% filter(n() == 1) %>% ungroup() %>%
  group_by(fotmob_player_id) %>% filter(n() == 1) %>% ungroup()

n_rescued <- nrow(rescues)

if (n_rescued > 0) {
  new_rows <- rescues %>%
    select(any_of(names(cw))) %>%
    mutate(
      match_method = "dob_rescue",
      confirmation_source = "dob_verification",
      review_flag = "dob_rescued",
      approved = TRUE,
      merge_safe = TRUE,
      dob_status = "verified"
    )
  cw <- bind_rows(cw, new_rows)
}

# ---- Report -----------------------------------------------------------------
summary_tbl <- cw %>%
  filter(approved | review_flag %in% c("dob_rejected")) %>%
  count(dob_status, merge_safe, review_flag) %>%
  arrange(desc(n))

message("=== DOB verification summary (",
        if (apply_changes) "APPLY" else "DRY RUN", ") ===")
message("approved pairs checked: ", sum(cw$approved, na.rm = TRUE))
message("verified on DOB:        ", sum(cw$dob_status == "verified" & cw$approved, na.rm = TRUE))
message("mismatches demoted:     ", n_demoted)
message("conflicts resolved:     ", n_resolved)
message("candidates rescued:     ", n_rescued)
message("no FotMob DOB yet:      ", sum(cw$dob_status == "no_fotmob_dob" & cw$approved, na.rm = TRUE))
print(summary_tbl, n = 20)

if (apply_changes) {
  backup <- paste0(crosswalk_path, ".bak_dobverify_", format(Sys.Date(), "%Y%m%d"))
  file.copy(crosswalk_path, backup, overwrite = FALSE)
  write_csv(cw %>% select(-fotmob_dob, -fotmob_nationality), crosswalk_path, na = "")
  dir.create(dirname(report_path), recursive = TRUE, showWarnings = FALSE)
  write_csv(cw %>%
              filter(approved | review_flag %in% c("dob_rejected", "dob_mismatch")) %>%
              select(tm_player_id, player_name_tm, fotmob_player_id,
                     fotmob_player_name, date_of_birth, fotmob_dob,
                     dob_status, merge_safe, review_flag),
            report_path, na = "")
  message("Backed up to: ", backup)
  message("Wrote updated crosswalk and report: ", report_path)
} else {
  message("Dry run - no files written. Re-run with 'apply' to write.")
}
