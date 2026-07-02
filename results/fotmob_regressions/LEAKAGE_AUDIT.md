# Leakage Audit: FotMob Contract Regressions

## Main assessment

The biggest leakage risk was in the renewal variables, not in the expiry bins. The main regression script has now been changed so the primary outputs no longer use future-derived renewal timing.

The removed leaky design computed renewal timing with the full observed player path:

- `ever_signed_new_contract`: true for every row of a player if that player signs at any observed future point.
- `first_sign_month`: first observed signing month in the full sample.
- `post_new_contract`: rows at or after that future-derived signing month.
- `sign_bin_6m`: months relative to that future-derived signing month.

Those variables are not safe for predictive or main causal specifications because they use future information.

The repaired renewal specification uses:

- `signed_new_contract`: true only in a player-month where the observed `ContractExpiryDate` jumps by more than 90 days relative to the prior player-month.
- `post_observed_renewal`: true only after a renewal has already been observed in a prior player-month.
- `renewal_status`: a descriptive grouping into `no_observed_renewal_yet`, `signing_month`, and `post_observed_renewal`.

This does not make renewal estimates causal by itself, but it removes the direct look-ahead problem from the generated regression outputs.

The canonical repaired summary file is `fotmob_observed_renewal_summary.csv`. The old `fotmob_renewal_6m_summary.csv` filename is retained as a compatibility copy with the same safe contents.

## Safer variables

The following variables are contemporaneous contract-status measures and are safer for the main expiry analysis:

- `DaysToExpiry`
- `Bosman`
- `expiry_bin_6m`
- `final_180`
- `expiry_window`
- `signed_new_contract`
- `post_observed_renewal`

The panel construction rolls the latest available contract snapshot forward to the player-month, and the strict all-competitions panel currently has:

- `rows where Date_scraped != Month`: 0
- `negative DaysToExpiry`: 0
- `Date_scraped after ContractExpiryDate`: 0

That does not prove the snapshots are perfect, but it rules out the obvious mechanical leak where future-dated contract rows are joined to earlier months.

## Interpretation rule

Use the Bosman, expiry-bin, threshold, and RDD outputs as the main contract-expiry evidence.

The repaired renewal output can be discussed as an observed-status association, with language like:

> Renewal status is measured only from contract extensions already observed by the player-month. These estimates should still be read as associations, not as causal renewal effects.
