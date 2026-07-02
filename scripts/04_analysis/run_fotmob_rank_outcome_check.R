suppressMessages({library(dplyr); library(fixest); library(readr)})
football_season <- function(month) {
  y <- as.integer(format(month, "%Y")); m <- as.integer(format(month, "%m"))
  s <- if_else(m >= 7L, y, y - 1L); paste0(s, "/", s + 1L)
}
df <- read_csv("data/panel/fotmob_analysis_panel_all_comps_strict.csv", show_col_types = FALSE) %>%
  mutate(Month = as.Date(Month), Bosman = as.logical(Bosman),
         player_id = as.integer(player_id),
         ContractExpiryDate = as.Date(ContractExpiryDate),
         season = football_season(Month),
         r = if_else(!is.na(fotmob_mean_rating) & fotmob_mean_rating > 0, fotmob_mean_rating, NA_real_),
         rw = if_else(!is.na(fotmob_minutes_weighted_rating) & fotmob_minutes_weighted_rating > 0, fotmob_minutes_weighted_rating, NA_real_)) %>%
  group_by(fotmob_source_league, Month) %>%
  mutate(pct_mean = if_else(is.na(r), NA_real_, percent_rank(r)),
         pct_weighted = if_else(is.na(rw), NA_real_, percent_rank(rw))) %>%
  ungroup() %>%
  arrange(player_id, Month) %>% group_by(player_id) %>%
  mutate(prev_expiry = lag(ContractExpiryDate),
         jump = as.numeric(ContractExpiryDate - prev_expiry),
         new_spell = is.na(prev_expiry) | abs(coalesce(jump,0)) > 90,
         spell_num = cumsum(new_spell),
         player_spell = paste0(player_id, "_", spell_num)) %>% ungroup() %>%
  mutate(league_month = paste0(fotmob_source_league, "_", Month),
         club_month = paste0(ClubID, "_", Month))

# skewness of the z outcome for reference
z <- scale(df$r)[,1]
sk <- mean((z-mean(z,na.rm=TRUE))^3, na.rm=TRUE)/sd(z,na.rm=TRUE)^3
cat("skewness of standardized mean rating:", round(sk,2), "\n\n")

for (oc in c("pct_mean","pct_weighted")) {
  for (sp in list(c("player_id + Month","~player_id"),
                  c("player_spell + league_month","~player_id"),
                  c("player_spell + club_month","~ClubID"))) {
    m <- tryCatch(feols(as.formula(paste0(oc," ~ Bosman | ",sp[1])), data=df, cluster=as.formula(sp[2])), error=function(e) NULL)
    if (!is.null(m) && "BosmanTRUE" %in% rownames(coeftable(m))) {
      ct <- coeftable(m)["BosmanTRUE",]
      cat(sprintf("%-13s %-28s est=%+7.4f p=%.4f n=%d\n", oc, sp[1], ct[1], ct[4], nobs(m)))
    }
  }
}
