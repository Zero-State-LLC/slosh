# Economics

An honest assessment of whether this can make money. Written to be argued with,
not to justify a decision already taken.

**Summary: build it as a portfolio piece and a craft exercise. If it earns, treat
that as a bonus.** The engineering is the valuable output; the revenue case is
weak and the reasons are structural rather than fixable by pricing.

The canonical product shape is hybrid, not confused: **Experiences** are authored
expressive water states, and **Places** are evidence-grounded representations of
real waters. This is product architecture, not a new pricing split. Monetization
questions should not weaken the representative-water doctrine or imply arbitrary
geographic coverage.

## The mechanics

| Item | Figure |
|---|---|
| Apple Developer Program | $99 / year |
| Apple commission, standard | 30% |
| Apple commission, [Small Business Program](https://developer.apple.com/app-store/small-business-program/) (<$1M/yr) | 15% |
| Net on a $0.99 sale, Small Business | ~$0.84 |
| Net on a $2.99 sale, Small Business | ~$2.54 |
| Sales to cover the developer account at $0.99 | ~118 |
| Sales to cover it at $2.99 | ~39 |

The commission is not the problem. Breaking even on the account fee is a low bar.

## The actual problem is distribution

Three structural headwinds, in order of severity:

**1. Watch-only discovery is poor.** The Watch App Store is a small, rarely
browsed surface. There is no meaningful search traffic to capture and no
editorial pipeline comparable to iOS. An app that exists only on the watch is
close to undiscoverable without outside traffic.

**2. The category is crowded and subscription-led.** Ambient, relaxation and
sleep apps are a mature market whose winners run paid acquisition against
subscription lifetime value. A one-off unlock cannot buy installs at those
prices, so the only viable route is organic.

**3. Nobody is searching for this.** There is no query with intent behind it.
"Water app" is not a thing people look for. Demand has to be created by showing
someone the thing moving, which makes distribution a content problem, not an ASO
problem.

### What that means numerically

An unpromoted watch-only launch realistically sees **tens to low hundreds of
lifetime downloads**, converting at maybe **2–5%** on an in-app purchase. At
$2.99 that is roughly $5–40 net. Lunch money.

The upside case is not a better funnel — it is a single piece of content
travelling. One good loop of Aurora or Storm at night on a social platform is
worth more than every optimisation on this page combined, and it is also
entirely outside your control.

## If you want to try anyway

Four things matter, roughly in order of impact.

### 1. Ship iPhone and iPad, not just the watch

This is the single biggest lever and it is not close. iOS has real discovery,
and it additionally has **Metal and SwiftUI shader effects**, both absent on
watchOS — so the same water can look considerably better on the bigger screen
(depth of field, foam detail, real sky reflection). `OceanCore` and `OceanUI`
already port unchanged.

Make it a universal purchase and let the watch app be the charming hook rather
than the whole product.

### 2. One unlock, never a subscription

"$2.99 unlocks every mode" fits what this is. Nobody subscribes to a water app,
and asking converts goodwill into a one-star review. A subscription also commits
you to a content treadmill for an audience that does not want one.

### 3. Give away a genuinely good free tier

Suggested split — five free, ten paid:

| Free | Paid |
|---|---|
| Calm ocean | Tide pool, Koi pond, Under ice, Aurora |
| Rain shower | Deep drift, Zero gravity, Molten, Mercury |
| Tropical lagoon | Storm swell, Storm at night |
| Midnight glow | |
| Breaking surf | |

The free set has to stand on its own — Rain shower and Breaking surf are the two
most compelling modes and both are free on purpose. The unlock should feel like
supporting something you already like, not like removing a blockade. An app that
feels crippled gets deleted, and a deleted app sells nothing.

### 4. Treat the demo loops as the product

The GIFs in `media/` are the marketing asset. Budget real effort there: capture
on device, at high frame rate, with actual wrist motion rather than simulated
drags.

## Costs to weigh against it

- **$99/year**, ongoing, whether or not anyone buys.
- **App Review**, which for a watch-only app with no obvious utility can attract
  guideline 4.2 ("minimum functionality") scrutiny. See
  [ROADMAP.md](ROADMAP.md#phase-4--submission) for how to mitigate.
- **Support and compatibility** — every watchOS release is a re-test.
- **Opportunity cost**, which is the real one. The engineering here is a
  stronger asset on a CV or in a portfolio than the revenue is in a bank
  account.

## Alternative models considered, and rejected

| Model | Why not |
|---|---|
| Subscription | Wrong shape for a one-sitting product; invites resentment |
| Ads | Destroys the entire premise, which is calm |
| Paid up front | Kills the funnel; nobody buys an unknown ambient app sight-unseen |
| Free, no monetisation | Reasonable! Costs $99/yr for goodwill and a portfolio link |
| Open source + donations | Also reasonable, and compatible with a paid iOS build |

**Recommendation: free with a single $2.99 unlock, iOS-first for discovery, and
no expectation that it pays for itself.** Ship it because it is good, and
because "I wrote a fragment shader that runs on a platform with no shader API"
is a better story than most side projects have.
