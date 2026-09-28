# Hearthday — design decisions

Status: draft for owner review · 2026-09-28

The native app has **not** been run on a device or simulator (there was no Xcode in the authoring environment). The screenshots in the PR come from the **browser companion prototype**, which mirrors the flows and copy but is not the native app. Visual details on iOS will differ.

## Principles

1. **Answer "what do I do now?" first.** Every screen during a bake leads with the next hands-on step and its time. Explanations come second.
2. **Be honest about uncertainty.** Times are shown as a likely window ("ready 21:10–22:40"), never as a promise. There is no language about guaranteed results, and no health or nutrition claims.
3. **Make the week visible.** Busy time is always drawn on the same ribbon as the plan, so the reason a plan looks the way it does is visible without reading.
4. **Never dead-end.** Every empty, infeasible or error state gives one concrete next action.
5. **Low typing.** Onboarding is three screens of steppers, pickers and presets. There are no accounts and no free-text fields are required.

## Identity

- **Name:** Hearthday, "the day around your hearth". An earlier working name (Proofline) was dropped because of a likely trademark conflict. Hearthday has **not** been trademark-cleared; that search is a pre-launch task.
- **Palette** (`Design/Theme.swift`): flour and crumb backgrounds, crust and ember accents for actions, and **indigo "night"** for sleep. Work is sage and other commitments are plum. Every colour has a dark-mode variant.
- **Type:** a serif display face (SF Serif) for headings gives a baker's-notebook feel. Times use SF Rounded with monospaced digits so countdowns don't jitter.
- **Mark:** `LoafMark`, a scored-loaf logo drawn in `Canvas`, so no image assets are needed.
- **Signature visuals:** the **week ribbon** (the plan drawn over hatched busy blocks) and the **rise jar** on the check-in screen (a jar that fills as you move the rise slider, with the target line marked).

## Key flows and why they look like this

| Flow | Decision | Reason |
|---|---|---|
| Onboarding | 3 pages: welcome → busy times (sleep and work presets, editable) → kitchen temperature and starter | Busy times are the planner's main input. Presets give a working plan in under 2 minutes. |
| Home | Suggested finish times (10:00, 12:00, 19:00 over the next 4 days) that are filtered to have a free oven slot, plus "Custom time" | During testing a weekday "Tomorrow 10 AM" suggestion fell inside work hours and failed. Suggestions now only offer times that can work. |
| Plan result | Summary, flow chips (feed → mix → bulk → shape → proof → bake), step list, estimate note and up to 2 alternatives | Alternatives show the trade-off (for example an overnight fridge proof versus a same-day proof) instead of hiding it. |
| Infeasible | Names the busy block that blocks the plan and offers **"Earliest that fits"** as a one-tap fix | Sourjoe does the same. It is the correct pattern, not a differentiator. |
| Live bake | Next-step card, a passive card during waits and a conflict banner when a step drifts into busy time | Most of a bake is waiting. The screen should be glanceable. |
| Check-in | Rise slider and jar → a short list of options, each with a finish time and a one-line trade-off. One is marked recommended. | This is the hypothesised differentiator: a decision, not a timer. |
| Shape readiness | At shaping, ask "under / just right / over?" | This is the only calibration signal. It takes one tap and has no scale or sensor. |
| Journal | Calibration card ("your dough runs ~12% faster than the model"), bake rows and a "Plan held" chip | It shows learning, which builds trust in the estimates. |

## Empty and error states

- **No bakes yet:** the journal explains what will appear there and links to planning.
- **Infeasible plan:** the reason, the blocking busy block, and the earliest feasible time.
- **Check-in with no viable options:** earlier builds could show an empty list. The screen now explains the situation and offers "log check-in only".
- **Corrupt saved data:** the file is moved aside (quarantined, not deleted) and a banner explains that the app started fresh. If it can't be moved aside, the app keeps working without saving so the original is never overwritten. The banner can't be dismissed while that's the case.
- **Save failure:** a persistent banner.
- **StoreKit unavailable:** the reason plus "Try again". The paywall never shows a price it couldn't load.
- **Purchase pending, cancelled or failed:** each has its own message. Success is only shown once a verified entitlement is active. An error or unverified result can't prove whether the App Store charged anyone, so the copy never says either way. It says Pro isn't active yet and points to Restore purchase, then to Apple Account purchase history, Report a Problem and Apple Support. Erasing app data keeps a verified purchase: StoreKit is re-checked straight after the reset.
- **Notifications denied:** the live bake shows "Reminders are off" with a button that opens Hearthday's notification settings. The plan keeps working in the app. Permission is re-read on every reminder sync, so turning it off in Settings shows up without a relaunch.
- **Reminders rejected by iOS:** "N of M reminders couldn't be scheduled" on the live bake until a later sync succeeds.
- **Invalid input:** out-of-range temperatures, ready times in the past or more than 7 days ahead, and broken formulas get "Something needs fixing first" with a plain reason, never an extrapolated plan. Implausible check-in readings get "Check that reading". Busy-time and formula editors disable Save until the entry is valid.
- **Dough in the fridge mid-bulk:** "Put the dough in the fridge" is a hands-on step with its own reminder. Once it's marked done, the check-in button disappears, because rise targets don't apply to chilled dough. The shape step then says to shape straight from the fridge and judge by look, with no "likely ready" window.
- **Bake moved by a late or early step:** when a late mix or shape would leave the cold proof under 8 h (or an early one would stretch it past 36 h), the bake moves. A card explains why, for example "Shaping ran late, so the bake moved later to give the cold proof at least 8 h." The reminders move with it. The card clears at the next re-plan.
- **Reopened after time away:** a missed step shows "Was due … ago" in the warning colour, with a shaping caution if bulk ran long. A bake more than 12 hours past its planned finish asks "Did this bake finish?" and offers Log or Abandon.
- **Saved by a newer version:** the file is kept, not overwritten, with a message to update the app.

## Accessibility

- Dynamic Type is supported throughout because only text styles are used, never fixed point sizes.
- Busy time is **hatched** as well as coloured, so it doesn't rely on colour alone.
- The ribbon, rise slider and temperature stepper expose spoken values ("3 hands-on steps", "60 percent", "24 °C").
- Decorative images are hidden from VoiceOver. Empty states read as a single combined element.
- Minimum hit targets are 44 pt. Primary buttons are 52 pt tall.
- Light and dark palettes are dynamic colours. UI tests walk the whole loop in both appearances and save screenshots.
- **Not yet verified:** VoiceOver reading order, Reduce Motion, the largest accessibility text sizes and measured contrast on a real device. These need a manual Accessibility Inspector and VoiceOver pass on a Mac or device.

## Paywall

- One non-consumable "Pro" purchase. The screen lists exactly what Pro adds and what **stays free**, and it has Restore. There is no countdown, no fake discount, no auto-renewing trial and no pre-selected upsell.
- **Free:** planning around busy times, live check-ins and re-planning, reminders, and *seeing* what calibration has learned.
- **Pro:** calibration *applied* to plans, unlimited formulas (free has 2), and the full journal (free shows the last 5; older bakes are kept, never deleted).
- **Risk:** putting the differentiator (check-ins) in the free tier may cap conversion. That is deliberate: the differentiator has to be experienced to be valued. Experiment E5 tests it.
