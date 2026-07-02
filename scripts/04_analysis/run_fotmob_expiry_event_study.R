library(dplyr)
library(fixest)
library(ggplot2)
library(readr)
library(tibble)

# Event study in contract time: outcomes as a function of months-to-expiry,
# estimated within player x contract spell with league x month FE (primary)
# and player + month FE (comparison). Replaces the RDD as the main
# contract-run-down exhibit: no discontinuity assumption, full support.

panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
results_dir <- file.path("results", "fotmob_regressions")

ref_month <- 18L   # reference: 18 months to expiry (mid-contract)
cap_month <- 24L   # months >= 24 pooled into "24+"

football_season <- function(month) {
  y <- as.integer(format(month, "%Y"))
  m <- as.integer(format(month, "%m"))
  s <- if_else(m >= 7L, y, y - 1L)
  paste0(s, "/", s + 1L)
}

standardize_within <- function(x) {
  x <- if_else(!is.na(x) & x > 0, x, NA_real_)
  mu <- mean(x, na.rm = TRUE)
  sigma <- sd(x, na.rm = TRUE)
  if (is.na(sigma) || sigma == 0) {
    return(rep(NA_real_, length(x)))
  }
  (x - mu) / sigma
}

panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(
    Month = as.Date(Month),
    ContractExpiryDate = as.Date(ContractExpiryDate),
    player_id = as.integer(player_id),
    DaysToExpiry = as.numeric(DaysToExpiry),
    Minutes_tm = as.numeric(Minutes_tm),
    played_tm = coalesce(Minutes_tm, 0) > 0,
    season = football_season(Month)
  ) %>%
  filter(!is.na(DaysToExpiry), DaysToExpiry >= 0) %>%
  group_by(fotmob_source_league, season) %>%
  mutate(z_rating = standardize_within(fotmob_mean_rating)) %>%
  ungroup() %>%
  arrange(player_id, Month) %>%
  group_by(player_id) %>%
  mutate(
    prev_expiry = lag(ContractExpiryDate),
    expiry_jump_days = as.numeric(ContractExpiryDate - prev_expiry),
    new_spell = is.na(prev_expiry) | abs(coalesce(expiry_jump_days, 0)) > 90,
    spell_num = cumsum(new_spell),
    player_spell = paste0(player_id, "_", spell_num)
  ) %>%
  ungroup() %>%
  mutate(
    months_to_expiry = pmin(as.integer(floor(DaysToExpiry / 30.44)), cap_month),
    league_month = paste0(fotmob_source_league, "_", Month)
  )

specs <- tribble(
  ~spec_name, ~fe,
  "spell_leaguemonth", "player_spell + league_month",
  "player_month", "player_id + Month"
)

outcomes <- tribble(
  ~outcome, ~label,
  "played_tm", "Played at all (TM, extensive margin)",
  "Minutes_tm", "Minutes (TM)",
  "z_rating", "Std. rating | played (intensive margin)"
)

tidy_event <- function(model, outcome, spec_name) {
  out <- as_tibble(coeftable(model), rownames = "term")
  names(out) <- c("term", "estimate", "std_error", "t_value", "p_value")
  out %>%
    filter(grepl("months_to_expiry", term)) %>%
    mutate(
      months_to_expiry = as.integer(gsub(".*::", "", term)),
      outcome_name = outcome,
      spec_name = spec_name,
      nobs = nobs(model),
      ci_lo = estimate - 1.96 * std_error,
      ci_hi = estimate + 1.96 * std_error
    )
}

results <- list()
for (i in seq_len(nrow(specs))) {
  for (j in seq_len(nrow(outcomes))) {
    oc <- outcomes$outcome[j]
    fml <- as.formula(paste0(oc, " ~ i(months_to_expiry, ref = ", ref_month, ") | ", specs$fe[i]))
    m <- tryCatch(feols(fml, data = panel, cluster = ~player_id), error = function(e) NULL)
    if (!is.null(m)) {
      results[[length(results) + 1]] <- tidy_event(m, oc, specs$spec_name[i])
    }
  }
}
event_results <- bind_rows(results)

write_csv(event_results, file.path(results_dir, "fotmob_expiry_event_study.csv"), na = "")

ref_row <- expand.grid(
  months_to_expiry = ref_month,
  outcome_name = outcomes$outcome,
  spec_name = specs$spec_name,
  stringsAsFactors = FALSE
) %>%
  mutate(estimate = 0, ci_lo = 0, ci_hi = 0)

plot_df <- bind_rows(
  event_results %>% select(months_to_expiry, outcome_name, spec_name, estimate, ci_lo, ci_hi),
  ref_row
) %>%
  left_join(outcomes, by = c("outcome_name" = "outcome")) %>%
  mutate(
    spec_label = if_else(spec_name == "spell_leaguemonth",
                         "Spell + league-month FE (primary)",
                         "Player + month FE")
  )

p <- ggplot(plot_df, aes(x = months_to_expiry, y = estimate, color = spec_label)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  geom_vline(xintercept = 6, linetype = "dotted", color = "grey40") +
  annotate("text", x = 6.3, y = Inf, label = "Bosman window", hjust = 0, vjust = 1.5, size = 3, color = "grey40") +
  geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi), position = position_dodge(width = 0.5), size = 0.3) +
  scale_x_reverse(breaks = seq(0, 24, 6)) +
  facet_wrap(~label, scales = "free_y", ncol = 1) +
  labs(
    x = "Months to contract expiry (time runs left)",
    y = paste0("Effect relative to ", ref_month, " months to expiry"),
    color = NULL,
    title = "Outcomes over the contract cycle",
    subtitle = "Event-study coefficients with 95% CIs, clustered by player"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(results_dir, "fotmob_expiry_event_study.png"), p, width = 8, height = 9, dpi = 150)

message("Saved event-study results to: ", file.path(results_dir, "fotmob_expiry_event_study.csv"))
message("Saved figure to: ", file.path(results_dir, "fotmob_expiry_event_study.png"))
