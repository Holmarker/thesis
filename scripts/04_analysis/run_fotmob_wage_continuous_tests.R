suppressMessages({library(dplyr); library(fixest); library(readr); library(stringr)})
library(openxlsx)

# Two pre-declared tests, playing outcome, spell + league-month FE:
#  T1: Bosman x within-league wage percentile (continuous, season-lagged)
#  T2: Bosman x wages-to-revenue percentile (continuous, season-lagged)

norm_club <- function(x) {
  x %>% str_replace_all("&amp;","and") %>% str_replace_all("&","and") %>%
    str_replace_all("ø","o") %>% str_replace_all("æ","a") %>% str_replace_all("å","a") %>%
    iconv(from="", to="ASCII//TRANSLIT") %>% tolower() %>%
    str_replace_all("[^a-z0-9 ]"," ") %>% str_squish()
}
STOP <- c("fc","cf","afc","sc","ac","sk","fk","if","bk","club","cd","ud","us","as","ss","sv","1","04","05","09","the")
club_tokens <- function(x){ n<-tryCatch(norm_club(x),error=function(e) NA_character_); if(length(n)!=1||is.na(n)||!nzchar(n)) return(character(0)); setdiff(str_split(n," ")[[1]],STOP)}
token_sim <- function(a,b){ta<-club_tokens(a);tb<-club_tokens(b); if(!length(ta)||!length(tb)) return(0); length(intersect(ta,tb))/min(length(ta),length(tb))}

raw <- read.xlsx("data/all_clubs_financial_data.xlsx", sheet=1) %>%
  filter(account_name %in% c("Wages","Wages-to-revenue"), !is.na(value), year>=2022, !grepl("^League",club_name)) %>%
  mutate(value=abs(value))
wage_pct <- raw %>% filter(account_name=="Wages") %>%
  group_by(league,year,club_name) %>% summarise(v=mean(value),.groups="drop") %>%
  group_by(league,year) %>% mutate(wage_pct=percent_rank(v)) %>% ungroup() %>%
  mutate(season=paste0(year,"/",year+1)) %>% select(league,season,club_name,wage_pct)
wtr_pct <- raw %>% filter(account_name=="Wages-to-revenue") %>%
  group_by(league,year,club_name) %>% summarise(v=mean(value),.groups="drop") %>%
  group_by(league,year) %>% mutate(wtr_pct=percent_rank(v)) %>% ungroup() %>%
  mutate(season=paste0(year,"/",year+1)) %>% select(league,season,club_name,wtr_pct)

football_season <- function(m){y<-as.integer(format(m,"%Y")); mm<-as.integer(format(m,"%m")); s<-if_else(mm>=7L,y,y-1L); paste0(s,"/",s+1L)}

panel <- read_csv("data/panel/fotmob_analysis_panel_all_comps.csv", show_col_types=FALSE) %>%
  mutate(Month=as.Date(Month), Bosman=as.logical(Bosman), player_id=as.integer(player_id),
         ContractExpiryDate=as.Date(ContractExpiryDate), Minutes_tm=as.numeric(Minutes_tm),
         played=coalesce(Minutes_tm,0)>0, season=football_season(Month)) %>%
  arrange(player_id,Month) %>% group_by(player_id) %>%
  mutate(prev=lag(ContractExpiryDate), jump=as.numeric(ContractExpiryDate-prev),
         new_spell=is.na(prev)|abs(coalesce(jump,0))>90, spell=cumsum(new_spell),
         player_spell=paste0(player_id,"_",spell)) %>% ungroup() %>%
  mutate(league_month=paste0(fotmob_source_league,"_",Month))

# club name matching (as in main script)
pc <- panel %>% filter(!is.na(fotmob_source_league)) %>% distinct(fotmob_source_league, ClubID, Club) %>% rename(league=fotmob_source_league)
fin_clubs <- wage_pct %>% distinct(league, club_name)
matches <- pc %>% inner_join(fin_clubs, by="league", relationship="many-to-many") %>%
  rowwise() %>% mutate(sim=token_sim(Club, club_name)) %>% ungroup() %>%
  filter(sim>=0.5) %>% group_by(league,ClubID) %>% slice_max(sim,n=1,with_ties=FALSE) %>%
  group_by(league,club_name) %>% slice_max(sim,n=1,with_ties=FALSE) %>% ungroup() %>%
  select(league, ClubID, club_name)

d <- panel %>%
  left_join(matches, by=c("fotmob_source_league"="league","ClubID")) %>%
  left_join(wage_pct, by=c("fotmob_source_league"="league","season","club_name")) %>%
  left_join(wtr_pct, by=c("fotmob_source_league"="league","season","club_name"))

cat("rows with wage_pct:", sum(!is.na(d$wage_pct)), " with wtr_pct:", sum(!is.na(d$wtr_pct)), "\n\n")
m1 <- feols(played ~ Bosman*wage_pct | player_spell + league_month, data=d %>% filter(!is.na(wage_pct)), cluster=~player_id)
cat("T1: Bosman x wage percentile (playing)\n"); print(coeftable(m1)[grep("Bosman",rownames(coeftable(m1))),,drop=FALSE])
m2 <- feols(played ~ Bosman*wtr_pct | player_spell + league_month, data=d %>% filter(!is.na(wtr_pct)), cluster=~player_id)
cat("\nT2: Bosman x wages-to-revenue percentile (playing)\n"); print(coeftable(m2)[grep("Bosman",rownames(coeftable(m2))),,drop=FALSE])
