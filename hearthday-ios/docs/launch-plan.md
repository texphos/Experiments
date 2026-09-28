# Hearthday — launch plan (draft)

Status: draft for owner review · 2026-09-28

**Nothing in this plan has been executed.** Following the owner's constraints, no money has been spent, no developer account has been bought, no domain has been registered, nothing has been published or deployed, no one has been contacted and no legal agreement has been submitted. Each step below that needs one of those is marked **[owner approval]**.

## Gates

A launch only happens if E1 and E2 pass ([validation-experiments.md](validation-experiments.md)). Public launch also needs E3 to pass.

## Phase 0: make it real on a Mac (no spend)

1. Open on a Mac with Xcode 16 or later: `brew install xcodegen && xcodegen generate`, then fix any compile errors (the SwiftUI code has only been syntax-checked).
2. Run it in the simulator with the local StoreKit config. Test purchase, restore and the unavailable state.
3. Run the Accessibility Inspector, VoiceOver, the largest Dynamic Type size, dark mode and Reduce Motion.
4. Test notifications while backgrounded and locked. Test a time-zone change and a bake that crosses daylight saving.
5. Build the known gaps: the notifications-denied banner and the opt-in counter export for E3.

## Phase 1: interviews and head-to-head (E1, E2)

- **[owner approval]** Recruit 12–15 bakers through personal networks and, with moderator permission, communities. Use the [interview guide](drafts/interview-guide.md).
- Run E2 with the prototype or a simulator build before spending on anything.

## Phase 2: TestFlight beta (E3, E5 fake door, E6)

- **[owner approval, $99/year]** Enrol in the Apple Developer Program. Choose the account type (individual or organisation) with legal/tax advice, since that affects the seller name shown on the store.
- **[owner approval]** Trademark search for "Hearthday" in US and EU classes 9 and 42. Consider alternatives if it conflicts.
- **[owner approval]** Host the [privacy policy](drafts/privacy-policy.md) on a free static page. It could use a free subdomain, so no domain purchase is needed.
- Invite 30–50 testers ([recruitment post](drafts/beta-recruitment-post.md)). Run for 4 weeks with a weekly one-question survey.

## Phase 3: App Store launch (only if E3 passes)

- **Listing:** [app-store-listing.md](drafts/app-store-listing.md). Keyword focus: sourdough schedule, bread timer, baking planner, bulk fermentation. Screenshots come from the native build, not the prototype.
- **Privacy label:** "Data Not Collected". Check this against the final build, including any SDKs; the plan is none.
- **Price:** $9.99 unless P1 says otherwise. The optional introductory price must be clearly labelled.
- **Review notes:** explain the local StoreKit product and that there is no login.

## Organic distribution (ordered by expected leverage; all **Assumptions**)

1. **App Store search.** Title and subtitle keywords, screenshots showing the week ribbon and the check-in decision, and a clear privacy/one-time-price message.
2. **Community helpfulness.** Answer "my dough is too fast/slow tonight" questions in r/Sourdough, r/Breadit and Facebook groups with the method, not a link. Mention the app only where rules allow and when asked.
3. **Baker creators.** **[owner approval]** Offer free promo codes, with no payment or required coverage, to 10–20 small sourdough creators whose audiences are weekday bakers. Disclosure is their responsibility and should be encouraged.
4. **A free web tool.** A static "Will my dough be ready before bed?" calculator built from the parity-tested `core.js`, which ranks for search and links to the app. **[owner approval]** before any public deploy.
5. **Press and Product Hunt.** Low expected value in a crowded category. Yeast on East launched there in August 2026.

## Metrics to watch (App Store Connect only; no analytics SDK)

- Impressions → product page views → downloads by source and keyword
- Download → Pro conversion (E5)
- Ratings and review themes. Ask for a rating (`requestReview`) only after a finished bake that the user logged as "just right".
- Refund requests

## Support

- Add an in-app "Email the developer" link (not built yet; the address needs setting up **[owner approval]**).
- An FAQ covering why estimates are ranges, how calibration works, and why it isn't a food-safety tool.
