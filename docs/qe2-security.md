# QE2 — Security & Compliance

Privacy manifest correction, StoreKit transaction hardening, data integrity
guardrails, and ATT/tracking compliance.

---

## Why Now

The App Store review process has tightened significantly around privacy
manifests and data-use declarations.  The current `PrivacyInfo.xcprivacy` is
in direct conflict with the running code — a mismatch that is grounds for
rejection on the next submission.  Fixing it now, before any wider distribution
push, is cheaper than an emergency remediation under reviewer pressure.

---

## Scope Overview

| Area | Priority | Effort |
|---|---|---|
| Privacy manifest correction | 🔴 High | Small |
| ATT / tracking declaration | 🔴 High | Small |
| StoreKit transaction verification | 🔴 High | Small |
| Coin mutation integrity | 🟡 Medium | Small |
| Bundle-exclusive enforcement | 🟡 Medium | Small |
| UserDefaults sensitive-field audit | 🟡 Medium | Small |
| Anti-cheat coin bound validation | 🟢 Low | Small |

---

## 1 · Privacy Manifest Correction (CRITICAL)

### Current state

`RollAlong/PrivacyInfo.xcprivacy` currently declares:

```xml
<key>NSPrivacyTracking</key>
<false/>
<key>NSPrivacyCollectedDataTypes</key>
<array/>   <!-- empty -->
```

The comment block in the file reads *"No analytics, no ad SDKs."*

This is **false**.  The codebase contains:

- `AnalyticsClient.swift` — fires `app_launch`, `level_complete`, `level_fail`,
  `iap_purchased`, `iap_failed`, `cosmetic_purchased`, `pack_purchased`,
  `att_response`, and all game round events.
- `AdManager.swift` — manages ad lifecycle with events `ad_impression`,
  `ad_rewarded`, `ad_failed`.

Both are compiled into the production binary and call their respective SDKs.

**If Apple's automated scanner detects analytics or ad APIs in the binary while
the manifest declares none, the submission will be rejected.**

### Required changes

**`PrivacyInfo.xcprivacy`**

1. Set `NSPrivacyTracking` to `<true/>` if ATT is solicited (see §3 below);
   leave `<false/>` only if analytics are purely first-party and no IDFA/IDFV
   is passed to third parties.
2. Populate `NSPrivacyCollectedDataTypes` with the actual data categories in
   use.  At minimum:

   | `NSPrivacyCollectedDataType` | Linked to Identity | Used for Tracking |
   |---|---|---|
   | `NSPrivacyCollectedDataTypeGameplayContent` | No | No |
   | `NSPrivacyCollectedDataTypePurchaseHistory` | No | No |
   | `NSPrivacyCollectedDataTypeCrashData` | No | No |

   If the analytics backend receives any device identifier, add
   `NSPrivacyCollectedDataTypeDeviceID` with appropriate flags.

3. Populate `NSPrivacyAccessedAPITypes` for any accessed APIs (e.g.,
   `NSPrivacyAccessedAPICategoryUserDefaults` for `GameState` persistence).

4. Remove or correct the misleading comment.

**Files:** `RollAlong/PrivacyInfo.xcprivacy`

---

## 2 · Analytics SDK Declaration

### Current state

`AnalyticsClient.swift` uses an analytics SDK (Mixpanel or equivalent — confirm
by checking the `import` statement and `Podfile`/`Package.swift`).  Third-party
SDK privacy manifests must be bundled by the SDK vendor; verify the SDK version
in use ships its own `.xcprivacy` manifest.  If it does not, the app must
declare the SDK's data use in the top-level manifest instead.

### Required changes

1. Identify the analytics SDK and its current version.
2. Confirm that version ships a privacy manifest (check the vendor's release
   notes or inspect the framework bundle for `PrivacyInfo.xcprivacy`).
3. If the SDK does NOT ship a manifest, add its declared API accesses and data
   types to `RollAlong/PrivacyInfo.xcprivacy`.
4. Same audit for the ad SDK used in `AdManager.swift`.

**Files:** `Podfile` or `Package.swift`, `RollAlong/PrivacyInfo.xcprivacy`

---

## 3 · ATT / Tracking Declaration

### Current state

`AnalyticsClient.swift` fires an `att_response` event, implying
`AppTrackingTransparency.requestTrackingAuthorization` is called somewhere.
`NSPrivacyTracking` is currently `<false/>`.

### Required changes

