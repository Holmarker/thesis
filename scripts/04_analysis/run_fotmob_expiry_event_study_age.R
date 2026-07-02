library(dplyr)
library(fixest)
library(ggplot2)
library(readr)
library(tibble)

# Age-robustness for the contract-cycle event study. Within a spell,
# months-to-expiry advances one-for-one with age, so the declining
# playing profile could partly be an aging curve. Two checks:
#   (a) re-estimate with a quadratic age control;
#   (b) split by age at spell start — for young players aging IMPROVES
#       playing time, so a decline toward expiry cannot be an age effect.

panel_path <- file.path("data", "panel", "fotmob_analysis_panel_all_comps.csv")
results_dir <- file.path("results", "fotmob_regressions")

ref_month <- 18L
cap_month <- 24L

panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(
    Month = as.Date(Month),
    ContractExpiryDate = as.Date(ContractExpiryDate),
    player_id = as.integer(player_id),
    DaysToExpiry = as.numeric(DaysToExpiry),
    Age = as.numeric(Age),
    Minutes_tm = as.numeric(Minutes_tm),
    played_tm = coalesce(Minutes_tm, 0) > 0
  ) %>%
  filter(!is.na(DaysToExpiry), DaysToExpiry >= 0) %>%
  arrange(player_id, Month) %>%
  group_by(player_id) %>%
  mutate(
    prev_expiry = lag(ContractExpiryDate),
    expiry_jump_days = as.numeric(ContractExpiryDate - prev_expiry),
    new_spell = is.na(prev_expiry) | abs(coalesce(expiry_jump_days, 0)) > 90,
    spell_num = cumsum(new_spell),
    player_spell = paste0(player_id, "_", spell_num)
  ) %>%
  group_by(player_id, spell_num) %>%
  mutate(age_at_spell_start = first(Age)) %>%
  ungroup() %>%
  mutate(
    months_to_expiry = pmin(as.integer(floor(DaysToExpiry / 30.44)), cap_month),
    league_month = paste0(fotmob_source_league, "_", Month),
    age_group_spell = case_when(
      age_at_spell_start < 24 ~ "u24_at_spell_start",
      age_at_spell_start < 29 ~ "24_28_at_spell_start",
      age_at_spell_start >= 29 ~ "29plus_at_spell_start",
      TRUE ~ NA_character_
    )
  )

tidy_event <- function(model, outcome, variant) {
  out <- as_tibble(coeftable(model), rownames = "term")
  names(out) <- c("term", "estimate", "std_error", "t_value", "p_value")
  out %>%
    filter(grepl("months_to_expiry", term)) %>%
    mutate(
      months_to_expiry = as.integer(gsub(".*::", "", term)),
      outcome_name = outcome,
      variant = variant,
      nobs = nobs(model),
      ci_lo = estimate - 1.96 * std_error,
      ci_hi = estimate + 1.96 * std_error
    )
}

results <- list()

# (a) pooled, with and without quadratic age control
for (v in c("baseline", "age_quadratic")) {
  rhs <- if (v == "age_quadratic") {
    paste0("i(months_to_expiry, ref = ", ref_month, ") + Age + I(Age^2)")
  } else {
    paste0("i(months_to_expiry, ref = ", ref_month, ")")
  }
  m <- feols(as.formula(paste0("played_tm ~ ", rhs, " | player_spell + league_month")),
             data = panel, cluster = ~player_id)
  results[[length(results) + 1]] <- tidy_event(m, "played_tm", v)
}

# (b) split by age at spell start
for (g in c("u24_at_spell_start", "24_28_at_spell_start", "29plus_at_spell_start")) {
  d <- panel %>% filter(age_group_spell == g)
  m <- tryCatch(
    feols(as.formula(paste0("played_tm ~ i(months_to_expiry, ref = ", ref_month,
                            ") | player_spell + league_month")),
          data = d, cluster = ~player_id),
    error = function(e) NULL
  )
  if (!is.null(m)) results[[length(results) + 1]] <- tidy_event(m, "played_tm", g)
}

event_results <- bind_rows(results)
write_csv(event_results, file.path(results_dir, "fotmob_expiry_event_study_age.csv"), na = "")

variant_labels <- c(
  baseline = "Pooled (baseline)",
  age_quadratic = "Pooled + age, age^2",
  u24_at_spell_start = "Under 24 at spell start",
  `24_28_at_spell_start` = "24-28 at spell start",
  `29plus_at_spell_start` = "29+ at spell start"
)

ref_rows <- tibble(
  months_to_expiry = ref_month,
  variant = names(variant_labels),
  estimate = 0, ci_lo = 0, ci_hi = 0
)

plot_df <- bind_rows(
  event_results %>% select(months_to_expiry, variant, estimate, ci_lo, ci_hi),
  ref_rows
) %>%
  mutate(variant_label = factor(variant_labels[variant], levels = variant_labels))

p <- ggplot(plot_df, aes(x = months_to_expiry, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  geom_vline(xintercept = 6, linetype = "dotted", color = "grey40") +
  geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi), size = 0.3, color = "#00798c") +
  scale_x_reverse(breaks = seq(0, 24, 6)) +
  facet_wrap(~variant_label, ncol = 1, scales = "fixed") +
  labs(
    x = "Months to contract expiry (time runs left)",
    y = paste0("Effect on playing probability vs ", ref_month, " months to expiry"),
    title = "Playing over the contract cycle: age robustness",
    subtitle = "Spell + league-month FE; 95% CIs clustered by player; dotted line = Bosman window"
  ) +
  theme_minimal(base_size = 11)

ggsave(file.path(results_dir, "fotmob_expiry_event_study_age.png"), p, width = 8, height = 11, dpi = 150)

message("Saved age-robustness results and figure.")
