library(dplyr)
library(fixest)
library(openxlsx)
library(readr)
library(stringr)
library(tibble)
library(tidyr)

# Heterogeneity by club wage level. Club wages from
# data/all_clubs_financial_data.xlsx (OTP financials; local-currency
# values), converted to a currency-free measure: the club's average
# wage RANK within its league across 2022-2025 financial years, cut
# into league-level terciles. Clubs matched to the panel by normalized
# name within league.

fin_path <- file.path("data", "all_clubs_financial_data.xlsx")
panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps_strict.csv")
full_panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
results_dir <- file.path("results", "fotmob_regressions")

norm_club <- function(x) {
  x %>%
    str_replace_all("&amp;", "and") %>%
    str_replace_all("&", "and") %>%
    str_replace_all("ø", "o") %>%
    str_replace_all("æ", "a") %>%
    str_replace_all("å", "a") %>%
    iconv(from = "", to = "ASCII//TRANSLIT") %>%
    tolower() %>%
    str_replace_all("[^a-z0-9 ]", " ") %>%
    str_squish()
}

STOP <- c("fc", "cf", "afc", "sc", "ac", "sk", "fk", "if", "bk", "club", "cd",
          "ud", "us", "as", "ss", "sv", "1", "04", "05", "09", "the")
club_tokens <- function(x) {
  n <- tryCatch(norm_club(x), error = function(e) NA_character_)
  if (length(n) != 1 || is.na(n) || !nzchar(n)) return(character(0))
  setdiff(str_split(n, " ")[[1]], STOP)
}

token_sim <- function(a, b) {
  ta <- club_tokens(a); tb <- club_tokens(b)
  if (length(ta) == 0 || length(tb) == 0) return(0)
  length(intersect(ta, tb)) / min(length(ta), length(tb))
}

# ---- club wage ranks within league ----
fin <- read.xlsx(fin_path, sheet = 1) %>%
  filter(account_name == "Wages", !is.na(value), year >= 2022,
         !grepl("^League", club_name)) %>%
  mutate(value = abs(value)) %>%
  filter(value > 0) %>%
  group_by(league, club_id, club_name) %>%
  summarise(mean_wage_local = mean(value), n_years = n(), .groups = "drop") %>%
  group_by(league) %>%
  mutate(
    wage_rank = rank(-mean_wage_local),
    n_clubs = n(),
    wage_tercile = cut(percent_rank(mean_wage_local),
                       breaks = c(-Inf, 1 / 3, 2 / 3, Inf),
                       labels = c("low_wage", "mid_wage", "high_wage"))
  ) %>%
  ungroup()

# ---- match panel clubs to financial clubs within league ----
panel_clubs <- read_csv(panel_path, show_col_types = FALSE) %>%
  filter(!is.na(fotmob_source_league)) %>%
  count(fotmob_source_league, ClubID, Club) %>%
  rename(league = fotmob_source_league)

matches <- panel_clubs %>%
  inner_join(fin, by = "league", relationship = "many-to-many") %>%
  rowwise() %>%
  mutate(sim = token_sim(Club, club_name)) %>%
  ungroup() %>%
  filter(sim >= 0.5) %>%
  group_by(league, ClubID) %>%
  slice_max(sim, n = 1, with_ties = FALSE) %>%
  group_by(league, club_id) %>%
  slice_max(sim, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(league, ClubID, Club, fin_club = club_name, wage_tercile, wage_rank, n_clubs, sim)

write_csv(matches, file.path(results_dir, "club_wage_match_table.csv"), na = "")
message("matched clubs: ", nrow(matches), " of ", nrow(panel_clubs),
        " panel league-clubs (", n_distinct(panel_clubs$ClubID), " unique)")

# ---- panels with wage tercile ----
football_season <- function(month) {
  y <- as.integer(format(month, "%Y"))
  m <- as.integer(format(month, "%m"))
  s <- if_else(m >= 7L, y, y - 1L)
  paste0(s, "/", s + 1L)
}
standardize_within <- function(x) {
  x <- if_else(!is.na(x) & x > 0, x, NA_real_)
  mu <- mean(x, na.rm = TRUE); sigma <- sd(x, na.rm = TRUE)
  if (is.na(sigma) || sigma == 0) return(rep(NA_real_, length(x)))
  (x - mu) / sigma
}

prep <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(Month = as.Date(Month), Bosman = as.logical(Bosman),
           player_id = as.integer(player_id),
           ContractExpiryDate = as.Date(ContractExpiryDate),
           Minutes_tm = as.numeric(Minutes_tm),
           played = coalesce(Minutes_tm, 0) > 0,
           season = football_season(Month)) %>%
    left_join(matches %>% select(league, ClubID, wage_tercile),
              by = c("ClubID", "fotmob_source_league" = "league")) %>%
    group_by(fotmob_source_league, season) %>%
    mutate(z_mean = standardize_within(fotmob_mean_rating),
           z_weighted = standardize_within(fotmob_minutes_weighted_rating)) %>%
    ungroup() %>%
    arrange(player_id, Month) %>%
    group_by(player_id) %>%
    mutate(prev_expiry = lag(ContractExpiryDate),
           jump = as.numeric(ContractExpiryDate - prev_expiry),
           new_spell = is.na(prev_expiry) | abs(coalesce(jump, 0)) > 90,
           spell_num = cumsum(new_spell),
           player_spell = paste0(player_id, "_", spell_num)) %>%
    ungroup() %>%
    mutate(league_month = paste0(fotmob_source_league, "_", Month))
}

