library(dplyr)
library(jsonlite)
library(readr)
library(stringr)
library(tibble)

input_path <- "RSpeciale/leaguenames.csv"
output_path <- "RSpeciale/league_config_resolved.csv"

normalize_name <- function(x) {
  x %>%
    iconv(from = "", to = "ASCII//TRANSLIT") %>%
    tolower() %>%
    str_replace_all("[^a-z0-9 ]", " ") %>%
    str_squish()
}

strip_prefix_country <- function(x) {
  x %>%
    str_replace("^(english|spanish|german|french|italian|turkish|portuguese|saudi|brazilian|belgian|dutch|ukrainian|greek|danish|scottish|austrian|argentine|swiss|serbian|croatian|czech|norwegian|romanian|polish|swedish|bulgarian|hungarian)\\s+", "") %>%
    str_squish()
}

extract_country_prefix <- function(x) {
  prefix <- str_extract(
    normalize_name(x),
    "^(english|spanish|german|french|italian|turkish|portuguese|saudi|brazilian|belgian|dutch|ukrainian|greek|danish|scottish|austrian|argentine|swiss|serbian|croatian|czech|norwegian|romanian|polish|swedish|bulgarian|hungarian)"
  )

  recode(
    prefix,
    english = "ENG",
    spanish = "ESP",
    german = "GER",
    french = "FRA",
    italian = "ITA",
    turkish = "TUR",
    portuguese = "POR",
    saudi = "KSA",
    brazilian = "BRA",
    belgian = "BEL",
    dutch = "NED",
    ukrainian = "UKR",
    greek = "GRE",
    danish = "DEN",
    scottish = "SCO",
    austrian = "AUT",
    argentine = "ARG",
    swiss = "SUI",
    serbian = "SRB",
    croatian = "CRO",
    czech = "CZE",
    norwegian = "NOR",
    romanian = "ROU",
    polish = "POL",
    swedish = "SWE",
    bulgarian = "BUL",
    hungarian = "HUN",
    .default = NA_character_
  )
}

canonicalize_target_name <- function(x) {
  x %>%
    normalize_name() %>%
    strip_prefix_country() %>%
    str_replace_all("\\bsuper lig\\b", "super lig") %>%
    str_replace_all("\\bprimeira liga\\b", "liga portugal") %>%
    str_replace_all("\\bpremier liga\\b", "premier league") %>%
    str_replace_all("\\b1 hnl\\b", "hnl") %>%
    str_replace_all("\\bfirst league\\b", "1 liga") %>%
    str_replace_all("\\bparva liga\\b", "first professional league") %>%
    str_replace_all("\\bprimera division\\b", "liga profesional") %>%
    str_replace_all("\\bnemzeti bajnoksag\\b", "nemzeti bajnoksag i") %>%
    str_replace_all("\\b1 lig\\b", "1 lig") %>%
    str_replace_all("\\blaliga 2\\b", "laliga2") %>%
    str_squish()
}

canonicalize_fotmob_name <- function(name, page_url, ccode) {
  normalized <- normalize_name(name)

  dplyr::case_when(
    ccode == "ESP" & normalized == "laliga" ~ "laliga",
    ccode == "ESP" & normalized == "laliga2" ~ "laliga2",
    ccode == "ENG" & normalized == "championship" ~ "championship",
    ccode == "ENG" & normalized == "league one" ~ "league one",
    ccode == "BEL" & normalized == "first division a" ~ "pro league",
    ccode == "BEL" & normalized == "first division b" ~ "challenger pro league",
    ccode == "KSA" & normalized == "saudi pro league" ~ "pro league",
    ccode == "UKR" & normalized == "premier league" ~ "premier league",
    ccode == "GRE" & normalized == "super league" ~ "super league 1",
    ccode == "CRO" & normalized == "hnl" ~ "hnl",
    ccode == "CZE" & normalized == "1 liga" ~ "1 liga",
    ccode == "ARG" & normalized == "liga profesional" ~ "liga profesional",
    ccode == "BUL" & normalized == "first professional league" ~ "first professional league",
    ccode == "ROU" & normalized == "liga i" ~ "liga 1",
    ccode == "HUN" & normalized == "nemzeti bajnoksag i" ~ "nemzeti bajnoksag i",
    ccode == "HUN" & str_detect(page_url, "nemzeti-bajnoksag-i") ~ "nemzeti bajnoksag i",
    ccode == "TUR" & normalized == "super lig" ~ "super lig",
    ccode == "TUR" & normalized == "1 lig" ~ "1 lig",
    ccode == "TUR" & str_detect(page_url, "super-lig") ~ "super lig",
    TRUE ~ normalized
  )
}

