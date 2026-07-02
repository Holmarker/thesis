library(dplyr)
library(readr)

autokeep_path <- "RSpeciale/data/fotmob_transfermarkt_crosswalk_autokeep.csv"
manual_review_path <- "RSpeciale/data/fotmob_transfermarkt_crosswalk_manual_review.csv"
confirmed_out <- "RSpeciale/data/fotmob_transfermarkt_crosswalk_confirmed.csv"
conflicts_out <- "RSpeciale/data/fotmob_transfermarkt_crosswalk_conflicts.csv"

autokeep <- read_csv(autokeep_path, show_col_types = FALSE) %>%
  mutate(confirmation_source = "autokeep")

manual_review <- read_csv(manual_review_path, show_col_types = FALSE) %>%
  mutate(confirmation_source = "manual_review")

confirmed <- bind_rows(autokeep, manual_review) %>%
  mutate(approved = TRUE) %>%
  group_by(tm_player_id) %>%
  mutate(tm_id_conflict_count = n()) %>%
  ungroup() %>%
  group_by(fotmob_player_id) %>%
  mutate(fotmob_id_conflict_count = n()) %>%
  ungroup() %>%
  mutate(
    has_tm_conflict = tm_id_conflict_count > 1,
    has_fotmob_conflict = fotmob_id_conflict_count > 1,
    merge_safe = !has_tm_conflict & !has_fotmob_conflict
  ) %>%
  arrange(desc(has_fotmob_conflict), player_name_tm, tm_player_id)

conflicts <- confirmed %>%
  filter(has_tm_conflict | has_fotmob_conflict)

write_csv(confirmed, confirmed_out, na = "")
message("Saved confirmed crosswalk to: ", confirmed_out)

write_csv(conflicts, conflicts_out, na = "")
message("Saved crosswalk conflicts to: ", conflicts_out)

message("Confirmed rows: ", nrow(confirmed))
message("Merge-safe rows: ", sum(confirmed$merge_safe, na.rm = TRUE))
message("Rows with FotMob conflicts: ", sum(confirmed$has_fotmob_conflict, na.rm = TRUE))