strict <- prep(panel_path)
full <- prep(full_panel_path)

tidy_row <- function(model, outcome, tercile, panel_name) {
  ct <- as_tibble(coeftable(model), rownames = "term") %>% filter(term == "BosmanTRUE")
  names(ct) <- c("term", "estimate", "std_error", "t_value", "p_value")
  ct %>% mutate(outcome_name = outcome, wage_tercile = tercile,
                panel = panel_name, nobs = nobs(model)) %>%
    select(panel, outcome_name, wage_tercile, term, estimate, std_error,
           t_value, p_value, nobs)
}

results <- list()
for (tc in c("low_wage", "mid_wage", "high_wage")) {
  d_full <- full %>% filter(wage_tercile == tc)
  d_strict <- strict %>% filter(wage_tercile == tc)
  for (spec in list(
    list(d = d_full, oc = "played", pn = "full"),
    list(d = d_full, oc = "Minutes_tm", pn = "full"),
    list(d = d_strict, oc = "z_mean", pn = "strict"),
    list(d = d_strict, oc = "z_weighted", pn = "strict")
  )) {
    m <- tryCatch(
      feols(as.formula(paste0(spec$oc, " ~ Bosman | player_spell + league_month")),
            data = spec$d, cluster = ~player_id),
      error = function(e) NULL
    )
    if (!is.null(m)) results[[length(results) + 1]] <- tidy_row(m, spec$oc, tc, spec$pn)
  }
}

out <- bind_rows(results)
write_csv(out, file.path(results_dir, "fotmob_wage_heterogeneity_results.csv"), na = "")
print(as.data.frame(out), digits = 3)
message("Saved to ", file.path(results_dir, "fotmob_wage_heterogeneity_results.csv"))

# ---- formal interaction tests and wages-to-revenue split ----

wtr <- read.xlsx(fin_path, sheet = 1) %>%
  filter(account_name == "Wages-to-revenue", !is.na(value), year >= 2022,
         !grepl("^League", club_name)) %>%
  mutate(value = abs(value)) %>%
  group_by(league, club_id, club_name) %>%
  summarise(mean_wtr = mean(value), .groups = "drop") %>%
  group_by(league) %>%
  mutate(wtr_tercile = cut(percent_rank(mean_wtr),
                           breaks = c(-Inf, 1 / 3, 2 / 3, Inf),
                           labels = c("low_pressure", "mid_pressure", "high_pressure"))) %>%
  ungroup() %>%
  select(league, club_name, wtr_tercile)

matches_wtr <- matches %>%
  left_join(wtr, by = c("league", "fin_club" = "club_name"))

add_wtr <- function(df) {
  df %>% left_join(matches_wtr %>% select(league, ClubID, wtr_tercile),
                   by = c("ClubID", "fotmob_source_league" = "league"))
}
strict <- add_wtr(strict)
full <- add_wtr(full)

interaction_test <- function(df, outcome, split_var, label) {
  d <- df %>% filter(!is.na(.data[[split_var]]))
  m <- tryCatch(
    feols(as.formula(paste0(outcome, " ~ Bosman * ", split_var,
                            " | player_spell + league_month")),
          data = d, cluster = ~player_id),
    error = function(e) NULL
  )
  if (is.null(m)) return(NULL)
  inter_terms <- grep("^Bosman.*:", rownames(coeftable(m)), value = TRUE)
  wt <- tryCatch(wald(m, keep = inter_terms, print = FALSE), error = function(e) NULL)
  tibble(
    test = label, outcome_name = outcome,
    joint_p = if (!is.null(wt)) wt$p else NA_real_,
    n_inter_terms = length(inter_terms), nobs = nobs(m)
  )
}

