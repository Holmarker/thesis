suppressMessages({library(dplyr); library(fixest); library(readr); library(lubridate)})

football_season <- function(month) {
  y <- as.integer(format(month, "%Y")); m <- as.integer(format(month, "%m"))
  s <- if_else(m >= 7L, y, y - 1L); paste0(s, "/", s + 1L)
}
standardize_within <- function(x) {
  x <- if_else(!is.na(x) & x > 0, x, NA_real_)
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

df <- read_csv("data/panel/fotmob_analysis_panel_all_comps_strict.csv", show_col_types = FALSE) %>%
  mutate(Month = as.Date(Month), Bosman = as.logical(Bosman),
         Age = as.numeric(Age), season = football_season(Month)) %>%
  group_by(fotmob_source_league, season) %>%
  mutate(grp_n = sum(!is.na(fotmob_mean_rating) & fotmob_mean_rating > 0),
         z = standardize_within(fotmob_mean_rating),
         zw = standardize_within(fotmob_minutes_weighted_rating)) %>%
  ungroup()

cat("== league-season group sizes used for z ==\n")
gs <- df %>% distinct(fotmob_source_league, season, grp_n)
print(summary(gs$grp_n))
cat("groups with <30 rated rows:", sum(gs$grp_n < 30), "of", nrow(gs), "\n\n")

u23 <- df %>% filter(Age < 23)
cat("== u23 Bosman cells ==\n")
cat("u23 rows:", nrow(u23), " Bosman rows:", sum(u23$Bosman, na.rm=TRUE),
    " Bosman players:", n_distinct(u23$player_id[u23$Bosman]), "\n\n")

cat("== u23 Bosman by season ==\n")
season_rows <- list()
for (s in sort(unique(u23$season))) {
  d <- u23 %>% filter(season == s)
  if (sum(d$Bosman, na.rm=TRUE) < 20) { cat(s, ": too few Bosman rows (", sum(d$Bosman,na.rm=TRUE), ")\n"); next }
  m <- tryCatch(feols(z ~ Bosman | player_id + Month, data = d, cluster = ~player_id), error=function(e) NULL)
  if (!is.null(m) && "BosmanTRUE" %in% rownames(coeftable(m))) {
    ct <- coeftable(m)["BosmanTRUE",]
    cat(sprintf("%s: est=%7.3f p=%.4f n=%d bosman_rows=%d\n", s, ct[1], ct[4], nobs(m), sum(d$Bosman,na.rm=TRUE)))
    season_rows[[length(season_rows)+1]] <- data.frame(season=s, estimate=ct[1], p_value=ct[4], nobs=nobs(m), bosman_rows=sum(d$Bosman,na.rm=TRUE))
  }
}
readr::write_csv(dplyr::bind_rows(season_rows), "results/fotmob_regressions/fotmob_audit_bosman_u23_by_season.csv")

cat("\n== u23 Bosman, alternative outcomes/specs ==\n")
specs <- list(
  c("z (league-season)", "z"),
  c("z weighted", "zw"),
  c("raw mean rating", "fotmob_mean_rating")
)
for (sp in specs) {
  m <- feols(as.formula(paste0(sp[2], " ~ Bosman | player_id + Month")), data = u23, cluster = ~player_id)
  ct <- coeftable(m)["BosmanTRUE",]
  cat(sprintf("%-18s est=%7.3f p=%.4f n=%d\n", sp[1], ct[1], ct[4], nobs(m)))
}
# selection check: does being in Bosman window predict minutes (conditioning-on-playing bias)?
m <- feols(fotmob_minutes ~ Bosman | player_id + Month, data = u23, cluster = ~player_id)
ct <- coeftable(m)["BosmanTRUE",]
cat(sprintf("%-18s est=%7.3f p=%.4f  (minutes: selection-into-playing check)\n", "fotmob_minutes", ct[1], ct[4]))

cat("\n== RDD artifact check: raw means near 180-day cutoff (source_league, weighted) ==\n")
sl <- read_csv("data/panel/fotmob_analysis_panel_source_league.csv", show_col_types = FALSE) %>%
  mutate(DaysToExpiry = as.numeric(DaysToExpiry)) %>%
  filter(!is.na(fotmob_minutes_weighted_rating), fotmob_minutes_weighted_rating > 0,
         abs(DaysToExpiry - 180) <= 30)
sl %>% mutate(side = if_else(DaysToExpiry >= 180, "above(180-210)", "below(150-180)")) %>%
  group_by(side) %>%
  summarise(n = n(), mean_rating = mean(fotmob_minutes_weighted_rating), .groups="drop") %>%
  print()
