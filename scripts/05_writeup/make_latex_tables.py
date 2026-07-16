#!/usr/bin/env python3
"""Generate the thesis LaTeX tables from the current results CSVs.

Writes to results/latex_tables/ (tracked in git) and, if it exists, also to
../tables/ (the thesis writing folder). Rerun after every rebuild so the
manuscript numbers always match the pipeline.
"""
import csv
import os
import shutil

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REG = os.path.join(REPO, "results", "fotmob_regressions")
DESC = os.path.join(REPO, "results", "thesis_descriptive_statistics")
OUT = os.path.join(REPO, "results", "latex_tables")
THESIS_TABLES = os.path.normpath(os.path.join(REPO, "..", "tables"))
LATEX_PROJECT_TABLES = os.path.join(REPO, "text", "latex", "tables")
os.makedirs(OUT, exist_ok=True)


def rows(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def pick(rs, **kw):
    out = [r for r in rs if all(r.get(k) == v for k, v in kw.items())]
    if len(out) != 1:
        raise SystemExit(f"pick() matched {len(out)} rows for {kw}")
    return out[0]


def pval(p):
    p = float(p)
    if p < 0.0001:
        return r"${<}0.0001$"
    if p < 0.001:
        return r"${<}0.001$"
    return f"${p:.2g}$" if p >= 0.01 else f"${p:.4f}$"


def num(x, d=3, sign=False):
    v = float(x)
    s = f"{v:+.{d}f}" if sign else f"{v:.{d}f}"
    return f"${s}$"


def grp(n):
    return f"{int(round(float(n))):,}".replace(",", r"{,}")


def write(name, body):
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        f.write(body)
    for dest in (THESIS_TABLES, LATEX_PROJECT_TABLES):
        if os.path.isdir(dest):
            shutil.copy(path, os.path.join(dest, name))
    print("wrote", name)


# ---------- tab_summary ----------
t1 = rows(os.path.join(DESC, "table1_full_sample_summary_statistics.csv"))
sv = {r["variable"]: r for r in t1}
label_map = [
    ("Age", "Age (years)"),
    ("DaysToExpiry", "Days to expiry"),
    ("Minutes_tm", "Minutes (month, TM)"),
    ("Goals_tm", "Goals (month, TM)"),
    ("Assists_tm", "Assists (month, TM)"),
    ("Goals_per90_tm", "Goals per 90 (TM)"),
    ("Assists_per90_tm", "Assists per 90 (TM)"),
    ("fotmob_matches", "FotMob matches (month)"),
    ("fotmob_minutes", "FotMob minutes (month)"),
    ("fotmob_goals", "FotMob goals (month)"),
    ("fotmob_assists", "FotMob assists (month)"),
    ("fotmob_mean_rating_clean", "Mean rating"),
    ("fotmob_minutes_weighted_rating_clean", "Minutes-weighted rating"),
]
lines = []
for var, label in label_map:
    r = sv[var]
    lines.append(
        f"    {label:27s} & {grp(r['n'])} & {float(r['mean']):.2f} "
        f"& {float(r['sd']):.2f} & {float(r['min']):.2f} & {float(r['p25']):.2f} "
        f"& {float(r['median']):.2f} & {float(r['p75']):.2f} & {float(r['max']):.2f} \\\\"
    )
overview = {r["statistic"]: r["value"] for r in rows(os.path.join(DESC, "sample_overview.csv"))}
first = overview.get("First month", "2022-06")[:7]
last = overview.get("Last month", "")[:7]
write("tab_summary.tex", f"""% Full-sample summary statistics (auto-generated: make_latex_tables.py)
\\begin{{table}}[htbp]
  \\centering
  \\caption{{Full-sample summary statistics.}}
  \\label{{tab:summary}}
  \\begin{{tabular}}{{lrrrrrrrr}}
    \\toprule
    Variable & $N$ & Mean & SD & Min & P25 & Median & P75 & Max \\\\
    \\midrule
{chr(10).join(lines)}
    \\bottomrule
  \\end{{tabular}}

  \\vspace{{4pt}}
  {{\\footnotesize\\itshape Note: player-month panel, {first}--{last}.
  Rating variables use positive (played) observations only.\\par}}
\\end{{table}}
""")

# ---------- tab_bosman_means ----------
t2 = rows(os.path.join(DESC, "table2_bosman_window_mean_comparison_ttests.csv"))
tv = {r["variable"]: r for r in t2}
bm_map = [
    ("DaysToExpiry", "Days to expiry", 1),
    ("Age", "Age (years)", 2),
    ("Minutes_tm", "Minutes (month)", 1),
    ("Goals_tm", "Goals (month)", 2),
    ("Assists_tm", "Assists (month)", 2),
    ("fotmob_mean_rating_clean", "Mean rating", 2),
    ("fotmob_minutes_weighted_rating_clean", "Minutes-wtd.\\ rating", 2),
]
lines = []
for var, label, d in bm_map:
    r = tv[var]
    diff = float(r["difference_bosman_minus_outside"])
    lines.append(
        f"    {label:22s} & {float(r['mean_bosman']):.{d}f} & {float(r['mean_outside']):.{d}f} "
        f"& ${diff:+.{d}f}$ & {pval(r['p_value'])} \\\\"
    )
n_bos = overview.get("Bosman-window observations", "")
n_bos_tex = grp(n_bos) if n_bos else "--"
write("tab_bosman_means.tex", f"""% Bosman vs non-Bosman unconditional means (auto-generated)
\\begin{{table}}[htbp]
  \\centering
  \\caption{{Player-months inside vs.\\ outside the Bosman window (unconditional means).}}
  \\label{{tab:bosman-means}}
  \\begin{{tabular}}{{lrrrr}}
    \\toprule
    Variable & Bosman & Non-Bosman & Diff. & $p$ \\\\
    \\midrule
{chr(10).join(lines)}
    \\bottomrule
  \\end{{tabular}}

  \\vspace{{4pt}}
  {{\\footnotesize\\itshape Note: full all-competitions panel; two-sample
  $t$-tests. $N_{{\\mathrm{{Bosman}}}}={n_bos_tex}$.\\par}}
\\end{{table}}
""")

# ---------- tab_composition ----------
comp = rows(os.path.join(DESC, "fotmob_rating_availability_by_season.csv"))
lines, tot_n, tot_r = [], 0, 0
for r in comp:
    n, rt = int(float(r["observations"])), int(float(r["positive_mean_rating_observations"]))
    tot_n += n
    tot_r += rt
    season = r["season"].replace("/20", "/")
    lines.append(f"    {season} & {grp(n)} & {grp(rt)} & {rt / n * 100:.1f}\\% \\\\" if n else "")
write("tab_composition.tex", f"""% Panel composition and rating coverage by season (auto-generated)
\\begin{{table}}[htbp]
  \\centering
  \\caption{{Panel composition and FotMob rating coverage by season.}}
  \\label{{tab:composition}}
  \\begin{{tabular}}{{lrrr}}
    \\toprule
    Season & Observations & Rated (positive) & Coverage \\\\
    \\midrule
{chr(10).join(l for l in lines if l)}
    \\midrule
    Total   & {grp(tot_n)} & {grp(tot_r)} & {tot_r / tot_n * 100:.1f}\\% \\\\
    \\bottomrule
  \\end{{tabular}}

  \\vspace{{4pt}}
  {{\\footnotesize\\itshape Note: earlier seasons cover contract and playing
  variables for all rows; FotMob rating coverage rises as the match-rating
  scrape widens from the top-five leagues to $\\sim$40 leagues.\\par}}
\\end{{table}}
""")

# ---------- tab_intensive_fe ----------
sf = rows(os.path.join(REG, "fotmob_spell_fe_results.csv"))
spec_labels = [
    ("player_month", "Player $+$ month"),
    ("player_leaguemonth", "Player $+$ league\\,$\\times$\\,month"),
    ("spell_month", "Spell $+$ month"),
    ("spell_leaguemonth", "Spell $+$ league\\,$\\times$\\,month"),
]
lines = []
mde = None
for spec, label in spec_labels:
    r = pick(sf, model_name="bosman", sample_name="all_comps_strict",
             outcome_name="z_mean_rating_league_season", spec_name=spec, term="BosmanTRUE")
    lines.append(f"    {label:36s} & {num(r['estimate'], sign=True)} & {pval(r['p_value'])} \\\\")
    mde = float(r["mde_80pct"])
rsl = pick(sf, model_name="bosman", sample_name="source_league_strict",
           outcome_name="z_mean_rating_league_season", spec_name="player_month", term="BosmanTRUE")
write("tab_intensive_fe.tex", f"""% Intensive-margin Bosman effect across FE structures (auto-generated)
\\begin{{table}}[htbp]
  \\centering
  \\caption{{Intensive margin: Bosman effect on the standardised match rating across fixed-effects structures.}}
  \\label{{tab:intensive-fe}}
  \\begin{{tabular}}{{lrr}}
    \\toprule
    Fixed-effects structure & Estimate (SD) & $p$ \\\\
    \\midrule
{chr(10).join(lines)}
    \\midrule
    Source-league sample (player $+$ month) & {num(rsl['estimate'], sign=True)} & {pval(rsl['p_value'])} \\\\
    \\bottomrule
  \\end{{tabular}}

  \\vspace{{4pt}}
  {{\\footnotesize\\itshape Note: outcome is the monthly rating standardised within
  league\\,$\\times$\\,season; SE clustered by player. Minimum detectable effect
  ($80\\%$ power) $\\approx {mde:.2f}$ SD. ``Spell'' denotes player-by-contract-spell
  fixed effects.\\par}}
\\end{{table}}
""")

# ---------- tab_extensive ----------
sel = rows(os.path.join(REG, "fotmob_selection_margin_results.csv"))
cm = rows(os.path.join(REG, "fotmob_club_month_fe_results.csv"))
def sel_pick(outcome):
    return pick(sel, model_name="bosman_selection", sample_name="all_comps_full",
                outcome_name=outcome, spec_name="spell_leaguemonth", term="BosmanTRUE")
fm_p = sel_pick("played_fotmob"); fm_m = sel_pick("fotmob_minutes")
any_p = sel_pick("played_any"); tm_p = sel_pick("played_tm")
e06 = pick(sel, model_name="expiry_selection", sample_name="all_comps_full",
           outcome_name="played_fotmob", spec_name="spell_leaguemonth", term="expiry_bin_6m::0:6")
cm_by = {r["outcome_name"]: r for r in cm}
def pp(r):
    return f"${float(r['estimate']) * 100:+.1f}$\\,pp"
write("tab_extensive.tex", f"""% Extensive margin: selection into playing (auto-generated)
\\begin{{table}}[htbp]
  \\centering
  \\caption{{Extensive margin: contract status and playing time (spell $+$ league$\\times$month FE).}}
  \\label{{tab:extensive}}
  \\begin{{tabular}}{{llrr}}
    \\toprule
    Outcome (source) & & Estimate & $p$ \\\\
    \\midrule
    \\multicolumn{{4}}{{l}}{{\\textit{{Panel A. Primary: FotMob, covered league-months (D10)}}}} \\\\
    Played & Bosman window       & {pp(fm_p)}  & {pval(fm_p['p_value'])}   \\\\
    Minutes & Bosman window      & {num(fm_m['estimate'], 1, sign=True)}  & {pval(fm_m['p_value'])}   \\\\
    Played & 0--6m expiry bin    & {pp(e06)} & {pval(e06['p_value'])} \\\\
    \\midrule
    \\multicolumn{{4}}{{l}}{{\\textit{{Panel B. Measurement robustness: same design, other sources}}}} \\\\
    Played (TM or FotMob) & Bosman window & {pp(any_p)} & {pval(any_p['p_value'])} \\\\
    Played (TM only) & Bosman window      & {pp(tm_p)}  & {pval(tm_p['p_value'])}   \\\\
    \\midrule
    \\multicolumn{{4}}{{l}}{{\\textit{{Panel C. Within teammates (club\\,$\\times$\\,month FE)}}}} \\\\
    Played & & {pp(cm_by['played'])}  & {pval(cm_by['played']['p_value'])} \\\\
    Minutes & & {num(cm_by['Minutes_tm']['estimate'], 1, sign=True)}      & {pval(cm_by['Minutes_tm']['p_value'])}   \\\\
    \\bottomrule
  \\end{{tabular}}

  \\vspace{{4pt}}
  {{\\footnotesize\\itshape Note: the extensive margin is measurement-bounded:
  FotMob-only outcomes show a small decline, the combined definition is null,
  and the TM-only definition (coverage-gapped) flips sign --- Panel B reports
  all three permanently (see decisions log, D10).\\par}}
\\end{{table}}
""")

# ---------- tab_heterogeneity ----------
het = rows(os.path.join(REG, "fotmob_heterogeneity_results.csv"))
audit = rows(os.path.join(REG, "fotmob_audit_bosman_u23_by_season.csv"))
lines_a = []
for lvl, label in [("u23", "Under 23"), ("23_28", "23--28"), ("29_plus", "29 or over")]:
    r = pick(het, model_name="bosman_fe", sample_name="all_comps_strict",
             outcome_name="z_mean_rating_league_season", split_var="age_group",
             split_level=lvl, term="BosmanTRUE")
    lines_a.append(f"    {label:10s} & {num(r['estimate'], sign=True)} & {pval(r['p_value'])} \\\\")
u23_pooled = pick(het, model_name="bosman_fe", sample_name="all_comps_strict",
                  outcome_name="z_mean_rating_league_season", split_var="age_group",
                  split_level="u23", term="BosmanTRUE")
lines_b = []
tot_b_rows, tot_b_players = 0, None
for r in audit:
    season = r["season"].replace("/20", "/")
    lines_b.append(f"    {season} & {num(r['estimate'], 2, sign=True)} & {pval(r['p_value'])} \\\\")
    tot_b_rows += int(r["bosman_rows"])
write("tab_heterogeneity.tex", f"""% Age heterogeneity and season-stability audit (auto-generated)
\\begin{{table}}[htbp]
  \\centering
  \\caption{{Bosman\\,$\\times$\\,age heterogeneity and season-stability audit (standardised rating).}}
  \\label{{tab:heterogeneity}}
  \\begin{{tabular}}{{lrr}}
    \\toprule
    \\multicolumn{{3}}{{l}}{{\\textit{{Panel A. Pooled age-group interactions}}}} \\\\
    Age group & Estimate (SD) & $p$ \\\\
    \\midrule
{chr(10).join(lines_a)}
    \\midrule
    \\multicolumn{{3}}{{l}}{{\\textit{{Panel B. Under-23 interaction by season}}}} \\\\
    Season & Estimate (SD) & $p$ \\\\
    \\midrule
{chr(10).join(lines_b)}
    \\bottomrule
  \\end{{tabular}}

  \\vspace{{4pt}}
  {{\\footnotesize\\itshape Note: the pooled under-23 estimate rests on {tot_b_rows}
  Bosman player-months and is significant in no single season, declining
  monotonically as coverage improves.\\par}}
\\end{{table}}
""")

# ---------- tab_rejected ----------
rdd = rows(os.path.join(REG, "fotmob_rdd_results.csv"))
rob = rows(os.path.join(REG, "fotmob_rdd_robustness.csv"))
reg = rows(os.path.join(REG, "fotmob_regression_results.csv"))
head = pick(rdd, sample_name="source_league", outcome_name="fotmob_minutes_weighted_rating",
            cutoff_days="180", bandwidth_days="30")
plc = [r for r in rob if r.get("check_type") == "placebo_cutoff"
       and r["sample_name"] == "source_league" and r["outcome_name"] == "fotmob_mean_rating"
       and r.get("cutoff_days") in ("150", "210")]
plc = {r["cutoff_days"]: r for r in plc}
post = pick(reg, model_name="observed_renewal_status_fe", sample_name="all_comps_strict",
            outcome_name="z_mean_rating_league_season", term="post_observed_renewalTRUE")
sign_m = pick(reg, model_name="observed_renewal_status_fe", sample_name="all_comps_strict",
              outcome_name="z_mean_rating_league_season", term="signed_new_contractTRUE")
write("tab_rejected.tex", f"""% Rejected designs: RDD and renewal (auto-generated)
\\begin{{table}}[htbp]
  \\centering
  \\caption{{Rejected designs retained as negative exhibits.}}
  \\label{{tab:rejected}}
  \\begin{{tabular}}{{llrr}}
    \\toprule
    Design & Test & Estimate & $p$ \\\\
    \\midrule
    \\multicolumn{{4}}{{l}}{{\\textit{{Panel A. RDD at 180 days to expiry (0--10 scale)}}}} \\\\
    RDD & Headline (30-day bw)   & {num(head['estimate'], 1, sign=True)} & {pval(head['p_value'])} \\\\
    RDD & Placebo cutoff 150 d   & {num(plc['150']['estimate'], 2, sign=True)} & {pval(plc['150']['p_value'])}    \\\\
    RDD & Placebo cutoff 210 d   & {num(plc['210']['estimate'], 2, sign=True)} & {pval(plc['210']['p_value'])}    \\\\
    \\midrule
    \\multicolumn{{4}}{{l}}{{\\textit{{Panel B. Contract renewal (standardised rating)}}}} \\\\
    Renewal & Post-renewal (pooled) & {num(post['estimate'], sign=True)} & {pval(post['p_value'])} \\\\
    Renewal & Signing month (pooled) & {num(sign_m['estimate'], sign=True)} & {pval(sign_m['p_value'])}    \\\\
    Renewal & Within-season estimates & \\multicolumn{{2}}{{c}}{{all n.s.}} \\\\
    Renewal & Event study ($+4$ to $+6$m) & $+0.08$ & -- \\\\
    \\bottomrule
  \\end{{tabular}}

  \\vspace{{4pt}}
  {{\\footnotesize\\itshape Note: the RDD headline is a slope-extrapolation
  artefact (raw means differ by $0.08$ in the opposite direction); placebo
  cutoffs fire, and covariate balance fails near the threshold. The pooled
  renewal coefficients are contradicted by within-season estimates and the
  event-time path (mean reversion).\\par}}
\\end{{table}}
""")

# ---------- tab_robustness ----------
ar = rows(os.path.join(REG, "fotmob_additional_robustness.csv"))
pos1 = pick(ar, exercise="position_standardized", note="player+Month FE")
pos2 = pick(ar, exercise="position_standardized", note="spell+league-month FE")
lee = {r["note"]: r for r in ar if r["exercise"] == "lee_bound"}
lo = float(lee["lower bound (trim control group, league-month FE)"]["estimate"])
hi = float(lee["upper bound (trim control group, league-month FE)"]["estimate"])
ref = float(lee["untrimmed reference (league-month FE)"]["estimate"])
write("tab_robustness.tex", f"""% Robustness of the intensive-margin null (auto-generated)
\\begin{{table}}[htbp]
  \\centering
  \\caption{{Robustness of the intensive-margin null.}}
  \\label{{tab:robustness}}
  \\begin{{tabular}}{{lrr}}
    \\toprule
    Check & Estimate (SD) & $p$ \\\\
    \\midrule
    Two-way clustering (player, month)        & \\multicolumn{{2}}{{c}}{{unchanged}} \\\\
    Position-cell standardisation (player $+$ month) & {num(pos1['estimate'], sign=True)} & {pval(pos1['p_value'])} \\\\
    Position-cell standardisation (spell $+$ lg\\,$\\times$\\,m) & {num(pos2['estimate'], sign=True)} & {pval(pos2['p_value'])} \\\\
    Lee-style trimming bounds                 & \\multicolumn{{2}}{{c}}{{$[{lo:+.2f},\\,{hi:+.2f}]$}} \\\\
    Minimum detectable effect ($80\\%$ power)  & \\multicolumn{{2}}{{c}}{{$\\approx {mde:.2f}$ SD}} \\\\
    \\bottomrule
  \\end{{tabular}}

  \\vspace{{4pt}}
  {{\\footnotesize\\itshape Note: Lee bounds trim the over-observed control group
  by its differential observation share within league\\,$\\times$\\,month cells,
  around an untrimmed estimate of ${ref:+.2f}$; they span zero.\\par}}
\\end{{table}}
""")

# ---------- numbers.tex: manuscript macros ----------
panel_manifest = {r["dataset"]: r for r in rows(os.path.join(REPO, "data", "panel", "fotmob_analysis_panel_manifest.csv"))}
master_manifest = {r["dataset"]: r for r in rows(os.path.join(REPO, "data", "master", "fotmob_master_manifest.csv"))}
full = panel_manifest["panel_all_comps"]
strict = panel_manifest["panel_all_comps_strict"]

macros = [
    ("NPanelObs", grp(full["rows"])),
    ("NPanelPlayers", grp(full["unique_players"])),
    ("NPanelClubs", grp(overview["Clubs"])),
    ("NStrictObs", grp(strict["rows"])),
    ("NStrictPlayers", grp(strict["unique_players"])),
    ("NBackfilled", grp(full["rows_backward_filled"])),
    ("NBackfilledStrict", grp(strict["rows_backward_filled"])),
    ("NBosmanObs", grp(overview["Bosman-window observations"])),
    ("NMatchRatings", grp(master_manifest["match_master"]["rows"])),
    ("NCrosswalkPlayers", grp(master_manifest["monthly_all_comps"]["unique_tm_players"])),
    ("FirstMonth", overview.get("First month", "")[:7]),
    ("LastMonth", overview.get("Last month", "")[:7]),
]
write(
    "numbers.tex",
    "% Auto-generated manuscript numbers (make_latex_tables.py). \\input this once\n"
    "% in the preamble; never hard-code these counts in the text.\n"
    + "".join(f"\\newcommand{{\\{n}}}{{{v}}}\n" for n, v in macros),
)

print("done")
