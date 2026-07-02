library(dplyr)
library(readr)
library(tibble)

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates) | dir.exists(candidates)]

  if (length(existing) > 0) {
    return(existing[[1]])
  }

  candidates[[1]]
}

panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
out_dir <- resolve_path("results", "fun")
index_out <- file.path(out_dir, "mercenary_index.csv")

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(
    Month = as.Date(Month),
    ContractExpiryDate = as.Date(ContractExpiryDate)
  ) %>%
  arrange(player_id, Month) %>%
  group_by(player_id) %>%
  mutate(
    prev_expiry = lag(ContractExpiryDate),
    expiry_jump_days = as.numeric(ContractExpiryDate - prev_expiry),
    signed_new_contract = !is.na(expiry_jump_days) & expiry_jump_days > 90,
    first_sign_month = if (any(signed_new_contract, na.rm = TRUE)) {
      first(Month[signed_new_contract])
    } else {
      as.Date(NA)
    },
    post_new_contract = !is.na(first_sign_month) & Month >= first_sign_month,
    near_expiry_0_6m = DaysToExpiry >= 0 & DaysToExpiry < 183
  ) %>%
  ungroup()

mercenary_index <- panel %>%
  group_by(player_id) %>%
  summarise(
    fotmob_player_id = first(fotmob_player_id),
    fotmob_player_name = first(fotmob_player_name),
    Club = first(Club),
    nationality = first(nationality_new),
    position = first(GenPosition),
    expiry_rows = sum(near_expiry_0_6m, na.rm = TRUE),
    post_contract_rows = sum(post_new_contract, na.rm = TRUE),
    expiry_mean_rating = mean(fotmob_mean_rating[near_expiry_0_6m], na.rm = TRUE),
    post_contract_mean_rating = mean(fotmob_mean_rating[post_new_contract], na.rm = TRUE),
    expiry_weighted_rating = mean(fotmob_minutes_weighted_rating[near_expiry_0_6m], na.rm = TRUE),
    post_contract_weighted_rating = mean(fotmob_minutes_weighted_rating[post_new_contract], na.rm = TRUE),
    expiry_minutes = sum(fotmob_minutes[near_expiry_0_6m], na.rm = TRUE),
    post_contract_minutes = sum(fotmob_minutes[post_new_contract], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    expiry_mean_rating = ifelse(is.nan(expiry_mean_rating), NA_real_, expiry_mean_rating),
    post_contract_mean_rating = ifelse(is.nan(post_contract_mean_rating), NA_real_, post_contract_mean_rating),
    expiry_weighted_rating = ifelse(is.nan(expiry_weighted_rating), NA_real_, expiry_weighted_rating),
    post_contract_weighted_rating = ifelse(is.nan(post_contract_weighted_rating), NA_real_, post_contract_weighted_rating),
    mercenary_index_mean = expiry_mean_rating - post_contract_mean_rating,
    mercenary_index_weighted = expiry_weighted_rating - post_contract_weighted_rating,
    reliability_flag = expiry_rows >= 2 & post_contract_rows >= 2 & expiry_minutes >= 180 & post_contract_minutes >= 180
  ) %>%
  filter(!is.na(mercenary_index_mean), !is.na(mercenary_index_weighted)) %>%
  arrange(desc(mercenary_index_weighted), desc(mercenary_index_mean))

ensure_dir(out_dir)
write_csv(mercenary_index, index_out, na = "")
message("Saved Mercenary Index to: ", index_out)
