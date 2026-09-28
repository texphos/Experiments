# Hearthday — architecture

Status: draft for owner review · 2026-09-28

## Shape of the system

```
hearthday-ios/
├── Core/                 SwiftPM package "HearthdayCore": Foundation-only, no UI, fully unit-tested
│   ├── Sources/HearthdayCore/
│   │   ├── Availability.swift   weekly repeating busy blocks, free/busy queries
│   │   ├── Fermentation.swift   temperature/inoculation → bulk, proof, starter-peak durations
│   │   ├── Plan.swift           Plan, PlanStep, step kinds, attended/passive
│   │   ├── Planner.swift        backward search for plans that avoid busy time
│   │   ├── LiveSession.swift    check-ins → re-plan options, calibration samples
│   │   ├── Calibration.swift    per-user speed factor and uncertainty
│   │   ├── Reminders.swift      plan → reminder list (UI-independent)
│   │   ├── Validation.swift     input limits and plain-language problems
│   │   ├── StepText.swift       user-facing step copy
│   │   └── AppState.swift       persisted state, schema version, repair, free/Pro limits, JSONFileStore
│   ├── Sources/hearthday-fixtures/  emits prototype/fixtures.json for JS parity
│   └── Tests/HearthdayCoreTests/    79 XCTest cases (planner, DST, validation, recovery, reminders, copy…)
├── App/Hearthday/        SwiftUI app (iOS 17), built and tested on macOS CI
│   ├── Model/            AppModel (@Observable), NotificationScheduler, ProStore (StoreKit 2)
│   ├── Views/            onboarding, home, plan, live bake, check-in, journal, settings, Pro
│   ├── Design/           Theme (palette, type, components), Formatters
│   └── Resources/        Hearthday.storekit (local StoreKit config; copied into the test bundle only)
├── App/HearthdayTests/   AppModel loop/persistence/reminder tests and SKTestSession StoreKit tests
├── App/HearthdayUITests/ full-loop UI tests in light and dark, relaunch test, screenshots as attachments
├── project.yml           XcodeGen spec; Hearthday.xcodeproj is generated from it and committed
└── prototype/            browser companion (a JS port of Core plus a mock UI), not the native app
                          hearthday-prototype.html is a single-file build that opens offline
```

CI (`.github/workflows/hearthday.yml`) runs three jobs on every pull-request update:

1. **Linux:** `swift test` for the core, and a check that `prototype/fixtures.json` matches what the Swift core generates.
2. **Prototype:** JS parity against those fixtures, a check that the single-file build is current, and a headless-Chrome end-to-end test against the single-file build over `file://`.
3. **macOS:**
   - Regenerate the Xcode project with XcodeGen 2.44.1 and fail on any diff.
   - `xcodebuild test` on an iPhone simulator, covering the core, app unit, StoreKit and UI tests.
   - An unsigned Release build for generic iOS.
   - Export the `.xcresult` screenshots and summary as artifacts.

**Why this split.** All of the logic that could be wrong (time arithmetic, the fermentation model, the planner search, re-planning, calibration, persistence) lives in `HearthdayCore`. That package builds and tests on Linux. The SwiftUI layer is thin: it renders state and forwards intents to `AppModel`.

## Key design choices

| Choice | Reason | Trade-off |
|---|---|---|
| No accounts, backend or analytics | Zero running cost, a simple privacy story ("Data Not Collected" is the target label) and one less thing to fail | No cross-device sync and no usage data. Validation relies on TestFlight feedback and App Store Connect's aggregate metrics. |
| JSON file in Application Support (`JSONFileStore`, atomic writes) | The state is small (a handful of formulas and bakes). It is easy to migrate and inspect. | Not suitable for large histories. SwiftData is an option later. |
| Corrupt file quarantined, not deleted; `schemaVersion` with lenient decoding and `repair()` | Never silently destroy a user's journal. Files from older builds open with defaults, out-of-range values are clamped, and a file from a *newer* build is set aside instead of being overwritten. | The user sees a "started fresh" banner with the reason. If the file can't be moved aside, the app runs **without saving** (the store is held read-only) so the only copy is never overwritten. A non-dismissible banner says so, and every resume retries. The store is attached only after the backup succeeds. If the file becomes readable again, it is left for the next launch. |
| Dates stored as `timeIntervalSinceReferenceDate` doubles | Exact round-trips, so a reopened bake produces identical reminders | Less readable by hand. ISO-8601 strings are still accepted on read. |
| Exhaustive 15-minute grid search in the planner | The search space is small (mix time × proof mode × inoculation × feed ratio). It is deterministic and easy to explain. | It runs off the main thread (`Task.detached`). A 15-minute resolution is enough for bread. |
| Local notifications only (`UNTimeIntervalNotificationTrigger`, `hearthday.` prefix), fully replaced after every state change | No push server. Plan steps are absolute instants, so an interval trigger fires at the right moment even after a time-zone change. Removing all pending requests before adding new ones means a re-planned bake never keeps a stale alert. | Syncs run **one at a time** through a coalescing queue in `AppModel`. While one is in flight, newer states replace each other, so only the latest state goes next and an older plan can't re-add reminders after a re-plan, abandon or reset. The scheduler awaits every `add`, adds nothing unless notifications are allowed, returns the permission it saw, and reports rejected requests (shown on the live screen until a sync succeeds). `start` awaits the permission answer before scheduling. Reminders are rebuilt on launch, on activation, and on time-zone or significant clock changes (`AppModel.resume()`), which also resets Foundation's cached time zone. |
| StoreKit 2 non-consumable, `Transaction.updates` listener, `AppStore.sync` restore | Current Apple API. No receipt server. | Pro is set **only** from a verified, unrevoked entry in `Transaction.currentEntitlements`. A purchase result never unlocks anything by itself, so pending (Ask to Buy), cancelled, failed and unverified results can't show success. If the product can't be loaded, the Pro screen shows an explicit unavailable state. |
| JS port of the core for the prototype, parity-tested against Swift fixtures | The prototype should behave like the real planner rather than a mock | It is a second implementation to keep in sync. The parity test catches drift (confirmed by mutating a constant: 6 of 15 checks failed). |

