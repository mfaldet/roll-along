# Changelog

Changes to Roll Along that reach players, newest first. Earlier history is in the git log.

## 1.0.1 (build 2026112101)

One bug fix. Nothing else in the game changed.

- **Fixed: "Watch ad" could stay stuck on "Ad not ready yet".** When a rewarded ad failed to load, nothing tried again, so the button did not work until the app was fully closed and reopened. Now:
  - A failed load is tried again by itself after 10 seconds, 30 seconds, 60 seconds, then every 2 minutes, until an ad loads. A successful load starts the waits over.
  - A load also starts when the app returns to the foreground, when the Out of Lives screen appears, and when "Watch ad" is tapped with no ad ready.
  - Only one load runs at a time, and nothing is retried while the app is in the background.
- The `ad_load_failed` analytics event now also records the error's numeric code (`error_code`) and domain (`error_domain`). No database change: both go in the event's existing `properties`.

Not changed: the ad unit IDs, the app ID, the debug and release split, the privacy settings (non-personalized requests, teen treatment, the PG content cap, no tracking prompt) and the reward of one life per completed ad.