1. Search for `ATTrackingManager.requestTrackingAuthorization` in the codebase.
2. If it is called:
   - Set `NSPrivacyTracking = <true/>` in the manifest.
   - Confirm `NSUserTrackingUsageDescription` is set in `Info.plist` with a
     clear, user-facing explanation (e.g., *"Used to measure ad performance and
     personalise your experience"*).
   - The ATT prompt must be shown **after** the app's own onboarding, not on
     cold launch.
3. If it is **not** called but `att_response` is fired with the system value
   obtained without the prompt:
   - Remove the event or gate it behind an explicit user permission check using
     `ATTrackingManager.trackingAuthorizationStatus`.
   - If the app intentionally avoids the prompt and uses only first-party data,
     confirm no cross-app tracking occurs and document this decision.

**Files:** `AnalyticsClient.swift`, `Info.plist`, `RollAlong/PrivacyInfo.xcprivacy`

---

## 4 · StoreKit Transaction Verification

### Current state

`StoreKitManager.swift` uses StoreKit 2 (`Product.purchase()`).  SK2 returns
a `VerificationResult<Transaction>` that must be unwrapped with
`.payloadValue` — which throws if Apple's signature verification fails —
before granting entitlements.

Risk: if the result is unwrapped with `try? result.payloadValue` or the
`unverified` case is not handled, a tampered transaction could unlock content.

### Required changes

1. Audit every `VerificationResult` unwrap in `StoreKitManager.swift`.
2. Replace any `case .unverified` branch that grants coins/cosmetics with an
   explicit failure path:

```swift
let transaction: Transaction
switch result {
case .verified(let t):   transaction = t
case .unverified(_, let e):
    Analytics.track("iap_verification_failed", ["error": e.localizedDescription])
    return // do NOT grant entitlement
}
```

3. Confirm `Transaction.currentEntitlements` is used at launch to restore
   non-consumable purchases (ball skins, packs) so restores work without a
   network call.

**Files:** `StoreKitManager.swift`

---

## 5 · Coin Mutation Integrity

### Current state

All `coins` mutations go through `GameState.addCoins(_:)` — confirmed by
codebase grep.  No direct `gameState.coins +=` calls exist outside this method.

### Required changes

1. Confirm `addCoins` applies a floor of `0` (no negative balance) and a
   reasonable ceiling (e.g., `min(newValue, 999_999)`) to prevent overflow or
   absurd balances from bugs.
2. Add a `precondition(amount >= 0)` guard (debug-only) so accidental negative
   adds surface during development rather than silently reducing balance.
3. Confirm the `addCoins` path calls `gameState.save()` (or marks it dirty for
   the background-save path added in QE1) so coin gains are not lost on sudden
   termination.

```swift
func addCoins(_ amount: Int) {
    precondition(amount >= 0, "Use spendCoins(_:) for deductions")
    coins = min(coins + amount, 999_999)
    // QE1: save() call goes here (or mark dirty)
}
```

**Files:** `GameState.swift`

---

## 6 · Bundle-Exclusive Enforcement

### Current state

`isBundleExclusive` is enforced in the `CosmeticShopView` grid filter —
bundle-only skins are hidden from the individual shop.  However, the
**equip path** also needs a guard: if a user somehow has a skin marked
`isBundleExclusive` in their owned list (e.g., via an old data migration or
corrupted state), they should still be able to equip it (possession implies
legitimate acquisition), but they should not be able to see or purchase it
individually.

### Required changes

1. Verify `CosmeticShopView` individual-item grid uses `!isBundleExclusive`
   filter — confirmed present, no change needed.
2. Verify the equip/select path in `CosmeticShopView` (or wherever equipped
   skin is set) does **not** block equip for owned bundle-exclusive skins.
3. Verify that the bundle purchase flow (`PackPurchaseSheet` or equivalent)
   marks bundle skins as `owned` in `GameState.ownedSkins` **atomically** —
   all skins in a bundle should be granted together; partial grants on
   interrupted purchases must not persist.

**Files:** `CosmeticShopView.swift`, `StoreKitManager.swift`, `GameState.swift`

---

## 7 · UserDefaults Sensitive-Field Audit

### Current state

`GameState` persists all player data to `UserDefaults`.  UserDefaults is
unencrypted and backed up to iCloud by default.

### Required changes

1. Enumerate every key written to `UserDefaults` in `GameState.swift`.
2. Classify each key:
   - **Non-sensitive game state** (level, coins, ownedSkins): UserDefaults is
     acceptable.
   - **Privacy-relevant** (e.g., any field that could identify the user or
     store a tracking token): move to `Keychain` or add
     `NSFileProtectionComplete` to the stored file.
3. Confirm no auth tokens, device IDs, or ad identifiers are stored in
   UserDefaults.
4. If `NSUbiquitousKeyValueStore` (iCloud KV sync) is used anywhere, audit
   what is synced — coins and progress syncing across devices is fine;
   tracking identifiers must not sync.

**Files:** `GameState.swift`

---

## 8 · Anti-Cheat Coin Bound Validation

### Current state

Coin rewards are computed from game logic (score multipliers, level bonuses).
No server-side validation exists (single-player game).

### Required changes

1. Add a maximum single-award ceiling in `addCoins`:
   - No single call should grant more than `5_000` coins (adjust based on
     highest legitimate reward path).
   - If `amount > maxSingleAward`, log a `Debug` warning and clamp — do not
     crash, as this may be a legitimate configuration change in future.
2. Add a sanity check at `GameState` load time: if `coins > 999_999`, reset
   to `999_999` and log a warning.  Prevents corrupt saves from displaying
   absurd balances.

**Files:** `GameState.swift`

---

## Files Touched

| File | Change |
|---|---|
| `RollAlong/PrivacyInfo.xcprivacy` | Correct `NSPrivacyTracking`, populate `NSPrivacyCollectedDataTypes` and `NSPrivacyAccessedAPITypes` |
| `Info.plist` | Confirm / add `NSUserTrackingUsageDescription` if ATT is used |
| `AnalyticsClient.swift` | Gate `att_response` on explicit permission status |
| `StoreKitManager.swift` | Harden `VerificationResult` unwrap; audit `currentEntitlements` restore |
| `GameState.swift` | `addCoins` floor/ceiling/precondition; UserDefaults key audit; load-time sanity |

---

## Acceptance Criteria

- [ ] `PrivacyInfo.xcprivacy` `NSPrivacyCollectedDataTypes` is non-empty and reflects actual data use
- [ ] No analytics or ad SDK API access is undeclared in the manifest
- [ ] `NSUserTrackingUsageDescription` is present in `Info.plist` if ATT prompt is ever shown
- [ ] `StoreKitManager` never grants entitlements on `.unverified` transaction results
- [ ] `addCoins` enforces `0 ≤ amount ≤ maxSingleAward` and `0 ≤ coins ≤ 999_999`
- [ ] No auth tokens or device identifiers are stored in unencrypted UserDefaults
- [ ] Bundle purchases grant all skins atomically — no partial grant on cancellation