flatten_leagues <- function(payload) {
  popular <- bind_rows(lapply(payload$popular, function(x) {
    tibble(
      league_id = x$id,
      fotmob_name = x$name,
      localized_name = x$localizedName,
      page_url = x$pageUrl,
      ccode = x$ccode,
      source_group = "popular"
    )
  }))

  countries <- bind_rows(lapply(payload$countries, function(country) {
    bind_rows(lapply(country$leagues, function(league) {
      tibble(
        league_id = league$id,
        fotmob_name = league$name,
        localized_name = league$localizedName,
        page_url = league$pageUrl,
        ccode = league$ccode,
        source_group = "countries"
      )
    }))
  }))

  international <- bind_rows(lapply(payload$international, function(country) {
    bind_rows(lapply(country$leagues, function(league) {
      tibble(
        league_id = league$id,
        fotmob_name = league$name,
        localized_name = league$localizedName,
        page_url = league$pageUrl,
        ccode = league$ccode,
        source_group = "international"
      )
    }))
  }))

  bind_rows(popular, countries, international) %>%
    distinct(league_id, .keep_all = TRUE)
}

raw_targets <- read_csv(input_path, show_col_types = FALSE) %>%
  rename(raw_league_name = 1) %>%
  mutate(
    league_name = raw_league_name,
    target_ccode = extract_country_prefix(raw_league_name),
    target_name_clean = canonicalize_target_name(raw_league_name)
  )

all_leagues <- fromJSON(
  "https://www.fotmob.com/api/data/allLeagues?locale=da&country=DNK",
  simplifyVector = FALSE
) %>%
  flatten_leagues() %>%
  mutate(
    fotmob_name_clean = canonicalize_fotmob_name(fotmob_name, page_url, ccode)
  )

resolved <- raw_targets %>%
  left_join(
    all_leagues,
    by = c(
      "target_ccode" = "ccode",
      "target_name_clean" = "fotmob_name_clean"
    )
  ) %>%
  mutate(
    season_start = case_when(
      str_detect(league_name, "Brazilian Serie A|Brazilian Serie B|Argentine Primera Division|Norwegian Eliteserien|Swedish Allsvenskan") ~ "2025-01-01",
      TRUE ~ "2025-07-01"
    ),
    season_end = case_when(
      str_detect(league_name, "Brazilian Serie A|Brazilian Serie B|Argentine Primera Division") ~ "2025-12-31",
      str_detect(league_name, "Norwegian Eliteserien|Swedish Allsvenskan") ~ "2025-11-30",
      TRUE ~ "2026-05-31"
    ),
    active = TRUE,
    match_status = if_else(is.na(league_id), "unmatched", "matched")
  ) %>%
  rename(
    ccode = target_ccode
  ) %>%
  select(
    league_name,
    league_id,
    fotmob_name,
    localized_name,
    ccode,
    page_url,
    season_start,
    season_end,
    active,
    match_status
  )

write_csv(resolved, output_path, na = "")

message("Saved resolved config to: ", output_path)
message("Matched leagues: ", sum(resolved$match_status == "matched"))
message("Unmatched leagues: ", sum(resolved$match_status == "unmatched"))
