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
│   │   ├── StepText.swift       user-facing step copy
│   │   └── AppState.swift       persisted state, free/Pro limits, JSONFileStore
│   ├── Sources/hearthday-fixtures/  emits prototype/fixtures.json for JS parity
│   └── Tests/HearthdayCoreTests/    44 XCTest cases
├── App/Hearthday/        SwiftUI app (iOS 17); NOT compiled in the authoring environment
│   ├── Model/            AppModel (@Observable), NotificationScheduler, ProStore (StoreKit 2)
│   ├── Views/            onboarding, home, plan, live bake, check-in, journal, settings, Pro
│   ├── Design/           Theme (palette, type, components), Formatters
│   └── Resources/        Hearthday.storekit (local StoreKit test config)
├── project.yml           XcodeGen spec
└── prototype/            browser companion (a JS port of Core plus a mock UI), not the native app
```

**Why this split.** All of the logic that could be wrong (time arithmetic, the fermentation model, the planner search, re-planning, calibration, persistence) lives in `HearthdayCore`. That package builds and tests on Linux. The SwiftUI layer is thin: it renders state and forwards intents to `AppModel`.

## Key design choices

| Choice | Reason | Trade-off |
|---|---|---|
| No accounts, backend or analytics | Zero running cost, a simple privacy story ("Data Not Collected" is the target label) and one less thing to fail | No cross-device sync and no usage data. Validation relies on TestFlight feedback and App Store Connect's aggregate metrics. |
| JSON file in Application Support (`JSONFileStore`, atomic writes) | The state is small (a handful of formulas and bakes). It is easy to migrate and inspect. | Not suitable for large histories. SwiftData is an option later. |
| Corrupt file quarantined, not deleted | Never silently destroy a user's journal | The user sees a "started fresh" banner. |
| Exhaustive 15-minute grid search in the planner | The search space is small (mix time × proof mode × inoculation × feed ratio). It is deterministic and easy to explain. | It runs off the main thread (`Task.detached`). A 15-minute resolution is enough for bread. |
| Local notifications only (`UNCalendarNotificationTrigger`, `hearthday.` prefix) | No push server needed | If the user changes the device clock or time zone, reminders are rebuilt on the next foreground (`scenePhase` → `refreshClock`). |
| StoreKit 2 non-consumable, `Transaction.updates` listener, `AppStore.sync` restore | Current Apple API. No receipt server. | The entitlement is cached in `AppState.isPro` and reconciled at launch. |
| JS port of the core for the prototype, parity-tested against Swift fixtures | The prototype should behave like the real planner rather than a mock | It is a second implementation to keep in sync. The parity test catches drift (confirmed by mutating a constant: 6 of 15 checks failed). |

## Fermentation model (a planning heuristic, not a guarantee)

- Bulk: `hours = 7 / (2.6^((T−21)/10) × (inoc/20)^0.5 × speed)`. Room proof is 2 h at the reference temperature and scales the same way.
- Starter peak at 24 °C: 4.5, 6.5, 9 and 12 h for feed ratios of 1:1:1, 1:2:2, 1:5:5 and 1:10:10.
- The target rise depends on temperature (100% at 18 °C down to 30% at 27 °C, interpolated). **These targets assume a cold retard afterwards.** For same-day room proofs they may be too high.
- Default uncertainty is ±20%. Calibration narrows it to between ±10% and ±30%.
- **The constants disagree with at least one public model.** Sourjoe publishes 3.75 h at 20 °C with Q10 = 2. The two models reflect different assumptions about flour, inoculation and the end point. Neither is authoritative. Calibration exists because no fixed model fits every kitchen.

## Live re-planning

1. Estimate the time until the rise target by **linear extrapolation** of rise versus time since mixing.
2. Tolerance is the larger of 30 minutes and 15% of bulk.
3. If the user has a free shaping slot within tolerance of the likely-ready time, the single recommended option is `shapeNow` or `shapeWhenReady`, and reminders move to match.
4. Otherwise the options are built in a fixed order: `fridgeNow` (offered once bulk is at least 35% done by the time it would go in the fridge, recommended at 50% or more), then `stayUp` (shape during the busy block; recommended only if nothing else is), then `waitLonger` (shape at the next free slot, up to 3× tolerance late). Each option's remaining steps are re-planned against busy time. If a room-proof tail doesn't fit, a fridge proof is tried.
5. Options are not scored or sorted beyond that order and the single "recommended" flag.

## Calibration

- Only bakes rated "just right" at shaping count. Bakes whose bulk was paused in the fridge (`coldBulk`) are excluded, because chilling makes fast dough look slow.
- The speed factor is the log-mean of the observed/model ratio with a prior weight of 2, so one odd bake can't swing it.
- With 3 or more samples, uncertainty is `clamp(1.3 × rms + 0.05, 0.10, 0.30)`.
- **Pro** applies the factor to plans. Everyone can see what it has learned.

## Verification status (honest)

| Check | Status |
|---|---|
| `swift test` in `Core/` (Swift 6.1.2, Linux) | 44 tests pass |
| JS parity (`node prototype/parity.test.js`) | 15 checks pass against fixtures regenerated from Swift |
| Prototype end-to-end in headless Chrome (puppeteer-core, not committed) | Passes: onboarding → plan → start → check-in → option → finish → journal |
| SwiftUI app compiled or type-checked | **No.** Xcode isn't available on Linux. Only `swiftc -parse` (syntax only) was run on the app sources. Expect some compile fixes on first open in Xcode. |
| App run on simulator or device, StoreKit sandbox, notifications, VoiceOver | **Not done** |

## Known limitations

- **Daylight-saving transitions:** busy blocks are wall-clock and weekly. The planner uses `Calendar` arithmetic, but nothing tests a bake that crosses a DST change.
- **Linear extrapolation** of rise underestimates late-bulk acceleration and overestimates early lag. It is good enough for decisions, not for precision.
- **Temperature is entered by hand.** No sensor or weather integration.
- **Single oven, single dough.** Batches and multiple doughs are roadmap items.
- **No iCloud sync or backup** beyond the standard device backup.
