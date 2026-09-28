# Hearthday

A native iPhone app (Swift/SwiftUI, iOS 17+) for home sourdough bakers with a weekday job. It plans a bake around recurring busy times. When the dough runs fast or slow, a 10-second rise check turns into a few constraint-aware options, each with an honest finish time. Estimates learn from the baker's own "just right" bakes.

**Status: implementation-complete MVP, not released.** The app builds, and its unit, StoreKit and UI tests pass on an iOS simulator in CI. What's left is owner work that needs an Apple Developer account, signing and a physical device (see [Release blockers](#release-blockers)). Start with [docs/strategy.md](docs/strategy.md) for the market, the retracted novelty claim, the hypothesis being tested and the business-scale limits.

## What's in the MVP

| Area | What it does |
|---|---|
| The loop | Onboarding → plan (feasible, infeasible with the earliest time that fits, or invalid input) → start → live bake → dough check-in → re-plan options → finish → rate → journal. |
| Persistence | Atomic JSON writes after every change. The file is versioned. Older files open with defaults, damaged values are repaired, unreadable or newer-version files are set aside (never overwritten) with a banner, and dates round-trip exactly. |
| Recovery | On launch and every foreground, the app refreshes the clock, calendar and reminders. Missed steps show as overdue, and bakes long past their finish ask whether they finished. |
| Notifications | Every pending reminder is replaced after each change (start, step done, re-plan, finish, abandon). Triggers are time-interval based, so they fire at the right moment after a time-zone change. The "check your dough" nudge is suppressed during busy times and while the dough is in the fridge. If notifications are denied, a banner links to Settings. |
| Time zones and DST | Busy blocks are wall-clock rules whose end is computed as a local calendar time, never start plus a fixed duration. Skipped and repeated times resolve deterministically. See [architecture](docs/architecture.md#time-zones-and-daylight-saving). |
| Input handling | Temperatures outside 14–32 °C, ready times in the past or more than 7 days ahead, broken formulas, implausible check-in readings and invalid busy times are all refused with a plain reason. |
| Honest estimates | Fermentation times read as likely windows and straight-line estimates ("Go by the dough"). A test fails if generated copy says "guarantee", "will be ready", "exactly" and so on, or if an estimate reads as "about 0 h". |
| Free and Pro | **Free:** planning around busy times, check-ins and re-planning, reminders, seeing what calibration has learned, 2 formulas, the last 5 journal entries (older ones are kept). **Pro, a $9.99 one-time non-consumable:** personal timing applied to plans, unlimited formulas, the full journal. |
| Purchases | StoreKit 2. Pro unlocks **only** from a verified, unrevoked entitlement. Pending (Ask to Buy), cancelled, failed and unverified purchases never show success, a refund revokes Pro, restore handles "nothing to restore", and a product that can't load shows an explicit unavailable state. The local `.storekit` file is used by the Debug scheme and tests only and is not copied into the app. |
| Accessibility | Dynamic colours for light and dark, text styles only (Dynamic Type), hatching as well as colour for busy time, spoken values on the ribbon, slider and steppers, and 44 pt minimum targets. |

## Run it

### iOS app (Mac with Xcode 16 or later)

```bash
open Hearthday.xcodeproj          # committed; no generator needed
```

Choose the **Hearthday** scheme and an iPhone simulator, then press ⌘R to run or ⌘U to run every test (core, app, StoreKit and UI). No signing team is needed for the simulator. The Run action uses `App/Hearthday/Resources/Hearthday.storekit`, so purchases are local test transactions. Use **Debug → StoreKit → Manage Transactions** to refund or clear them.

From the command line:

```bash
xcodebuild test -project Hearthday.xcodeproj -scheme Hearthday \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO   # any installed iPhone simulator
```

`project.yml` is the source of truth for the project. After changing it, run `xcodegen generate` (XcodeGen 2.44.1) and commit the result. CI fails if they drift apart.

### Core logic only (macOS or Linux, Swift 6)

```bash
cd Core && swift test
```

### Browser companion prototype (Windows, macOS or Linux)

Double-click **`prototype/hearthday-prototype.html`**. It's one self-contained file that works offline, with no install or server. A permanent banner says it is not the iOS app. It runs a JavaScript port of the Swift core with a simulated clock and a panel showing the reminders the iPhone would schedule. Purchases are disabled.

To check or rebuild it:

```bash
cd prototype
node parity.test.js                                   # JS core vs Swift-generated fixtures
python3 build_standalone.py                           # rebuild the single file after editing app.js/core.js/app.css
npm ci && CHROME_PATH=/path/to/chrome node e2e.test.js  # headless end-to-end, light and dark
```

## Verification evidence

CI is in [`.github/workflows/hearthday.yml`](../.github/workflows/hearthday.yml) and runs on every pull-request update.

| Check | Result | Where |
|---|---|---|
| Xcode build and `xcodebuild test`, Xcode 16.4, iPhone 17 Pro simulator (iOS 26.2) | **116/116 pass, none skipped**: 95 core, 10 app-model, 8 StoreKit (`SKTestSession`), and 3 UI tests (full loop in light, full loop in dark, terminate and relaunch mid-bake) | macOS job; screenshots and `.xcresult` uploaded as artifacts |
| Unsigned Release build, generic iOS device | **Pass** | macOS job |
| Committed `Hearthday.xcodeproj` equals XcodeGen output | **Pass** | macOS job |
| `swift test` on Linux (Swift 6.1) and fixtures up to date | **Pass**, 95 tests | Linux job, and locally |
| JS parity with Swift (plans, invalid input, check-in options and wording, reminders after re-plan, scripted bakes with late/early steps, fridge transfer and repeated check-ins, DST windows) | **28/28 pass** | Prototype job, and locally |
| Prototype end-to-end in headless Chrome over `file://` | **48/48 pass**, no script errors | Prototype job, and locally |

The latest run and its artifacts are listed on the pull request's Checks tab. Sensitivity checks:
- The DST tests fail under the old fixed-duration logic: 15 failures in Swift, and the JS DST checks fail too.
- Mutating a fermentation constant fails the parity test.
- Each re-planning integrity fix fails its tests when reverted: the attended fridge transfer, excluding chilled bakes from calibration, the cold-proof bounds after late or early steps, fold pruning, bulk ending before shaping, and refusing check-ins once chilled. This holds in Swift (`ReplanIntegrityTests`) and in the JS parity scripts.

**Not verified** (it needs hardware or an account, not more code):
- Real notification delivery on a locked device.
- An App Store sandbox purchase with a real Apple Account.
- VoiceOver reading order, the largest accessibility text sizes, Reduce Motion and measured contrast.
- Performance on older devices.

## Release blockers

The implementation is complete for the MVP scope. Everything below needs the owner, money or Apple's systems, so none of it has been done.

| Blocker | Why it's owner work |
|---|---|
| Apple Developer Program enrolment (individual vs organisation) | Paid ($99/year; confirm on Apple's page) and a legal choice that sets the seller name |
| Signing team, bundle ID registration (`app.hearthday.ios`), provisioning | Needs the account. `DEVELOPMENT_TEAM` is intentionally empty. |
| Create the `app.hearthday.pro` non-consumable in App Store Connect, set the price, **enable Family Sharing** (the Pro screen says it's supported), and sign the Paid Apps agreement | Account and legal agreement |
| Device validation: notifications while locked, sandbox purchase, restore and refund, a time-zone change mid-bake, VoiceOver, Dynamic Type, Reduce Motion | Needs a physical iPhone and signing |
| App icon, and store screenshots from the native build | Design asset. The app currently has no icon set. |
| Trademark search for "Hearthday" | Legal review |
| Host the privacy policy ([draft](docs/drafts/privacy-policy.md)) and confirm the "Data Not Collected" label against the final build | Needs a public URL and legal review |
| Support contact address, and the in-app "Email the developer" link that depends on it | Needs an address |
| TestFlight beta and the validation experiments E1–E3 ([validation-experiments.md](docs/validation-experiments.md)) | Contacting users is owner-approved only |

## Layout

- `Core/`: a Foundation-only Swift package with the planner, fermentation model, validation, live re-planning, calibration, reminders and persistence. Most of the logic and tests live here.
- `App/Hearthday/`: the SwiftUI app (views, `AppModel`, notifications, StoreKit 2 `ProStore`, theme).
- `App/HearthdayTests/`, `App/HearthdayUITests/`: app-model, StoreKit and UI tests.
- `prototype/`: **a browser companion prototype, not the native app.**
- `docs/`: strategy, research sources, design, architecture, pricing and economics (`economics.py`), validation experiments, launch plan, roadmap, and `drafts/` (store listing, privacy policy, recruitment post, interview guide). All drafts are **unsent**.

## What has not been done (by design)

No money spent, no developer account, no domain, no App Store submission, no public deployment, no contact with prospective users and no legal agreements. These steps are prepared as drafts in `docs/` and marked **[owner approval]** in the launch plan.

## Disclaimer

Timings are planning estimates from temperature, inoculation and the baker's own history. They are not guarantees, and the app makes no food-safety or health claims.
