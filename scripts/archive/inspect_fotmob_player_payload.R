library(jsonlite)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

player_id <- 160447
player_slug <- "adam-smith"
url <- sprintf("https://www.fotmob.com/players/%s/%s", player_id, player_slug)

html <- paste(readLines(url, warn = FALSE), collapse = "\n")
json_txt <- sub('.*<script id="__NEXT_DATA__" type="application/json">', "", html)
json_txt <- sub("</script>.*", "", json_txt)
payload <- fromJSON(json_txt, simplifyVector = FALSE)
player <- payload$props$pageProps$fallback[[sprintf("player:%s", player_id)]]
fallback_keys <- names(payload$props$pageProps$fallback)

cat("name=", player$name %||% "NA", "\n", sep = "")
cat("recent_matches=", length(player$recentMatches %||% list()), "\n", sep = "")

stat_seasons <- player$statSeasons %||% list()
cat("stat_seasons=", length(stat_seasons), "\n", sep = "")

for (i in seq_len(min(length(stat_seasons), 20))) {
  season <- stat_seasons[[i]]
  cat(
    i,
    "|",
    season$seasonName %||% "NA",
    "| tournaments=",
    length(season$tournaments %||% list()),
    "\n"
  )
}

target_season <- Filter(function(x) identical(x$seasonName %||% NA_character_, "2024/2025"), stat_seasons)
if (length(target_season) > 0) {
  cat("target_2024_2025_tournaments\n")
  tournaments <- target_season[[1]]$tournaments %||% list()
  for (i in seq_len(length(tournaments))) {
    tournament <- tournaments[[i]]
    cat(
      i,
      "| name=",
      tournament$name %||% "NA",
      "| tournamentId=",
      tournament$tournamentId %||% "NA",
      "| entryId=",
      tournament$entryId %||% "NA",
      "| hasDeepStats=",
      tournament$hasDeepStats %||% "NA",
      "\n",
      sep = ""
    )
  }
}

cat("player_keys=", paste(names(player), collapse = ", "), "\n", sep = "")
cat("fallback_keys_sample=", paste(head(fallback_keys, 20), collapse = ", "), "\n", sep = "")
