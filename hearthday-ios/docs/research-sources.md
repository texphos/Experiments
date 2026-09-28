# Research sources and evidence log

All sources accessed **2026-09-28** unless noted. App Store prices are US storefront list prices on that date and change often. Items are labelled **Fact** (read directly on the cited page), **Third-party** (a secondary source; treat with care) or **Assumption** (mine, untested).

## Sourdough scheduling competitors

| Product | Platform | What the listing says (relevant parts) | Price seen | Source |
|---|---|---|---|---|
| Sourdough Companion (Mark Bennett) | Android | Plans backward around sleep/work using feed ratio and cold retard. Insights after 8 logged bakes. Offline, no account. Updated 2026-09-07 | One-time purchase (price not shown in our fetch; the owner's reviewer saw $3.99) | **Fact** — [Google Play](https://play.google.com/store/apps/details?id=com.sourdough.companion) |
| Sourjoe Schedule Builder | Web (free) | Reads daily quiet hours, shows every workable start range, names the blocker and the nearest time that works. Published, tunable rise model (ref 20 °C, 3.75 h bulk, Q10 2) | Free | **Fact** — [sourjoe.com/calculators/schedule](https://sourjoe.com/calculators/schedule/) |
| Doughflow | Web | "Block off sleep, commutes, and meetings." Backward planning, AI recipe import, multi-recipe planning | Free, or $5/month or $50/year | **Fact** — [doughflow.app](https://doughflow.app/) |
| Yeast on East | iOS | Start-time planning, temperature-adjusted bulk (15–35 °C), quiet hours, re-plans after a missed alert. No account or server | Free with 3 recipes; one-time unlock (price not listed) | **Fact** — [yeastoneast.com](https://yeastoneast.com/). Launch date: **Third-party** — [Founder DB](https://founderdb.co/product/yeast-on-east) (Product Hunt, 2026-08-28) |
| Knead (Davide Benini) | iOS | Forward planning; shows the hours that need your hands; recipe timing extraction | Not seen | **Fact** — [kneadbread.app](https://kneadbread.app/) |
| Bakebench | Web | Backward planning from bake time; .ics export | Not seen | **Fact** — [bakebench.app/schedule](http://bakebench.app/schedule) |
| Rise (Made by Windmill) | iOS | Schedule overview, notifications, "Magic Rise Time" from temperature and ingredients, finish early or add time | Free; $3.99–4.99/month, $14.99–19.99/year, $19.99 one-time; 323 US ratings | **Fact** — [App Store](https://apps.apple.com/us/app/rise-baking-bread-recipes/id1515369685) |
| BreadPilot: Bake AI (listed as "Sourdough Companion") | iOS | Timeline engine with "Delay 30 min", AI dough photo check (Pro). A different developer from the Android app | $1.99/month, $5.99/year, $8.99 lifetime | **Fact** — [App Store](https://apps.apple.com/us/app/sourdough-companion-bake-ai/id6785401801) |
| Crumb: Sourdough Companion | iOS | Timeline, ±15 min timer adjustments, starter tracking, logbook | Free with in-app purchases | **Fact** — [App Store](https://apps.apple.com/us/app/crumb-sourdough-companion/id6758160969) |
| Kneadly | iOS | Timers for flour, hydration and temperature; starter; log | $4.99 | **Fact** — [App Store](https://apps.apple.com/us/app/kneadly-sourdough-companion/id6760272748) |
| Sourdough Tracker | Web (Germany) | Starter journal; sensor kit in development | Not seen | **Fact** — [sourdoughtracker.com](https://sourdoughtracker.com/) |

**Search limits:** searches were web-based and non-exhaustive. The App Store has no public full-text search API, so absence from these results is **not** evidence of absence. I have not installed or used any competitor. All feature comparisons come from marketing copy.

## Fermentation model inputs

| Input | Value used | Source / status |
|---|---|---|
| Target rise by dough temperature | 18 °C→100%, 20→85, 21→75, 22→65, 24→50, 27→30 (interpolated) | 21 °C→75% and 27 °C→30% anchors are **Fact** — [The Sourdough Journey, "The Mystery of Percentage Rise in Bulk Fermentation"](https://thesourdoughjourney.com/the-mystery-of-percentage-rise-in-bulk-fermentation/) and [Dough Temping guide](https://thesourdoughjourney.com/dough-temping-for-perfect-sourdough-fermentation/). Intermediate points are read from the chart and interpolated (**Assumption**). The source assumes a cold retard afterwards; the same targets for same-day room proof are an **Assumption** |
| Bulk time reference | 7 h at 21 °C, 20% starter | **Assumption**, between published tables that disagree by up to ~2× (Sourjoe uses 3.75 h at 20 °C) |
| Temperature sensitivity | Q10 = 2.6 | **Assumption** (Sourjoe uses 2.0) |
| Inoculation effect | rate ∝ (inoc/20%)^0.5 | **Assumption**; Sourjoe uses the same exponent |
| Starter peak by feed ratio at 24 °C | 1:1:1 4.5 h, 1:2:2 6.5 h, 1:5:5 9 h, 1:10:10 12 h | **Assumption** (community rule of thumb; stated as such in the app) |
| Uncertainty window | ±20% by default; calibrated range 10–30% | **Assumption**; this is why the live check-in exists |

## Economics and platform

| Fact | Source |
|---|---|
| App Store Small Business Program: 15% commission for developers under US$1M in proceeds | **Fact** — [developer.apple.com/app-store/small-business-program](https://developer.apple.com/app-store/small-business-program/) |
| Median download-to-paid by day 35: hard paywall 10.7%, freemium 2.1%. iOS median 2.6% vs Android 0.9%. Freemium has a longer tail | **Third-party (industry dataset)** — [RevenueCat, State of Subscription Apps 2026 summary](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026) and [Android paywall gap](https://www.revenuecat.com/blog/engineering/android-paywall-gap). Subscription apps only; a one-time unlock may behave differently |
| r/Sourdough: ~709,540 (RedPulse, 2026-09-16) to ~750k members (GummySearch, +19.5%/yr, 2026-08-01). Strict no-self-promotion rules | **Third-party** — [RedPulse](https://redpulse.io/subreddit-search/r/sourdough/), [GummySearch](https://gummysearch.com/r/Sourdough/), [Reddifier](https://reddifier.com/free-subreddit-analysis-tool/r/Sourdough) |

## Rejected and runner-up categories

| Fact | Source |
|---|---|
| Filtru Pro: $3.49/month, $32.99/year, $79.99 lifetime (US) | **Fact** — [App Store](https://apps.apple.com/us/app/best-brew-guide-filtru-coffee/id1150921819) |
| Filtru claims 4.8★ from 11,914 ratings, established 2016; Bluetooth scale support for 14 brands | **Third-party (vendor's own comparison page)** — [getfiltru.com](https://getfiltru.com/alternative-to-bloom/) |
| HomeZada Premium $99/year or $15.95/month; Deluxe $189/year | **Fact** — [homezada.com pricing](https://www.homezada.com/buyers-sellers/pricing) |
| Centriq shut down on January 31 (sources disagree: 2025 or 2026) and deleted accounts | **Third-party, conflicting** — [myhomeplatform.com](https://myhomeplatform.com/blog/best-home-management-apps) (2026), [toolbox.repair](https://toolbox.repair/centriq-alternative) (2025) |
| DocFort $6.99/month, $59.99/year, $99.99/year family | **Fact** — [App Store](https://apps.apple.com/us/app/docfort/id6759193013) |
| EverPass: Expiry Reminder, $3.99 lifetime | **Fact** — [App Store](https://apps.apple.com/us/app/everpass-expiry-reminder/id6759546153) |

## Key assumptions (untested; see validation-experiments.md)

- Weekday-employed bakers hit schedule collisions often enough to want a tool: **E1**.
- Bakers will take a rise reading mid-bulk: **E3**.
- A one-time $9.99 unlock converts at 2–7% of downloads: **E5**. This is between RevenueCat's freemium median and its hard-paywall median, and that data covers subscriptions, not one-time purchases.
- 300–5,000 organic downloads a month are achievable without paid ads: **E6**. There is no evidence for this yet.
- "Hearthday" as a name: not trademark-cleared. An earlier candidate, "Proofline", was dropped because of an existing bakery-equipment mark.
