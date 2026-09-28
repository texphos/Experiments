# Hearthday — validation experiments

Status: draft for owner review · 2026-09-28

**Nothing here has been run.** Every experiment that involves contacting people, recruiting testers or posting publicly requires the owner's approval first, and none has been contacted. Draft materials are in [drafts/](drafts/).

Run the experiments in order. Each has a pass bar and a **kill criterion**. Hitting a kill criterion means stopping or redirecting, not tweaking and re-running until it passes.

| # | Question | Method | Sample | Pass | Kill |
|---|---|---|---|---|---|
| E1 | Is the mid-bulk schedule collision real and frequent for the target baker? | Structured interviews ([interview-guide](drafts/interview-guide.md)) with weekday-employed bakers who bake 2 or more times a month. Ask about the last 3 bakes, not hypotheticals. | 12–15 | 60% or more describe a collision in their last 3 bakes, **and** at least half of those describe a bad outcome or a sacrifice (a late night, over-proofed dough, a skipped bake) | Under 40% report a collision, **or** most say a fridge rule of thumb or an existing app already solves it |
| E2 | Do bakers see a difference from the incumbents? | Head-to-head usability test: the same scenario ("Friday 21:30, dough is fast, sleep at 23:00") in Hearthday (TestFlight, or the prototype if TestFlight isn't ready) versus Yeast on East (iOS) or Sourdough Companion (Android) | 6–8 from E1 | 5 of 8 or more prefer Hearthday for the scenario **and** can name the check-in options as the reason | Most can't name a meaningful difference, or prefer the incumbent |
| E3 | Does the loop get used? | TestFlight beta ([recruitment post](drafts/beta-recruitment-post.md)) for 4 weeks. Measured by in-app **on-device** counters that the tester exports voluntarily from Settings (still to be built; no analytics SDK) plus a weekly survey. | 30–50 active testers | A check-in used in 30% or more of bakes; 40% or more start a 2nd bake within 14 days | Check-in in under 10% of bakes, **or** under 20% start a 2nd bake within 14 days |
| E4 | Is App Store search demand enough for organic growth? | Draft the listing ([app-store-listing](drafts/app-store-listing.md)). After launch, read App Store Connect impressions and conversion for "sourdough schedule", "bread timer" and similar terms. | First 60 days | 300 or more downloads a month by day 60 without paid ads | Under 100 a month by day 60 despite executing the launch plan |
| E5 | Will people pay $9.99 for what Pro offers? | P1 fake-door test in TestFlight, then live conversion | 1,000 downloads | 3% or more download → Pro | Under 1.5% at $9.99 after 1,000 downloads (and under 1.5% at $6.99 if re-tested) |
| E6 | Does calibration improve estimates? | For testers with 4 or more "just right" bakes, compare the error in the predicted shaping time with and without calibration. Computed on-device from the journal they export. | 15 or more testers | The median absolute error falls by 20% or more | No improvement for most testers. Then "learns your kitchen" is marketing, so drop it from Pro and the listing. |

## What would change the plan

- **E1 fails:** stop sourdough. Re-examine the espresso runner-up with the same interview-first approach.
- **E1 passes and E2 fails:** the pain is real but already served. Don't launch a me-too. Either find a sharper wedge (for example micro-bakery batches, validated separately) or stop.
- **E3 fails on check-ins but passes on repeat use:** the value is the planner, which is commoditised. Launch only as a cheap, polished utility with low expectations, or stop.
- **E5 fails:** try a different Pro offer (for example multi-dough/batch planning) before changing the price again.
- **E6 fails:** remove the calibration claims and rethink what Pro offers.

## Ethics and consent

- Interviews and testing are voluntary and unpaid unless the owner approves an incentive budget (none is assumed). Testers may withdraw at any time.
- No data is collected by default. Any export is user-initiated, can be reviewed before sending, and contains no personal identifiers beyond what the tester chooses to share.
- Subreddit rules: r/Sourdough bans self-promotion. Recruitment there needs moderator permission (a draft request is included in the recruitment post).