## Fermentation model (a planning heuristic, not a guarantee)

- Bulk: `hours = 7 / (2.6^((T−21)/10) × (inoc/20)^0.5 × speed)`. Room proof is 2 h at the reference temperature and scales the same way.
- Starter peak at 24 °C: 4.5, 6.5, 9 and 12 h for feed ratios of 1:1:1, 1:2:2, 1:5:5 and 1:10:10.
- The target rise depends on temperature (100% at 18 °C down to 30% at 27 °C, interpolated). **These targets assume a cold retard afterwards.** For same-day room proofs they may be too high.
- Default uncertainty is ±20%. Calibration narrows it to between ±10% and ±30%.
- **The constants disagree with at least one public model.** Sourjoe publishes 3.75 h at 20 °C with Q10 = 2. The two models reflect different assumptions about flour, inoculation and the end point. Neither is authoritative. Calibration exists because no fixed model fits every kitchen.

### What comes from research and what is Hearthday's own heuristic

Only two things above are backed by a cited source ([research-sources.md](research-sources.md), labelled **Fact**): the 21 °C → 75% and 27 °C → 30% rise targets, and the fact that published bulk-time models disagree. Everything else is a **numerical heuristic** chosen for planning, labelled **Assumption** there. That covers the Q10, the reference bulk time, the inoculation exponent, starter peak times, the ±20% window, the linear rise extrapolation, the 8–36 h cold-proof bounds, and the fridge-rescue thresholds and transfer timing. None of them has been validated against measured bakes. The app says "likely" and "about", and tells the baker to go by the dough.

## Live re-planning

1. Estimate the time until the rise target by **linear extrapolation** of rise versus time since mixing. This is an estimate, not a validated fermentation predictor. Rise usually accelerates, so it tends to overestimate the time left, and a single imprecise reading can move it either way. Readings under 45 minutes after mixing are labelled "very rough", and every summary suggests checking again.
2. Tolerance is the larger of 30 minutes and 15% of bulk.
3. If the user has a free shaping slot within tolerance of the likely-ready time, the single recommended option is `shapeNow` or `shapeWhenReady`, and reminders move to match.
4. Otherwise the options are built in a fixed order:
   - `fridgeNow`: offered once bulk is at least 35% done by the time the dough would go in, recommended at 50% or more.
   - `stayUp`: shape during the busy block. Recommended only if nothing else is.
   - `waitLonger`: shape at the next free slot, up to 3× tolerance late.

   Each option's remaining steps are re-planned against busy time. If a room-proof tail doesn't fit, a fridge proof is tried.
5. Options are not scored or sorted beyond that order and the single "recommended" flag.

**Putting the dough in the fridge is a real step.** `fridgeNow` starts with an attended 5-minute `fridgeDough` step, so it gets its own reminder and counts as hands-on time. It is scheduled 10 minutes before the busy block when that slot is free, otherwise immediately (the baker is holding the phone). The passive `coldBulk` follows. The shape step after it has cold-shaping text and no room-temperature "likely ready" window.

**Applying an option keeps the plan in order.** Completed steps and the mix are kept. Pending folds that would end after the new end of bulk are dropped. Bulk is trimmed so it ends exactly where the option's shaping (or fridge transfer) begins. An earlier fridge option that was never carried out is replaced.

