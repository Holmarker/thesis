suppressMessages({library(dplyr); library(fixest); library(readr)})
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
  mutate(Month = as.Date(Month), season = football_season(Month),
         ContractExpiryDate = as.Date(ContractExpiryDate)) %>%
  group_by(fotmob_source_league, season) %>%
  mutate(z = standardize_within(fotmob_mean_rating)) %>% ungroup() %>%
  arrange(player_id, Month) %>% group_by(player_id) %>%
  mutate(prev_expiry = lag(ContractExpiryDate),
         jump = as.numeric(ContractExpiryDate - prev_expiry),
         signed = !is.na(jump) & jump > 90,
         renewals_before = lag(cumsum(coalesce(signed, FALSE)), default = 0L),
         post = renewals_before > 0,
         # event time: months since first observed renewal
         first_sign = if_else(any(signed), min(Month[signed]), as.Date(NA)),
         evt = as.integer(round(as.numeric(Month - first_sign) / 30.44))) %>%
  ungroup()

cat("== post-renewal by season ==\n")
for (s in sort(unique(df$season))) {
  d <- df %>% filter(season == s)
  if (sum(d$post, na.rm=TRUE) < 50) { cat(s, ": too few post rows\n"); next }
  m <- tryCatch(feols(z ~ signed + post | player_id + Month, data = d, cluster = ~player_id), error=function(e) NULL)
  if (!is.null(m) && "postTRUE" %in% rownames(coeftable(m))) {
    ct <- coeftable(m)["postTRUE",]
    cat(sprintf("%s: post est=%7.3f p=%.4f n=%d\n", s, ct[1], ct[4], nobs(m)))
  }
}

cat("\n== event-time means around first renewal (within-player z, signers only) ==\n")
df %>% filter(!is.na(evt), evt >= -6, evt <= 6, !is.na(z)) %>%
  group_by(evt) %>% summarise(n = n(), mean_z = round(mean(z), 3), .groups="drop") %>%
  print(n = 13)
