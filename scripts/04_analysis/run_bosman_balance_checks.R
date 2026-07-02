library(dplyr)
library(readr)
library(tibble)
library(tidyr)

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates) | dir.exists(candidates)]

  if (length(existing) > 0) {
    return(existing[[1]])
  }

  candidates[[1]]
}

load_panel <- function(path) {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(
      Bosman = as.logical(Bosman),
      Age = as.numeric(Age),
      PlayerHeight = suppressWarnings(as.numeric(PlayerHeight)),
      crosswalk_candidate_score = as.numeric(crosswalk_candidate_score)
    ) %>%
    filter(!is.na(Bosman))
}

continuous_balance <- function(df, var_name) {
  sub <- df %>%
    filter(!is.na(.data[[var_name]])) %>%
    transmute(Bosman, value = .data[[var_name]])

  if (nrow(sub) == 0) {
    return(NULL)
  }

  bos <- sub$value[sub$Bosman]
  non <- sub$value[!sub$Bosman]

  test <- tryCatch(t.test(bos, non), error = function(e) NULL)

  pooled_sd <- sqrt((stats::var(bos, na.rm = TRUE) + stats::var(non, na.rm = TRUE)) / 2)
  smd <- if (is.finite(pooled_sd) && pooled_sd > 0) {
    (mean(bos, na.rm = TRUE) - mean(non, na.rm = TRUE)) / pooled_sd
  } else {
    NA_real_
  }

  tibble(
    variable = var_name,
    n_bosman = sum(!is.na(bos)),
    n_non_bosman = sum(!is.na(non)),
    mean_bosman = mean(bos, na.rm = TRUE),
    mean_non_bosman = mean(non, na.rm = TRUE),
    diff = mean(bos, na.rm = TRUE) - mean(non, na.rm = TRUE),
    sd_bosman = stats::sd(bos, na.rm = TRUE),
    sd_non_bosman = stats::sd(non, na.rm = TRUE),
    smd = smd,
    p_value = if (!is.null(test)) test$p.value else NA_real_
  )
}

categorical_balance <- function(df, var_name) {
  sub <- df %>%
    mutate(value = as.character(.data[[var_name]])) %>%
    filter(!is.na(value), value != "")

  if (nrow(sub) == 0) {
    return(NULL)
  }

  counts <- sub %>%
    count(variable = var_name, value, Bosman) %>%
    tidyr::complete(variable, value, Bosman = c(FALSE, TRUE), fill = list(n = 0)) %>%
    group_by(variable, Bosman) %>%
    mutate(share = n / sum(n)) %>%
    ungroup() %>%
    mutate(group = if_else(Bosman, "bosman", "non_bosman")) %>%
    select(variable, value, group, n, share) %>%
    tidyr::pivot_wider(
      names_from = group,
      values_from = c(n, share),
      names_sep = "_"
    )

  tab <- table(sub$value, sub$Bosman)
  chi_p <- tryCatch(chisq.test(tab)$p.value, error = function(e) NA_real_)

  counts %>%
    mutate(chi_square_p_value = chi_p)
}

panel_path <- resolve_path("data", "panel", "fotmob_analysis_panel_source_league.csv")
results_dir <- resolve_path("results", "fotmob_regressions")

continuous_out <- file.path(results_dir, "bosman_balance_continuous.csv")
categorical_out <- file.path(results_dir, "bosman_balance_categorical.csv")

dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

panel <- load_panel(panel_path)

continuous_vars <- c("Age", "PlayerHeight", "crosswalk_candidate_score")
categorical_vars <- c("PreferredFoot", "GenPosition", "country_region", "fotmob_squad_role")

continuous_results <- lapply(continuous_vars, function(v) continuous_balance(panel, v)) %>%
  bind_rows() %>%
  arrange(desc(abs(smd)))

categorical_results <- lapply(categorical_vars, function(v) categorical_balance(panel, v)) %>%
  bind_rows() %>%
  arrange(variable, desc(abs(share_bosman - share_non_bosman)))

write_csv(continuous_results, continuous_out)
write_csv(categorical_results, categorical_out)

print(continuous_results)
print(categorical_results)
