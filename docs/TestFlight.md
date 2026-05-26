# TestFlight + App Store Submission — Roll Along

Step-by-step setup for shipping to TestFlight, then to the App Store.
Treat this as a one-time onboarding checklist; bookmark for repeat
release runbooks later.

---

## Phase 0 — Prerequisites (one-time)

### 0.1 Apple Developer Program
- Enroll at https://developer.apple.com/programs/
- Cost: **$99/year**, paid annually.  Tax-deductible business expense.
- Approval takes 24-48 hours.  Use your real legal name + Apple ID.

### 0.2 App Store Connect account
- Auto-created when Developer Program enrollment completes.
- Sign in at https://appstoreconnect.apple.com
- Accept agreements: Apple Developer Program, Paid Apps (even though
  Roll Along starts free — needed if you ever charge).

### 0.3 Bundle identifier
Current bundle ID is in `RollAlong.xcodeproj/project.pbxproj`
as `PRODUCT_BUNDLE_IDENTIFIER`.  Today it's the default Xcode value.
Before submitting:
- Set a unique reverse-DNS ID, e.g. `com.faldet.rollalong`.
- Register that ID in App Store Connect → Identifiers.

---

## Phase 1 — App Store Connect record

### 1.1 Create the app record
1. App Store Connect → My Apps → "+" → New App.
2. Platforms: iOS.
3. Name: **Roll Along**.
4. Primary language: English (U.S.).
5. Bundle ID: select the one you registered.
6. SKU: any unique string, e.g. `ROLLALONG-001`.
7. User Access: Full Access.

### 1.2 Fill in metadata
Use `docs/AppStore.md` in this repo as the source of truth.  Paste
into:
- App Information → Name, Subtitle, Category
- Pricing and Availability → Free, all regions (for V1)
- App Privacy → No data collected (matches `PrivacyInfo.xcprivacy`)
- 1.0 Prepare for Submission → Description, Keywords, Promo text,
  Support URL, Privacy Policy URL, Screenshots, App Preview Video

### 1.3 Screenshots
Per `docs/AppStore.md`.  Apple requires at least one device size.
Submit for 6.9" iPhone (1320 × 2868) and Apple scales for others.
Capture on a real device — simulator works but real device is crisper.

---

## Phase 2 — Code signing

### 2.1 Automatic signing (recommended)
1. Open `RollAlong.xcodeproj` in Xcode.
2. Select RollAlong target → Signing & Capabilities.
3. Check "Automatically manage signing".
4. Team: select your developer team (appears after Developer Program
   enrollment).
5. Xcode generates the signing certificate + provisioning profile
   automatically.

### 2.2 Manual signing (only if automatic fails)
1. App Store Connect / Developer portal → Certificates, Identifiers
   & Profiles.
2. Create an iOS Distribution certificate.
3. Create an App Store provisioning profile linked to your bundle ID
   + distribution cert.
4. Download both, double-click to install in Keychain.
5. In Xcode, uncheck "Automatically manage signing" and select your
   profile.

---

## Phase 3 — First TestFlight build

### 3.1 Manual upload via Xcode (simplest)
1. Bump version + build in Xcode → Target → General:
   - Version: `1.0.0`
   - Build: `1` (increment for each upload)
2. Product → Destination → **Any iOS Device (arm64)**.
3. Product → **Archive**.
4. When the Organizer opens: Distribute App → App Store Connect →
   Upload → Next, Next, Upload.
5. Build appears in App Store Connect → TestFlight → iOS Builds
   after 10-30 minutes processing.

### 3.2 Automated via Xcode Cloud (recommended for repeat releases)
- Xcode → Product → Xcode Cloud → Create Workflow.
- Trigger: push to `main` branch.
- Action: Archive → distribute to TestFlight (internal group).
- Includes automatic build number increment.
- Free for 25 compute hours/month — plenty for this project.

### 3.3 Automated via fastlane (alternative, more flexible)
- `gem install fastlane`
- `cd RollAlong.xcodeproj && fastlane init`
- Configure `Fastfile`:
  ```ruby
  lane :beta do
    increment_build_number(xcodeproj: "RollAlong.xcodeproj")
    build_app(scheme: "RollAlong")
    upload_to_testflight
  end
  ```