**Once the dough is chilled, check-ins stop** (`BakeSession.isChilled`: the transfer has been marked done, or a bake saved before the transfer step existed has a `coldBulk`). Rise targets assume room temperature, so a reading from chilled dough would feed the room-temperature model a number it can't interpret. Check-ins return `doughIsChilled` (or `notInBulk` before mixing and after shaping), and the app hides the check-in button.

**Late or early mixing and shaping never leave an impossible cold proof.** Marking mix or shape done slides the dough steps. In a fridge-proof plan, `keepColdProofWorkable` then checks the cold proof. If the bake is now under 8 h or over 36 h after shaping, including a "negative" proof when shaping happened after the planned bake, the bake moves to the nearest 15-minute slot inside the range. It prefers a slot where preheat and bake are free, and `adjustmentNote` tells the baker why. Room-proof plans already slide the bake with shaping.

`ReplanIntegrityTests` checks chronology after every option, and after completing each remaining step 90 minutes late, across a day of check-ins. The prototype replays the same scripted bakes from `fixtures.json`.

## Calibration

- Only bakes rated "just right" at shaping count.
- Any bake whose dough went into the fridge mid-bulk is excluded. The model has no term for time in the fridge, so counting those hours as room-temperature bulk would teach Hearthday that the baker's dough is slow. The exclusion holds even if a later re-plan removes the fridge steps, because it keys off the completed transfer.
- The journal's bulk time for a chilled bake counts room-temperature time only.
- The speed factor is the log-mean of the observed/model ratio with a prior weight of 2, so one odd bake can't swing it.
- With 3 or more samples, uncertainty is `clamp(1.3 × rms + 0.05, 0.10, 0.30)`.
- **Pro** applies the factor to plans. Everyone can see what it has learned.

## Verification status (honest)

The README has the current evidence, with a link to the CI run. In summary:

| Check | Status |
|---|---|
| Core, app-model, StoreKit (`SKTestSession`) and UI tests on an iOS simulator | Passing in macOS CI (Xcode 16.4, iPhone simulator) |
| Unsigned Release build for generic iOS | Passing in macOS CI |
| `swift test` in `Core/` (Swift 6.1, Linux) | Passing locally and in CI |
| JS parity and headless-Chrome end-to-end tests for the prototype | Passing locally and in CI |
| Physical device, App Store sandbox purchase, real notification delivery, VoiceOver and Dynamic Type audit | **Not done.** These need an Apple Developer account and a device, which is owner work. |

## Time zones and daylight saving

Busy blocks are **wall-clock** rules ("Sleep, 23:00–07:00, every day"). Each occurrence's start and end are computed as local calendar times on the right day, never as start plus a fixed duration. So the night of a spring-forward change is 7 hours and a fall-back night is 9. Fermentation steps are **physical** durations between absolute instants.

`Availability.wallClock` resolves the two awkward cases deterministically, identically on Apple platforms, Linux and in the JS port:

- A time skipped by spring-forward (02:30) moves forward by the gap (03:30), matching JavaScript `Date`.
- A repeated fall-back time takes its first occurrence.

`DSTTests` covers both transitions, every night of 2026 in five zones, whole plans that cross each change, and a device time-zone change mid-bake. Those tests fail under the old fixed-duration logic.

## Recovery after closing and reopening

State is written atomically after every change. On iOS it uses `completeFileProtectionUntilFirstUserAuthentication`, so background reminder rebuilds can still read it after the first unlock.

On launch, on every activation, and when the time zone or clock changes, `AppModel.resume()` refreshes the clock and calendar (resetting the cached system time zone), rebuilds reminders from the saved bake and re-reads notification permission. `BakeSession.status(now:)` then tells the live screen what to show:

| Status | When | What the live screen shows |
|---|---|---|
| Upcoming | Before the next step is due | The next step |
| Due | From 5 minutes before the step until the 15-minute grace period ends | The step as due now |
| Overdue | After the grace period | "Was due … ago", plus a shaping caution if bulk ran long |
| Stale | More than 12 hours past the planned finish | "Did this bake finish?" with Log and Abandon |
| Baked | Once the bake is done | The finished state |

## Known limitations

- **Daylight-saving edge cases are policy, not physics.** A step that lands inside a skipped hour is shown at the shifted time. An overnight dough spanning fall-back gets an extra hour of wall-clock time but not of fermentation.
- **Linear extrapolation** of rise is an unvalidated estimate. Rise usually speeds up through bulk, so a straight line tends to overestimate the time left (the safer error overnight). A mis-marked container, an uneven dough temperature or a very early reading can push it wrong in either direction. It is meant to support a decision, not to predict a time.
- **Chilled bulk isn't modelled.** Hearthday doesn't estimate how far dough ferments in the fridge. It schedules shaping at the next free time and tells the baker to judge the dough.
- **Temperature is entered by hand.** No sensor or weather integration.
- **Single oven, single dough.** Batches and multiple doughs are roadmap items.
- **No iCloud sync or backup** beyond the standard device backup.
