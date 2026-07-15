# Scrape date of birth (and nationality) for FotMob players, to verify the
# FotMob<->Transfermarkt crosswalk on exact birthdate (see text/DECISIONS.md).
#
# Targets: every FotMob id appearing in the confirmed crosswalk (approved rows,
# safe or not) plus all ids in the candidate pool, so unsafe conflicts and
# never-matched candidates can be adjudicated too.
#
# Checkpointed and resumable: appends to the output CSV and skips ids already
# fetched. Polite: ~1 request/second with jitter.
#
# Usage: Rscript scripts/01_scraping/scrape_fotmob_player_dob.R [max_players]

library(dplyr)
library(jsonlite)
library(readr)

`%||%` <- function(a, b) if (is.null(a)) b else a

args <- commandArgs(trailingOnly = TRUE)
max_players <- if (length(args) >= 1) as.integer(args[[1]]) else Inf

resolve_path <- function(...) {
  rel_path <- file.path(...)
  candidates <- c(rel_path, file.path("RSpeciale", rel_path))
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0) return(existing[[1]])
  candidates[[1]]
}

crosswalk_path <- resolve_path("data", "fotmob_transfermarkt_crosswalk_confirmed.csv")
candidates_path <- resolve_path("data", "fotmob_all_transfermarkt_crosswalk_candidates.csv")
out_path <- resolve_path("data", "fotmob_player_dob.csv")

crosswalk_ids <- read_csv(crosswalk_path, show_col_types = FALSE) %>%
  filter(approved) %>%
  pull(fotmob_player_id)

candidate_ids <- read_csv(candidates_path, show_col_types = FALSE) %>%
  pull(fotmob_player_id)

target_ids <- sort(unique(as.integer(c(crosswalk_ids, candidate_ids))))
target_ids <- target_ids[!is.na(target_ids)]

done_ids <- integer()
if (file.exists(out_path)) {
  prev <- read_csv(out_path, show_col_types = FALSE)
  # only successful fetches count as done; failures are retried on resume
  done_ids <- prev$fotmob_player_id[prev$status == "ok"]
}

todo <- setdiff(target_ids, done_ids)
message("Targets: ", length(target_ids), "; already fetched: ", length(done_ids),
        "; to do: ", length(todo))
todo <- head(todo, max_players)

get_fotmob_page_json <- function(url) {
  html <- paste(readLines(url, warn = FALSE), collapse = "\n")
  json_txt <- sub('.*<script id="__NEXT_DATA__" type="application/json">', "", html)
  json_txt <- sub("</script>.*", "", json_txt)
  fromJSON(json_txt, simplifyVector = FALSE)
}

fetch_player_dob <- function(player_id) {
  url <- sprintf("https://www.fotmob.com/players/%s/x", player_id)
  payload <- tryCatch(get_fotmob_page_json(url), error = function(e) NULL)

  row <- tibble(
    fotmob_player_id = as.integer(player_id),
    fotmob_player_name = NA_character_,
    birth_date = NA_character_,
    nationality = NA_character_,
    status = "fetch_failed",
    fetched_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
  if (is.null(payload)) return(row)

  fb <- payload$props$pageProps$fallback
  key <- sprintf("player:%s", player_id)
  pp <- fb[[key]]
  if (is.null(pp)) {
    # the fallback key sometimes carries query-suffixes; take the first
    # player:-prefixed entry instead
    hits <- grep("^player:", names(fb), value = TRUE)
    if (length(hits) > 0) pp <- fb[[hits[[1]]]]
  }
  if (is.null(pp)) {
    row$status <- "no_player_payload"
    return(row)
  }

  # locate the schema.org Person object inside meta regardless of key casing
  jsonld <- NULL
  for (m in pp$meta) {
    if (is.list(m) && identical(m[["@type"]], "Person")) { jsonld <- m; break }
  }
  row$fotmob_player_name <- pp$name %||% (jsonld$name %||% NA_character_)
  row$birth_date <- substr(jsonld$birthDate %||% "", 1, 10)
  if (!nzchar(row$birth_date)) row$birth_date <- NA_character_
  row$nationality <- jsonld$nationality$name %||% NA_character_
  row$status <- if (is.na(row$birth_date)) "no_birthdate" else "ok"
  row
}

append_row <- function(row, path) {
  write_csv(row, path, append = file.exists(path))
}

n_ok <- 0
for (i in seq_along(todo)) {
  row <- fetch_player_dob(todo[[i]])
  append_row(row, out_path)
  if (row$status == "ok") n_ok <- n_ok + 1
  if (i %% 100 == 0) {
    message(sprintf("%d/%d fetched (%d ok) - last id %s", i, length(todo), n_ok, todo[[i]]))
  }
  Sys.sleep(runif(1, 0.6, 1.2))
}

message("Done. Fetched ", length(todo), " players (", n_ok, " with birthdate) -> ", out_path)