- Run `fastlane beta` to ship a build.

---

## Phase 4 — TestFlight testing

### 4.1 Internal testing (no Apple review required)
- Up to 100 internal testers.
- App Store Connect → TestFlight → Internal Testing → Create Group.
- Add testers by Apple ID email.  They get an invite to install
  via the TestFlight app on iOS.
- Builds are immediately available.

### 4.2 External testing (requires beta review, ~24-48hr first time)
- Up to 10,000 external testers via a public link.
- Beta review is lighter than App Store review — usually clears
  within a day.  Re-submissions after the first build are typically
  instant.
- Useful for friends, family, beta community, Indie iOS Devs Discord,
  etc.

### 4.3 What to look for in beta
- Cold-launch flow → onboarding overlay → first level.
- "Roll Along friend!" moment after clearing L1.
- Coin pickup feel, star award accuracy.
- Audio feels right (system sounds are placeholders — note this in
  beta release notes).
- VoiceOver navigation through home, settings, levels grid.
- Reduce Motion enabled → confirm ball is easier to control + no
  shimmer + no screen shake.
- Cross-device feel: small iPhone vs. Pro Max ergonomics.

---

## Phase 5 — App Store submission

### 5.1 Pre-submission checklist
- [ ] All metadata fields filled per `docs/AppStore.md`.
- [ ] 6 screenshots uploaded (6.9" iPhone).
- [ ] App preview video uploaded (optional but recommended).
- [ ] Privacy policy URL live + reachable.
- [ ] Support URL live + reachable.
- [ ] `PrivacyInfo.xcprivacy` in the build (verify in `RollAlong.app`
      after archive).
- [ ] `NSMotionUsageDescription` in `Info.plist` (already present).
- [ ] Version 1.0.0, build > 1 (assume initial TestFlight was build 1).
- [ ] Tested on a real device end-to-end at least once.

### 5.2 Submit for review
1. App Store Connect → Roll Along → 1.0 Prepare for Submission.
2. Build: select the TestFlight-tested build.
3. Save → Add for Review → Submit for Review.
4. Status changes to "Waiting for Review".

### 5.3 Review timeline
- Typically **24-72 hours** for initial submission.
- Apple reviewer plays through the app + checks metadata.
- Common reject reasons (and how Roll Along is already covered):
  - Missing privacy policy URL → make sure it's live.
  - Missing motion usage string → present in Info.plist.
  - Crash on launch → tested via TestFlight.
  - Metadata mismatch (screenshots show features not in the build)
    → screenshots reflect actual gameplay.

### 5.4 If rejected
- Reviewer leaves notes in Resolution Center.
- Reply with fix in the message OR upload a new build addressing the
  issue.
- Re-review usually clears within 24hr.

### 5.5 Approval + release
- "Pending Developer Release" if you chose manual release.
- Tap "Release this version" — Roll Along goes live globally within
  ~2 hours.
- Or set automatic release at approval time.

---

## Phase 6 — Post-launch operations

### 6.1 Crash reporting
- App Store Connect → Analytics → Crashes.
- Or integrate Sentry SDK in a future PR for richer stack traces.

### 6.2 Reviews
- Monitor and respond — Apple allows one reply per review.
- Early 5-star reviews help the algorithm; nudge close friends to
  rate after a clean playthrough.

### 6.3 Future updates
1. Create branch off `main`.
2. Make changes + commit.
3. Bump version in Xcode (`1.0.1`, `1.1.0`, etc.).
4. Push branch + open PR.
5. After merge, archive + upload via the same flow.
6. Add release notes in App Store Connect → "What's new".

---

## Quick reference

| Action | Where |
|---|---|
| Enroll in Developer Program | https://developer.apple.com/programs |
| Manage app records | https://appstoreconnect.apple.com |
| Watch beta installs | App Store Connect → TestFlight |
| Privacy policy generator | https://app-privacy-policy-generator.firebaseapp.com |
| Privacy manifest reference | https://developer.apple.com/documentation/bundleresources/privacy_manifest_files |
| Required reason API list | https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api |
