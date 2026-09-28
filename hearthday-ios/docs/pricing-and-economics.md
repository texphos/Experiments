# Hearthday — pricing and unit economics

Status: draft for owner review · 2026-09-28 · Reproduce the numbers with `python3 docs/economics.py`

Every number below is either a **Fact** (with a source in [research-sources.md](research-sources.md)) or an **Assumption** (untested, with the experiment that tests it). None of it is a revenue forecast.

## Recommendation

- **Model:** free app plus one non-consumable **Hearthday Pro** unlock. No subscription, no ads.
- **Proposed price: US$9.99** (the StoreKit test config and prototype now show $9.99). This replaces an earlier $14.99 proposal.
- **Why not $0.99:** at 15% commission a $0.99 sale nets about $0.77 (**Fact** for the commission rate, **Assumption** for tax drag). Even the high scenario would then net about $260 a month. The price would also signal low quality in a category where comparable unlocks cost $4.99–$19.99.
- **Why not a subscription:** baking is episodic (2–6 bakes a month, with seasonal gaps), and the app has no running costs to pass on. Rise and BreadPilot do sell subscriptions, so users will pay them, but the closest competitors on this job (Sourdough Companion, Yeast on East) sell a one-time unlock. A subscription would put Hearthday at a disadvantage on the comparison users are most likely to make.
- **Why $9.99 and not $14.99:** checkpoint 2 established that the core planning job is already available cheaply (Sourdough Companion one-time at about $3.99 on Android, Sourjoe free on the web, Yeast on East one-time). Hearthday's advantage is a hypothesis, so it can't yet support a premium. $9.99 sits above BreadPilot's $8.99 lifetime and below Rise's $19.99 lifetime. E5 tests it against $6.99 and $14.99.

## What is free and what is Pro

| Free (the whole core job) | Pro |
|---|---|
| Plans around busy times, infeasible explanations, earliest feasible time | Personal calibration **applied** to plans (with a narrower likely-ready window) |
| Live check-ins and re-plan options | Unlimited formulas (free: 2) |
| Reminders | Full journal (free shows the last 5; older bakes are kept) |
| Seeing what calibration has learned | |

Pro sells *accuracy that improves with use*. It only works if calibration measurably improves estimates (E6). If it doesn't, the Pro offer has to change before launch.

## Unit economics (output of `economics.py`)

Inputs: price $9.99; Small Business Program commission 15% (**Fact**); 8% average sales-tax/VAT drag on proceeds (**Assumption**); Apple Developer Program $99/year (**Assumption**, taken from a third-party fee guide; confirm on Apple's enrolment page); zero infrastructure cost (**Fact** for this architecture: no backend).

- Net per sale ≈ **$7.81**
- Fixed cost ≈ **$8.25/month**, so break-even is about 1.1 sales a month

| Scenario | Downloads/month | Download → Pro | Sales/month | Net/month | Net/year |
|---|---:|---:|---:|---:|---:|
| Low | 300 | 2% | 6 | $39 | $463 |
| Base | 1,500 | 4% | 60 | $460 | $5,526 |
| High | 5,000 | 7% | 350 | $2,726 | $32,712 |

Downloads and conversion rates are **Assumptions**. Conversion is bracketed by RevenueCat's freemium and hard-paywall medians, which describe subscription apps, so it is a weak anchor. Downloads are not anchored at all; E3 and E4 are the first real signal.

**Price sensitivity** (Base downloads and conversion held fixed, which is unrealistic because conversion would move with price): $4.99 → $226/month, $6.99 → $320, $9.99 → $460, $14.99 → $695, $19.99 → $930.

## Acquisition economics

The largest cost per install a paid campaign could afford and still break even on the first purchase is **$0.16 (Low), $0.31 (Base) or $0.55 (High)**. App-install ads usually cost well above that (**Assumption**; no sourced benchmark is cited here). **Conclusion: no paid acquisition.** Growth must come from App Store search, the community, creators and word of mouth ([launch-plan.md](launch-plan.md)).

## Pricing experiments (drafts, need owner approval)

| Test | Design | Decision rule |
|---|---|---|
| P1: fake-door price test on TestFlight | Show one of $6.99, $9.99 or $14.99 on the Pro screen (StoreKit sandbox; no real charge) and ask "Would you pay this today?" | Keep $9.99 unless $14.99 gets at least 80% of $9.99's yes rate, in which case pick $14.99. Drop to $6.99 if $9.99 gets under 50% of $6.99's rate. |
| P2: post-launch conversion | Measure download → Pro from App Store Connect after 1,000 downloads | Below 1.5% at $9.99: revisit the Pro offer (E5 kill criterion) |
| P3: launch introductory price | Optional $6.99 for the first 2 weeks, clearly labelled | Only if the reviews and velocity would help search ranking. Never use fake "was" prices. |

## Risks

- **Race to the bottom:** Sourdough Companion's roughly $3.99 one-time price and Sourjoe's free tool anchor low.
- **The free tier may be too generous.** If check-ins are the differentiator and they're free, Pro rests on calibration alone. This is deliberate for validation and may change.
- **Tax and currency:** Apple's tier prices differ outside the US. The model uses US prices only.
