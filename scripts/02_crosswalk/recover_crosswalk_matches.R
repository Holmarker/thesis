library(dplyr)
library(lubridate)
library(readr)

# Recovers crosswalk matches that the original name-based pipeline left
# unconfirmed, using date-of-birth/age + nationality agreement:
#   Rule A: unmatched review candidates where exactly one candidate pair
#           agrees on nationality and age (name score >= 90), with a
#           team-score tiebreak.
#   Rule B: confirmed-but-not-merge-safe rows where the fotmob-side
#           conflict is resolved because exactly one TM candidate agrees
#           on nationality and age.

confirmed_path <- file.path("data", "fotmob_transfermarkt_crosswalk_confirmed.csv")
review_path <- file.path("data", "fotmob_transfermarkt_crosswalk_review.csv")
dob_source_path <- file.path("data", "fotmob_all_transfermarkt_crosswalk_candidates.csv")
summary_out <- file.path("results", "fotmob_regressions", "coverage_diagnostics", "crosswalk_recovery_summary.csv")

age_reference_date <- as.Date("2025-06-30")
age_tolerance <- 1.0
name_score_min <- 90
team_score_tiebreak <- 80

confirmed <- read_csv(confirmed_path, show_col_types = FALSE)
review <- read_csv(review_path, show_col_types = FALSE)

dob_lookup <- read_csv(dob_source_path, show_col_types = FALSE) %>%
  filter(!is.na(date_of_birth)) %>%
  distinct(tm_player_id, date_of_birth)

backup_path <- paste0(confirmed_path, ".bak_", format(Sys.Date(), "%Y%m%d"))
if (!file.exists(backup_path)) {
  file.copy(confirmed_path, backup_path)
}

age_agrees <- function(df) {
  df %>%
    left_join(dob_lookup, by = "tm_player_id", suffix = c("", "_lookup")) %>%
    mutate(
      dob = coalesce(as.Date(date_of_birth_lookup), as.Date(date_of_birth)),
      tm_age_at_ref = as.numeric(age_reference_date - dob) / 365.25,
      age_agreement = !is.na(tm_age_at_ref) & !is.na(age) &
        abs(tm_age_at_ref - as.numeric(age)) <= age_tolerance
    )
}

safe_fotmob <- confirmed %>% filter(merge_safe) %>% pull(fotmob_player_id)
safe_tm <- confirmed %>% filter(merge_safe) %>% pull(tm_player_id)

# ---- Rule A: recover unmatched candidate pairs ----

pool <- review %>%
  filter(
    !fotmob_player_id %in% safe_fotmob,
    !tm_player_id %in% safe_tm,
    same_nationality_hint,
    name_match_score >= name_score_min
  ) %>%
  age_agrees() %>%
  filter(age_agreement)

pick_unique <- function(df) {
  df %>%
    group_by(fotmob_player_id) %>%
    mutate(n_tm = n_distinct(tm_player_id)) %>%
    ungroup() %>%
    mutate(
      keep = n_tm == 1 |
        (n_tm > 1 & coalesce(team_match_score, 0) >= team_score_tiebreak)
    ) %>%
    filter(keep) %>%
    group_by(fotmob_player_id) %>%
    filter(n_distinct(tm_player_id) == 1) %>%
    slice_max(candidate_score, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    group_by(tm_player_id) %>%
    filter(n_distinct(fotmob_player_id) == 1) %>%
    ungroup()
}

recovered_a <- pick_unique(pool) %>%
  select(any_of(names(confirmed))) %>%
  mutate(
    approved = TRUE,
    confirmation_source = "auto_recovered_age_nationality",
    tm_id_conflict_count = 1L,
    fotmob_id_conflict_count = 1L,
    has_tm_conflict = FALSE,
    has_fotmob_conflict = FALSE,
    merge_safe = TRUE
  )

# ---- Rule B: resolve conflicted confirmed rows ----

unsafe <- confirmed %>%
  filter(!merge_safe) %>%
  age_agrees()

resolved_b <- unsafe %>%
  filter(age_agreement, same_nationality_hint) %>%
  group_by(fotmob_player_id) %>%
  filter(n_distinct(tm_player_id) == 1) %>%
  slice_max(coalesce(candidate_score, 0), n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  group_by(tm_player_id) %>%
  filter(n_distinct(fotmob_player_id) == 1) %>%
  ungroup() %>%
  filter(!tm_player_id %in% safe_tm)

resolved_keys <- resolved_b %>%
  distinct(tm_player_id, fotmob_player_id) %>%
  mutate(resolved = TRUE)

confirmed_updated <- confirmed %>%
  left_join(resolved_keys, by = c("tm_player_id", "fotmob_player_id")) %>%
  mutate(
    merge_safe = merge_safe | coalesce(resolved, FALSE),
    confirmation_source = if_else(
      coalesce(resolved, FALSE),
      "auto_resolved_age_nationality",
      confirmation_source
    )
  ) %>%
  select(-resolved)

# Rule A pairs must not collide with anything now merge-safe after Rule B.
now_safe_fotmob <- confirmed_updated %>% filter(merge_safe) %>% pull(fotmob_player_id)
now_safe_tm <- confirmed_updated %>% filter(merge_safe) %>% pull(tm_player_id)

recovered_a <- recovered_a %>%
  filter(
    !fotmob_player_id %in% now_safe_fotmob,
    !tm_player_id %in% now_safe_tm
  )

confirmed_final <- bind_rows(confirmed_updated, recovered_a)

write_csv(confirmed_final, confirmed_path, na = "")

recovery_summary <- tibble(
  rule = c(
    "A_new_pairs_from_review",
    "B_resolved_confirmed_conflicts",
    "total_merge_safe_before",
    "total_merge_safe_after"
  ),
  n = c(
    nrow(recovered_a),
    nrow(resolved_keys),
    sum(confirmed$merge_safe),
    sum(confirmed_final$merge_safe)
  )
)

write_csv(recovery_summary, summary_out, na = "")

message("Backed up original confirmed crosswalk to: ", backup_path)
message("Rule A new pairs: ", nrow(recovered_a))
message("Rule B resolved conflicts: ", nrow(resolved_keys))
message("Merge-safe rows: ", sum(confirmed$merge_safe), " -> ", sum(confirmed_final$merge_safe))
message("Saved recovery summary to: ", summary_out)
