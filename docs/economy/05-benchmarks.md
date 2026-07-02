# 05 — External benchmarks: how the industry calibrates this

From an adversarially-verified research pass (5 search angles, 20 sources
fetched, 92 claims extracted, 25 put to 3-vote verification, **6 killed**).
Only claims that survived are below; the killed ones are listed at the bottom
because several are "common wisdom" we should *not* rely on.

## The ten surviving findings → design rules for Roll Along

1. **Sources/sinks accounting is the discipline** *(high confidence — GDC/
   Lehdonvirta, corroborated by Unity/Machinations/MFTP)*. In a cosmetics-only
   economy, inflation shows up as **hoarded balances and dead sinks**, not
   prices. Keep coins tight enough that cosmetic prices are real decisions.
   → Our single-sink structure makes this fragile: one exploit (graphite) or
   farm (tracks) floods the whole system.

2. **The spreadsheet method** *(3-0)*: model an average player's
   sessions-to-reward curve and validate against explicit min/max bounds
   (balance, daily sessions). **Set target minutes-of-play per rarity tier
   FIRST, then derive per-mode payouts and prices** — never pick payout
   numbers directly. → This is the core method for our calibration sprint
   (workstream A builds the simulator).

3. **Top games do NOT normalize coins/min across modes — they cap the day**
   *(high — Nintendo primary source)*. Mario Kart Tour caps race coins at
   300/day (600 with Gold Pass — monetizing the earn *rate* itself), leaving
   login/challenge bonuses uncapped as deliberate deviations.
   → Nuances our equity goal: tighten the per-mode band (the 14× spread is
   still indefensible), but the *proven control surface* is a *daily soft cap
   or diminishing returns*, not per-minute equalization. A cap also future-
   proofs a Gold-Pass-style product.

4. **Rarity price curves: geometric ~2.5× steps, flat within tier** *(Brawl
   Stars prestige line: 10,000 → 25,000)*. → Our 0/50/100/200/500 ladder
   (×2/×2/×2.5) is structurally right. The fix is category *rung*
   standardization, not the curve.

5. **Visible rarity is a price-commitment device** *(Fortnite removed rarity
   labels in 2024 → player backlash over expected price gouging)*. Players
   read tier↔price coupling as "the rules." → Keep our tier badges hard-wired
   to fixed prices; never price per-item within a tier.

6. **Bundles should be priced BELOW the sum of contents** *(high — Epic's own
   help center: bundles discounted vs sum AND further discounted for owned
   items)*. Industry pattern ≈ 20–40% off sum. → **Direct counterpoint to our
   prorated-equals-sum bundles.** Recommendation: visible ~20% bundle discount
   on top of proration. Interaction warning: with our 100% sell-back refund
   this creates an arbitrage loop — pair any bundle discount with
   refund-what-you-paid (or an 80% refund rate).

7. **Coin-pack ladder design** *(merged, 3-0×3)*: ~6 tiers; the $0.99–$2.99
   pack is a **conversion device, not a revenue driver**; the largest pack
   carries the biggest bonus (~30%+) and generates the most revenue
   (whale-driven); bonus % must increase monotonically with size.
   → Our ladder's coins-per-dollar already rises monotonically
   (101→120→130→150→200/$) but we never *display* the bonus. Show "+X%" badges;
   treat coins100's job as first-purchase conversion, not value.

8. **Endowed progress effect** *(high — primary JCR field experiment)*:
   pre-filled progress raised completion 19%→34%. Works best when the
   head-start is justified and denominated in points. → Pre-fill coin-goal
   meters ("Welcome bonus: 200/1,000 toward your first Epic"), frame streaks
   and any piggy-bank as already-started. Cheap, ethical, proven.

9. **Loyalty-program analogue** *(the one cross-domain claim that survived)*:
   a currency's worth is set entirely by its **redemption menu** — real
   loyalty points span 0.4–2.2¢/point (5.5×) purely from what redemptions
   cost. → The anchor chain for all our numbers:
   **target minutes-per-tier → cosmetic prices → per-mode payouts → coin-pack
   sizing.** In that order. (Same chain as finding 2, independently derived.)

10. **Single-currency is a legitimate deviation** *(2-1)* — Candy Crush ran
    it successfully — but it removes the hard/soft exchange-rate buffer:
    coin-pack pricing *directly* prices every earn rate and cosmetic.
    → Raises the stakes on free-rate caps (finding 3) so purchased coins
    retain meaning.

## What did NOT survive (do not build on these)

| Refuted claim | Vote |
|---|---|
| Fortnite per-tier price tables (Common 200–500 … Legendary 1,500–2,000) | 0-3 |
| Fortnite tier steps are ~1.25–1.33× (sub-linear) | 1-2 |
| Brawl Stars normalizes earn rates via mode-agnostic wrappers | 0-3 |
| "Match sink removal rates to source generation rates" as the core rule | 0-3 |
| Flow-network model with price + drop-probability as the two levers | 0-3 |
| TPG valuation formula as directly transferable | 1-2 |

**Honest gaps the research could not fill** (feed the sprint plan):
- No verified coins/min numbers exist for comparable titles → our target grind
  times must be set from first principles (spreadsheet method), not copied.
- No verified $-per-hour-saved fairness band → treat our $3–6 target as a
  hypothesis to A/B, not a benchmark.
- Whether any studio truly normalizes per-mode earn rates is an open question
  → our own `minigame_result` telemetry will answer it for our player base
  better than any external source.
- Energy-system IAP calibration (lives packs, unlimited-lives) had no
  surviving claims → calibrate from our own data (Diamond breakeven model in
  [03-iap-value.md](03-iap-value.md)).

## Sources (survivors' anchors)
GDC Vault (Lehdonvirta 2014) · mobilefreetoplay.com economy bible ·
Nintendo's Mario Kart Tour FAQ (primary) · Epic Games help center (primary) ·
Journal of Consumer Research (endowed progress, primary) · Brawl Stars/MKT
wikis (corroborated) · Game Developer (IAP pack design) · TPG/UpgradedPoints
loyalty valuations. Full source table with per-claim votes retained in the
research run (wf_dc90ae2a-911).
