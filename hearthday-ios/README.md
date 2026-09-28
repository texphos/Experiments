# Hearthday

A native iPhone app (Swift/SwiftUI, iOS 17) for home sourdough bakers with a weekday job. It plans a bake around recurring busy times. When the dough runs fast or slow, a 10-second rise check turns into a few constraint-aware options, each with an honest finish time. Estimates learn from the baker's own "just right" bakes.

**Status: validation MVP, not released.** Start with [docs/strategy.md](docs/strategy.md), which covers the market, the retracted novelty claim, the hypothesis being tested and the business-scale limits.

## Verification status

| Check | Result | How to reproduce |
|---|---|---|
| Core unit tests (`HearthdayCore`, 44 XCTest cases) | **Pass** on Swift 6.1.2, Linux | `cd Core && swift test` |
| Swift → JS parity (fixtures regenerated from Swift; 15 checks) | **Pass**; the fixtures are byte-identical after regeneration | `cd Core && swift run -q hearthday-fixtures > ../prototype/fixtures.json && node ../prototype/parity.test.js` |
| Prototype end-to-end in headless Chrome (onboarding → plan → check-in → option → finish → journal → infeasible) | **Pass**, no console errors | The script used puppeteer-core outside the repo and isn't committed. Walk the same path by hand with `python3 -m http.server -d prototype 8765`. |
| SwiftUI app sources | **Syntax check only** (`swiftc -parse`). **Not compiled or type-checked.** | Needs a Mac with Xcode 16 or later |
| Run in simulator or on device, StoreKit sandbox, notifications, VoiceOver | **Not done**: Xcode and the iOS Simulator are unavailable in the authoring environment (Linux) | See "Open on a Mac" |

## Layout

- `Core/`: a Foundation-only Swift package with the planner, fermentation model, live re-planning, calibration, reminders and persistence. This is where the logic and the tests live.
- `App/Hearthday/`: the SwiftUI app (views, `AppModel`, notifications, StoreKit 2 `ProStore`, theme). `project.yml` is the XcodeGen spec.
- `prototype/`: **a browser companion prototype, not the native app.** It is a JS port of the core, parity-tested against Swift, inside a phone-shaped mock UI with a simulated clock. A permanent banner says it isn't the iOS app.
- `docs/`: strategy, research sources, design, architecture, pricing and economics (`economics.py`), validation experiments, launch plan, roadmap, and `drafts/` (store listing, privacy policy, recruitment post, interview guide), all **unsent**.

## Open on a Mac

```bash
brew install xcodegen
xcodegen generate
open Hearthday.xcodeproj
```

The scheme uses `App/Hearthday/Resources/Hearthday.storekit` for local purchase testing (a non-consumable `app.hearthday.pro` at a proposed $9.99). Expect a few compile fixes on first build, because the app layer has never been compiled.

## What has not been done (by design)

No money spent, no developer account, no domain, no App Store submission, no public deployment, no contact with prospective users and no legal agreements. These steps are prepared as drafts in `docs/` and marked **[owner approval]** in the launch plan.

## Disclaimer

Timings are planning estimates from temperature, inoculation and the baker's own history. They are not guarantees, and the app makes no food-safety or health claims.
