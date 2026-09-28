# Hearthday — product strategy

Status: draft for owner review · Research date: 2026-09-28 · Sources: [research-sources.md](research-sources.md)

## TL;DR

- **Chosen wedge:** home sourdough bakers with a weekday job who bake 2–6 times a month. The moment of pain is **mid-bulk, on a work night**: the dough is running faster or slower than the recipe said, and the next hands-on step is about to land in sleep or a meeting.
- **What Hearthday does about it:** it plans backward around recurring busy times, and it turns a 10-second rise check into a few constraint-aware options, one marked recommended (fridge now, shape when you're free, stay up, wait) with an honest finish time for each. Its time estimates learn from bakes the user rates "just right" at shaping.
- **What is *not* new:** planning a bake backward around sleep and work. At least five products already advertise it (Sourdough Companion, Sourjoe, Doughflow, Yeast on East, plus Knead and Sourdough Schedule for backward/visual planning). An earlier draft of this document said "no app plans around busy windows". **That claim was wrong and is retracted.**
- **Defensible, testable advantage (hypothesis, not fact):** decision support *during* bulk, on iPhone, that keeps the plan inside the baker's week. Competitors, going by their public listings, re-plan on *time* events (missed alert, "Delay 30 min", finish-early) or on temperature logs. Hearthday re-plans from an *observation of the dough* and presents trade-offs. This is unproven and could be copied quickly; see "What would disprove the thesis".
- **Business-scale candour:** this is a crowded, low-price indie category. The realistic outcome is **side-business revenue: hundreds to low thousands of US dollars a month** (see [pricing-and-economics.md](pricing-and-economics.md)). It is not a significant business on its own. Paid acquisition cannot work at these prices. A larger outcome depends on an expansion that has not been validated (micro-bakery batch planning, pizza and other doughs), and Doughflow already targets farmers-market batch baking.
- **Recommendation:** use the MVP as a cheap validation vehicle. Commit further effort only if the interview and TestFlight experiments pass ([validation-experiments.md](validation-experiments.md)).

## 1. Three sharply different opportunities

Ranked on the owner's criteria (demonstrable willingness to pay, organic distribution, time-to-value, repeat use, expansion), **not** on TAM.

| | A. Sourdough around a work week | B. Espresso dial-in coach | C. Home maintenance planner | D. Document renewals |
|---|---|---|---|---|
| Who | Weekday-employed home bakers | Home espresso owners | Homeowners | Families with passports/IDs |
| Recurring pain | Every bake spans 1–2 days and collides with sleep/work | Every new bag of beans needs 3–8 shots to dial in | Filters, gutters, service intervals | Passport/visa/licence expiry |
| Willingness to pay (evidence) | Rise: $14.99–19.99/yr or $19.99 one-time, 323 US ratings. Many $4.99–$8.99 unlocks. Sourdough Companion one-time. **Medium-low** | Filtru: $32.99/yr or $79.99 lifetime, claims 11,914 ratings. **Medium** | HomeZada: $99/yr. Centriq shut down (sources disagree: Jan 2025 or Jan 2026). **Low for consumers** | DocFort $59.99/yr, EverPass $3.99 lifetime. **Low** |
| Organic distribution | r/Sourdough ~710–750k members, +19.5%/yr (third-party trackers). Self-promotion banned. **Medium** | r/espresso ~1M (earlier session, not re-verified). **Medium** | Poor: little word of mouth for chores | Poor |
| Time-to-value | First plan in under 2 minutes | First useful nudge after 1 shot | Hours of data entry before any value | Minutes (OCR), then value arrives yearly |
| Repeat use | 2–6 bakes/month | Daily, spikes with each new bag | Monthly or seasonal | 1–2 times a year |
| Expansion | Pizza/other doughs; micro-bakery batches (unvalidated) | Grinders/scales hardware tie-ins | Pro/realtor channel (HomeZada PRO) | Family plans |
| Main risk | Crowded; feature parity is easy | Crowded (Filtru, Beanconqueror free, Dialin, Lumo, GrindDial…); Bluetooth scale integrations are table stakes | Data-entry burden; Centriq's closure shows weak consumer economics | Low frequency; sensitive data raises the trust bar for an unknown brand |
| Verdict | **Selected, with caveats** | Runner-up | Rejected | Rejected |

### Why home maintenance is rejected
- **Manual data entry:** value appears only after the user inventories appliances, model numbers and intervals. Photo-to-manual lookup reduces the effort but needs a product database (a backend, ongoing cost).
- **Acquisition cost:** there is no hobby community that shares chore apps. HomeZada leans on realtors and partners (co-branded PRO). That is a B2B2C channel a solo app can't reach cheaply.
- **Evidence of weak economics:** Centriq, a long-running free app, shut down and deleted accounts. Third-party sources disagree on whether that was January 2025 or January 2026, but every one of them reports the shutdown.

### Why document renewals are rejected
- **Frequency:** a passport renews about every 10 years, so the core loop fires rarely. That hurts retention and word of mouth.
- **Sensitive data:** users are rightly wary of scanning IDs into an unknown app. Competitors already offer on-device OCR with "Data Not Collected" labels (DocFort) at $3.99 lifetime (EverPass). There is no room on price or trust.

### Why espresso is the runner-up, not the pick
It has stronger willingness to pay (Filtru's $79.99 lifetime) and daily use, but the field is dense: Filtru has 10 years of polish and Bluetooth scale support for 14 brands, and Beanconqueror is free. A newcomer would need hardware integrations to be credible, which violates "low ongoing cost, fast MVP".

## 2. Challenging the favourite (sourdough)

**Retracted claim.** "No app plans around blocked-out busy windows." Independent review, then verification on 2026-09-28, found:

- **Sourdough Companion** (Android, Mark Bennett; one-time purchase): "Tell it when you want fresh bread, and when you are asleep or at work. It plans backward and shifts the two levers that actually move a sourdough timetable — feed ratio and cold retard — until every hands-on step lands while you are awake." That is Hearthday's planner, nearly word for word. It also "learns from your own baking" once you have logged eight bakes.
- **Sourjoe Schedule Builder** (free web): reads daily quiet hours, shows every workable start range, "names what's blocking and the nearest time that would work". This is the same design as Hearthday's infeasible state. It also publishes a tunable, calibrated rise-time model.
- **Doughflow** (web; free, or $5/month or $50/year): "Block off sleep, commutes, and meetings."
- **Yeast on East** (iOS; on-device, no account, one-time unlock; Product Hunt launch 2026-08-28): quiet hours, temperature-adjusted bulk, and "Miss one and the app re-plans the rest". Its business model and privacy stance are very close to Hearthday's.
- **Knead** (iOS) shows which hours need your hands. **Sourdough Schedule** (iOS) and **Bakebench** (web) plan backward from the finish time.
- **Sourdough Tracker** (web, Germany) focuses on the starter journal, with a sensor kit in development.

**What remains plausibly differentiated** (from public listings only; I have not used these apps):
1. **Re-planning from an observation of the dough.** Competitors re-plan on time events (missed alert, delay button, finish early) or temperature. Hearthday takes a *rise reading*, estimates when the dough will be ready, and offers options that respect busy times, one marked recommended, each with its finish time and trade-off (for example "Fridge the dough before Sleep, shape at 7:00, bread 7:00 PM"). Sourdough Companion has a temperature-aware aliquot rise target, so the *ingredients* exist elsewhere. The *decision screen* may not.
2. **Weekday-specific busy blocks on iPhone.** Sourjoe's quiet hours apply every day. Sourdough Companion's scheduler is Android-only. On iOS I found no listing that describes both sleep/work-aware backward planning *and* mid-bulk re-planning. This rests on a non-exhaustive search and is **not a claim of novelty**.
3. **Calibration that changes the timing model**, using only bakes the baker rated "just right" at shaping, and excluding fridge-paused bulks.

**Why that may still not be enough.** Each of these is a feature a competitor could add in weeks. The durable assets would have to be execution quality, trust and word of mouth, and those take time and luck.

## 3. Narrow audience, moment of pain, core workflow

- **Audience:** someone who keeps a starter in the fridge, works 8:30–17:30 on weekdays, and wants bread for a specific meal (Saturday breakfast, Sunday lunch, a Wednesday dinner).
- **Moment of pain:** Friday at 21:30. The recipe said about 7 hours of bulk. It's been 4 hours, the dough is already up 60%, and they want to sleep at 23:00. Free tools (recipe timings, static calculators, a notes app) tell you how long fermentation *should* take, not what to do *now* given your night.
- **Core loop (the MVP):**
  1. Plan: pick a finish time and get a feasible plan, or an honest "that doesn't fit" plus the earliest time that does.
  2. Bake with reminders.
  3. Check in mid-bulk and choose an option.
  4. Rate the shaping moment. Calibration improves the next plan.

## 4. What would disprove the thesis

Details and thresholds are in [validation-experiments.md](validation-experiments.md). Any one of these should stop or redirect investment:
- In interviews, fewer than half of target bakers report a schedule collision in their last 3 bakes, or most say existing tools or a fridge rule of thumb already solve it.
- In TestFlight, the check-in is used in fewer than 10% of bakes (the differentiator doesn't matter), or fewer than 20% of users start a second bake within 14 days.
- In a head-to-head usability test, testers can't name a meaningful difference between Hearthday and Yeast on East or Sourdough Companion.
- Download-to-Pro conversion stays under 1.5% at $9.99 after 1,000 downloads.
- Calibration does not reduce shaping-time error for most users, in which case "learns your kitchen" is marketing, not product.

## 5. Scale limits, stated plainly

- **Price ceiling:** comparable one-time unlocks run $3.99–$19.99. Subscriptions exist (Rise, Crumb), but the core problem is episodic. Hearthday uses a one-time purchase to match that value pattern and the competitors' anchors.
- **No paid acquisition:** at $9.99 and 2–7% conversion, break-even cost per install is $0.16–$0.55 (see the economics script). Growth has to be organic: App Store search, community helpfulness within subreddit rules, and baker creators.
- **Expected range:** $40–$2,700 net a month across the low to high scenarios. Even the high case is a strong side income, not a company.
- **Paths to a bigger outcome (unvalidated):** micro-bakery production scheduling (several doughs, one oven, a day job), and extension to pizza and enriched doughs. Each needs its own evidence before any build.
