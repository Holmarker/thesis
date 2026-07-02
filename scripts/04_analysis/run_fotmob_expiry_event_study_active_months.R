suppressMessages({library(dplyr); library(fixest); library(readr)})
df <- read_csv("data/panel/fotmob_analysis_panel_all_comps.csv", show_col_types = FALSE) %>%
  mutate(Month = as.Date(Month), ContractExpiryDate = as.Date(ContractExpiryDate),
         player_id = as.integer(player_id), DaysToExpiry = as.numeric(DaysToExpiry),
         Minutes_tm = as.numeric(Minutes_tm), played = coalesce(Minutes_tm,0) > 0,
         cal_month = as.integer(format(Month,"%m"))) %>%
  filter(!is.na(DaysToExpiry), DaysToExpiry >= 0) %>%
  arrange(player_id, Month) %>% group_by(player_id) %>%
  mutate(prev_expiry = lag(ContractExpiryDate),
         jump = as.numeric(ContractExpiryDate - prev_expiry),
         new_spell = is.na(prev_expiry) | abs(coalesce(jump,0)) > 90,
         spell_num = cumsum(new_spell),
         player_spell = paste0(player_id,"_",spell_num)) %>% ungroup() %>%
  mutate(months_to_expiry = pmin(as.integer(floor(DaysToExpiry/30.44)), 24L),
         league_month = paste0(fotmob_source_league,"_",Month)) %>%
  group_by(league_month) %>%
  mutate(lm_play_share = mean(played)) %>% ungroup()

cat("== calendar month of the months_to_expiry==0 bin ==\n")
df %>% filter(months_to_expiry==0) %>% count(cal_month) %>% arrange(-n) %>% head(5) %>% print()

cat("\n== league-month activity distribution ==\n")
lm <- df %>% distinct(league_month, lm_play_share)
cat("league-months with play share < 10%:", mean(lm$lm_play_share < 0.10), "\n")

cat("\n== event-study endpoints: all months vs active league-months (play share >= 25%) ==\n")
for (variant in c("all","active")) {
  d <- if (variant=="active") df %>% filter(lm_play_share >= 0.25) else df
  m <- feols(played ~ i(months_to_expiry, ref = 18) | player_spell + league_month, data = d, cluster = ~player_id)
  ct <- as.data.frame(coeftable(m))
  ct$term <- rownames(ct)
  for (mm in c("0","3","6","12")) {
    row <- ct[ct$term==paste0("months_to_expiry::",mm),]
    if (nrow(row)) cat(sprintf("%-7s m=%2s est=%7.3f p=%.4f\n", variant, mm, row$Estimate, row$`Pr(>|t|)`))
  }
  cat("  n =", nobs(m), "\n")
}
