# Hearthday — implementation roadmap

Status: draft for owner review · 2026-09-28

Milestones are ordered by dependency and gated by experiments. Each lists the components that change and the main risk. No calendar estimates.

## M0: Done in this branch

- `HearthdayCore`: availability with DST-correct wall-clock busy blocks, fermentation model, backward planner with infeasibility explanation and earliest feasible time, input validation, live check-in re-planning with hedged copy, calibration (excluding fridge-paused bulks), reminders, recovery status, and versioned persistence with repair and quarantine. 80 XCTest cases.
- SwiftUI app: onboarding, home, plan result (feasible, infeasible and invalid), live bake (due, overdue and stale), check-in, finish and rate, journal with calibration, settings, an honest Pro paywall with verified-only StoreKit 2, and a notifications-off banner. Built and tested in macOS CI with app-model, StoreKit (`SKTestSession`) and full-loop UI tests in light and dark.
- Committed, reproducible `Hearthday.xcodeproj`. CI fails if it drifts from `project.yml`.
- Browser companion prototype: a JS port of the core, parity-tested against Swift fixtures, as a single offline HTML file, with a committed headless-Chrome end-to-end test.
- Docs: strategy, research sources, design, architecture, pricing and economics, validation, launch, and unsent drafts.

## M1: Owner-gated device validation (before any tester sees it)

- **Needs the owner:** an Apple Developer account, a signing team and a physical iPhone.
- **Checks:**
  - Notifications delivered while locked.
  - Sandbox purchase, restore and refund with a real Apple Account.
  - A VoiceOver pass and the largest Dynamic Type size.
  - Reduce Motion.
  - A bake across a real time-zone change.
- **Risk:** device-only behaviour (notification delivery timing, sandbox account state) that the simulator doesn't reproduce.

## M2: Beta instrumentation without analytics (for E3 and E6)

- **Changes:** on-device counters (bakes started, check-ins, options chosen, second bake within 14 days) in `AppState`; Settings → "Share beta stats" produces a reviewable JSON through the share sheet; calibration error with and without calibration, computed from the journal.
- **Risk:** voluntary export means low response rates. The weekly survey is the backstop.

## M3: Only if E1–E3 pass — launch polish

- App icon and store screenshots from the native build, a `requestReview` after a successful bake, an in-app FAQ, localisation readiness (strings catalogue), and Fahrenheit and imperial polish.
- Home Screen widget for "next step at 21:40", **if** testers ask for it. It reuses `Reminders`.

## M4: Candidate expansions, each needing its own evidence

| Candidate | Why it might matter | Validate first by | Main risk |
|---|---|---|---|
| Multi-dough / micro-bakery batch planning (several doughs, one oven, a day job) | The only path seen to a higher price point | 8 interviews with cottage/market bakers. Doughflow already targets them. | A different buyer, workflow and willingness to pay |
| Pizza and enriched doughs | Broadens the audience at low cost (same planner, new constants) | Search volume and tester requests | The model constants need their own sources |
| Temperature from a Bluetooth probe | Removes manual input, improves estimates | Tester demand. Sourdough Tracker is building a sensor kit. | Hardware support burden, which contradicts the low-cost constraint |
| iCloud sync | Multiple devices | Tester requests | Adds complexity and a privacy-label change |

## Explicitly not planned

- An AI chat or photo "is my dough ready?" wrapper: running costs, unreliable, and BreadPilot already offers it.
- Accounts, a backend or social features.
- Any food-safety or health claims.