itests <- bind_rows(
  interaction_test(full, "played", "wage_tercile", "bosman_x_wage_tercile"),
  interaction_test(strict, "z_mean", "wage_tercile", "bosman_x_wage_tercile"),
  interaction_test(full, "played", "wtr_tercile", "bosman_x_wtr_tercile"),
  interaction_test(strict, "z_mean", "wtr_tercile", "bosman_x_wtr_tercile")
)
write_csv(itests, file.path(results_dir, "fotmob_wage_interaction_tests.csv"), na = "")
print(as.data.frame(itests))

# wages-to-revenue subgroup estimates (playing outcome)
wtr_results <- list()
for (tc in c("low_pressure", "mid_pressure", "high_pressure")) {
  for (spec in list(list(d = full %>% filter(wtr_tercile == tc), oc = "played", pn = "full"),
                    list(d = strict %>% filter(wtr_tercile == tc), oc = "z_weighted", pn = "strict"))) {
    m <- tryCatch(
      feols(as.formula(paste0(spec$oc, " ~ Bosman | player_spell + league_month")),
            data = spec$d, cluster = ~player_id),
      error = function(e) NULL
    )
    if (!is.null(m)) wtr_results[[length(wtr_results) + 1]] <- tidy_row(m, spec$oc, tc, spec$pn)
  }
}
wtr_out <- bind_rows(wtr_results)
write_csv(wtr_out, file.path(results_dir, "fotmob_wtr_heterogeneity_results.csv"), na = "")
print(as.data.frame(wtr_out), digits = 3)

# ---- global (cross-league) wage quintiles in EUR ----
# Approximate average 2022-2025 FX rates to EUR; adequate for quintile
# bucketing (a bucket misassignment would require a quintile-sized FX error).
fx <- c("&#8364;'m" = 1, "&#163;'m" = 1.16, "BRL'm" = 0.18,
        "DKK'm" = 0.134, "SEK'm" = 0.088, "NOK'm" = 0.087, "TRY'm" = 0.032)

fin_eur <- read.xlsx(fin_path, sheet = 1) %>%
  filter(account_name == "Wages", !is.na(value), year >= 2022,
         !grepl("^League", club_name)) %>%
  mutate(value = abs(value), fx_rate = fx[local_currency]) %>%
  filter(!is.na(fx_rate), value > 0) %>%
  group_by(league, club_id, club_name) %>%
  summarise(wage_eur = mean(value * fx_rate), .groups = "drop") %>%
  mutate(wage_quintile = cut(percent_rank(wage_eur),
                             breaks = c(-Inf, .2, .4, .6, .8, Inf),
                             labels = c("q1_bottom20", "q2", "q3", "q4", "q5_top20")))

matches_q <- matches %>%
  left_join(fin_eur %>% select(league, club_name, wage_eur, wage_quintile),
            by = c("league", "fin_club" = "club_name"))

add_q <- function(df) {
  df %>% left_join(matches_q %>% select(league, ClubID, wage_quintile),
                   by = c("ClubID", "fotmob_source_league" = "league"))
}
strict <- add_q(strict)
full <- add_q(full)

q_results <- list()
for (q in levels(fin_eur$wage_quintile)) {
  for (spec in list(list(d = full %>% filter(wage_quintile == q), oc = "played", pn = "full"),
                    list(d = strict %>% filter(wage_quintile == q), oc = "z_weighted", pn = "strict"))) {
    m <- tryCatch(
      feols(as.formula(paste0(spec$oc, " ~ Bosman | player_spell + league_month")),
            data = spec$d, cluster = ~player_id),
      error = function(e) NULL
    )
    if (!is.null(m)) q_results[[length(q_results) + 1]] <- tidy_row(m, spec$oc, q, spec$pn)
  }
}
q_out <- bind_rows(q_results)
write_csv(q_out, file.path(results_dir, "fotmob_wage_quintile_results.csv"), na = "")
print(as.data.frame(q_out), digits = 3)

qtest <- bind_rows(
  interaction_test(full, "played", "wage_quintile", "bosman_x_wage_quintile"),
  interaction_test(strict, "z_weighted", "wage_quintile", "bosman_x_wage_quintile")
)
write_csv(qtest, file.path(results_dir, "fotmob_wage_quintile_interaction.csv"), na = "")
print(as.data.frame(qtest))
