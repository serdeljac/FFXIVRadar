# FFXIV Radar — If We Started From Scratch

A hypothetical: same product (a gathering/tracking companion for FFXIV — timed nodes, vistas,
weather, a zone map, a live Eorzea clock), same scale (solo/small-team, hobby budget, public
SEO-driven site with ads), but no existing code. What stack would a professional team pick,
and in what order would they build it?

The recommendations below are grounded in what actually happened building this app the first
time — see `engineering-assessment.md` for the specifics being referenced throughout.

---

## The stack

| Layer | Recommendation | Why |
|---|---|---|
| Framework | **Vue 3 + Nuxt** (not a bare Vite SPA) | See "Vue vs React" below. Nuxt over plain Vue+Vite specifically because it adds SSR/SSG, file-based routing, and per-route data fetching for free — which would have prevented §1's "every route blocks on 4.1MB of JSON" problem from ever existing, instead of needing a retrofit. |
| Language | **TypeScript, `strict: true` from commit one** | The existing app has 128 `any`s and `strict: false` because turning strict mode on after the fact means fixing everything at once. Starting strict costs a little more up front per-file and costs nothing to keep. |
| Domain logic | **Framework-agnostic package**, tested in isolation | The Eorzea time/weather/window-prediction engine (`hooks.ts` in the current app) is the hardest, most bug-prone part of this product and has nothing to do with Vue. Build it as a plain TS module (or its own workspace package) with its own test suite from day one — see Phase 1. |
| Data validation | **Zod** (or similar) schema for every JSON dataset | The reference data is hand-transcribed from gameplay (per the current site's own About page). Transcription errors are expected, not exceptional — CLAUDE.md already documents several ("a few weather names never occur in their zone"). Validating shape *and* flagging cross-references that don't resolve (an area with no matching zone, a weather name the zone's rate table doesn't recognize) at build time turns "silent `—` in production" into "build fails with a clear message" months earlier. |
| Data storage | **Static JSON for game reference data; DynamoDB for user accounts/sync** | Game content (nodes, areas, timers, weather) is read-only and has no write path — keep it as versioned JSON, same reasoning as before. User accounts and synced preferences are a genuine write path now that login is in scope — see Authentication below. Don't blur the two: reference data doesn't move into the user store just because one now exists. |
| Authentication | **AWS Cognito** (Email/Password + Google + Facebook as federated identity providers) | See "Authentication & accounts" below. |
| State management | **Composables (Pinia if it grows past a handful)**, never one root component | The current app's `App.vue` is a ~740-line God Component owning all state, loading, and business logic in Options API, which is why none of it is unit-testable and why the data-loading gate couldn't be scoped per-route without a refactor (§1, §8). Build the data layer as composables from the start: `useFfxivData()`, `useTracking()`, `useEorzeaClock()`. |
| Styling | **SCSS with a token file** (current approach) or **Tailwind** | Either is fine; not a high-leverage decision for this app. The current `variables.scss`-as-single-source-of-truth pattern already works well — keep it if staying with hand-written SCSS. |
| Testing | **Vitest** (unit) + **@vue/test-utils** (component) from the start | Vitest was the right call the first time. The gap wasn't the tool, it was coverage: only the math got tested, not the page-level filter/pagination/tracking logic that lived inside `.vue` files and couldn't be unit tested because it was trapped in Options API methods. Composables fix the "can't test it" problem; write the tests as each composable is built, not after. |
| Linting/formatting | **ESLint + Prettier + CI, wired before the first feature PR** | This app went through its entire first build without either. Retrofitting them later (as happened this session) means either accepting hundreds of pre-existing warnings or blocking on a big cleanup pass. Costs nothing to add on day one. |
| Map | **Leaflet** (current choice) or **MapLibre GL** | Leaflet is the right call for raster game-map images as tile layers, which is what this needs — no reason to switch. MapLibre GL is worth it only if vector tiles or smoother pan/zoom become a real requirement. |
| Images/CDN | **S3 (or equivalent) + CDN with real `Cache-Control` headers, from day one; source art never lives in the app repo** | The current repo has 232MB of images sitting in `src/assets/` that aren't even used in production (§3) — that happened because there was never an explicit decision about where "source art" lives versus what the app repo contains. Decide this before the first image is committed: app repo holds only what's actually bundled or referenced; source/working art lives elsewhere (a separate repo, or cloud storage directly). |
| Hosting | **Vercel** (current choice) | Good fit: native support for whatever framework is chosen, a real serverless runtime for the Lodestone-scraping endpoint, solid free tier for a hobby-scale public site. No reason to move. |
| Package manager | **npm is fine**; pin the Node version | Not a high-leverage choice either way. Do add an `engines` field in `package.json` and a `.nvmrc` from the start — neither exists in the current repo, which is why a `jsdom` engine-mismatch warning went unnoticed this session. |

---

## Vue vs React

**Recommendation: stay in the Vue ecosystem, specifically move to Nuxt.**

Reasoning, in order of weight:

1. **This app's hard problem isn't the UI framework.** The genuinely difficult part — Eorzea
   time math, weather window prediction, spawn-condition resolution — is framework-agnostic
   business logic. Vue vs React makes essentially no difference to how hard that code is to
   write or test. Neither framework has an edge on tables, filters, forms, or a Leaflet map,
   which is the rest of the UI.
2. **You already know Vue.** A rebuild is a chance to fix real architectural problems (the God
   Component, the eager data load, the missing types). None of those problems are things React
   would have prevented — they're patterns, not framework limitations. Switching frameworks on
   top of a rebuild adds a second, unrelated learning cost (JSX, hooks' rules of dependencies,
   a different composition model) without buying a corresponding technical win here.
3. **The actual upgrade worth making is SPA → SSR/SSG**, and that's a meta-framework choice
   (Nuxt vs Next.js), not a framework choice (Vue vs React). A public, ad-supported,
   SEO-dependent site being a pure client-rendered SPA — as this one currently is — means every
   route ships blank HTML and a loading spinner to crawlers and first paint alike. Nuxt (Vue) or
   Next.js (React) both fix this equally well. Since #2 already favors staying in Vue, Nuxt is
   the one that doesn't also cost a framework switch.
4. If there were a green-field reason to prefer React specifically — e.g. a hard requirement to
   reuse an existing React component library, or hiring plans around a team that's React-only —
   that would outweigh the above. Absent that, there's no technical reason to leave Vue.

---

## Authentication & accounts

**Recommendation: AWS Cognito** (User Pool) for identity — Email/Password plus Google and
Facebook wired in as federated identity providers — with **DynamoDB** as the server-side store
for accounts and synced tracked-node preferences.

**Why AWS specifically:** the app already runs real AWS infrastructure in production today —
the vista images are served from an S3 bucket. Extending that same account/region/IAM
boundary to cover identity and user data is lower-friction than onboarding an entirely new
vendor (Supabase, Firebase) for a second, unrelated piece of the stack, and keeps billing,
IAM policy, and access review in one place.

**Why DynamoDB over RDS/Aurora for this specific data:** the access pattern here is simple —
essentially one item per user holding their tracked-node IDs and preferences, looked up by
user ID. That's a textbook DynamoDB shape: a single-table design with one partition key per
user. DynamoDB's on-demand pricing scales to near-zero cost at hobby-scale traffic and needs
no instance to provision or patch, unlike RDS (which bills for a running instance regardless
of traffic) or even Aurora Serverless v2 (which still has a non-zero capacity floor). If the
data model grows meaningfully relational later — multiple linked entities, complex queries
across users — that's the point to revisit RDS/Aurora, not before.

**Honest trade-off vs. Supabase/Firebase:** Cognito's developer experience for social login is
rougher than either. Supabase/Firebase let you toggle on Google or Facebook sign-in in a few
clicks; Cognito requires registering Google/Facebook as OAuth apps yourself and configuring
each as a federated identity provider on the User Pool — well-documented, genuinely supported,
but more manual setup and more moving parts to get right the first time. Worth knowing going
in, not discovering mid-build.

**Architecture — keep hosting on Vercel, use AWS for identity/storage only:** there's no reason
raised here to move hosting off Vercel, and Cognito/DynamoDB don't require it. The pattern is
the same one the current app already uses for the Lodestone scrape endpoint
(`api/_lodestone.ts`) — a Vercel serverless function as the thin server-side layer, except this
one validates a Cognito-issued JWT and reads/writes DynamoDB via the AWS SDK instead of
scraping a webpage. Same shape of code, different destination. (The alternative is AWS Amplify,
which bundles hosting + Cognito + DynamoDB + S3 under one AWS-native framework — worth
considering only if there's a reason to want everything under one platform; absent that, it's
an extra layer on top of a Vercel setup that's already working well.)

**What this changes elsewhere in the plan:**
- The "static JSON, not a database" call above still stands for *game content* — that's still
  read-only reference data with no write path. It's user accounts and synced preferences that
  need server-side storage now, and that's a separate, much smaller dataset — not a reason to
  move game data into DynamoDB too.
- Auth should be **additive, not required**. The current app's core value — browse timed nodes,
  check weather, see the map — works fully anonymously today, and that should stay true. Login
  unlocks cross-device sync; it shouldn't gate the reference-tool experience behind a signup
  wall. Keep the `localStorage` tracking path as the logged-out default, and add a one-time
  "merge local tracking into your account" step the first time an anonymous user logs in, so
  nobody loses what they'd already tracked.

**Security/implementation notes to get right from the start, not after a report:**
- Never handle OAuth tokens or password hashing directly — that's the entire point of using a
  managed identity provider instead of rolling it by hand. Let Cognito issue and verify tokens
  (via `amazon-cognito-identity-js` or AWS Amplify's Auth library); the app only ever sees a
  signed JWT, never a password or a provider secret.
- Session handling: exchange the Cognito tokens for an `httpOnly`, `secure`, `sameSite` cookie
  set by a Nuxt server route, not stored raw in `localStorage` where any XSS on the site could
  read it. Validate the JWT server-side (against Cognito's public JWKS) on every API call.
- The Vercel function's AWS credentials should be scoped by IAM policy to exactly the one
  DynamoDB table it needs — read/write on that table only, nothing broader — same least-
  privilege principle that should already apply to whatever credentials serve the S3 bucket.
- Email sign-up needs basic abuse protection (a CAPTCHA, or Cognito's built-in risk-based
  adaptive authentication) — a public site with an open sign-up form is a spam-bot target from
  day one, not eventually.
- Give users a real way to delete their account and its DynamoDB data, not just log out — a
  small thing to build in from the start, a much bigger retrofit once real users exist.

---

## Roadmap — build in this order

The ordering is deliberate: the hardest and most reusable part (domain logic) comes first and
gets built framework-free, so it can be fully tested before a single page exists. The simplest
content pages come before the hardest one (the map), to establish conventions cheaply before
spending them on the most complex screen.

### Phase 0 — Foundations (before any feature code)
1. Repo scaffold: Nuxt + TypeScript (`strict: true`), ESLint + Prettier configured, CI
   (build + lint + test) wired and green on the first commit.
2. `engines` field + `.nvmrc`, pinning the Node version used in CI and locally.
3. Decide and document the asset strategy (see the Images/CDN row in the stack table above)
   before a single image is committed.
4. Decide the data strategy: JSON files in-repo, versioned like code, validated at build time.

### Phase 1 — Domain layer (framework-free, fully tested before any UI exists)
1. Define TypeScript interfaces for every dataset (nodes, areas, timers, weather) as a
   discriminated union on `job`, so branching logic (`if (node.job === 'sightseeing')`) is
   type-narrowed instead of trusted at runtime.
2. Add Zod schemas (or equivalent) for each JSON file; fail the build on a row that doesn't
   match shape or on a cross-reference that doesn't resolve (mirrors the "expected data gaps"
   already documented for the current app, but catches new ones immediately instead of via a
   console warning in production).
3. Port/rebuild the Eorzea time and weather-window-prediction engine as a standalone, Vue-free
   TS module. Write its test suite alongside it — this is the part of the current app that's
   already well-tested, and for good reason: it's where the subtlest bugs live.
4. Only once this layer has its own green test suite does any UI code get written against it.

### Phase 2 — App shell
1. Nuxt layout: navigation, responsive breakpoints, design tokens (SCSS variables or Tailwind
   config), the "skip to content" / accessibility basics the current app already does well —
   carry those forward rather than re-deriving them.
2. Routing and per-route data fetching using Nuxt's data-fetching primitives, scoped per page
   from the start — this is what prevents §1's problem structurally instead of patching it in
   after the fact.
3. Shared composables: `useTracking()` (localStorage-backed tracked-node list),
   `useEorzeaClock()` (a single reactive clock tick, matching the current app's `useNow()`
   pattern — that part was already right).

### Phase 3 — First content pages (simplest first, to prove the pattern cheaply)
1. Pick the simplest data page (e.g. Aether Currents — a checklist, minimal logic) and build it
   end to end: data fetch → filter/pagination composable → table → tests. This is the template
   every later page copies.
2. Extract the filter/pagination logic as a shared composable from the start (the current app
   copy-pasted it into five pages independently and let the APIs drift — §5). Build it once,
   here, before a second page exists to copy from.
3. Roll out the remaining simple table pages (Blue Mage Abilities, Weather Patterns) using the
   same composable.

### Phase 4 — Timed/weather-gated content
1. Timed Mining & Botany, Timed Fishing, Sightseeing Vistas — these are where the Phase 1 domain
   engine actually gets exercised by real UI. Build these once the engine and the filter
   composable both already exist and are already tested, not before.
2. Live countdown display component, driven by the shared clock composable — one component,
   reused everywhere a countdown appears (table row, tracking bar, details pane), exactly like
   the current app's `<DisplayTime>` — that pattern was correct the first time.

### Phase 5 — The map (most complex single screen, done once conventions exist)
1. Leaflet integration, zone picker, layered markers by job/type.
2. This is deliberately last among the core features: it's the largest single file in the
   current app (1800+ lines) and touches every dataset at once. Every other page existing first
   means the data layer, icon resolution, and countdown components it depends on are already
   built and already tested.

### Phase 6 — Accounts & sync
1. Set up the Cognito User Pool (Email/Password, plus Google and Facebook registered as
   federated identity providers) and the DynamoDB table for synced tracked-node preferences,
   keyed by user ID.
2. Build the thin Vercel serverless API layer that validates a Cognito JWT and reads/writes
   that DynamoDB table — same pattern as the existing Lodestone endpoint, pointed at AWS
   instead of a scraped webpage. IAM policy scoped to that one table only.
3. Wire up sign-in (Email/Password, Google, Facebook) via Cognito's SDK/Amplify Auth. Tokens
   exchanged server-side for an `httpOnly` session cookie — never stored raw in `localStorage`.
4. Build the anonymous → account merge step: the first login after having tracked nodes
   locally should offer to import them, not silently discard them.
5. Swap `useTracking()`'s storage backend to call the DynamoDB-backed API when logged in,
   `localStorage` when not — same composable, same call sites in the UI, different backend.
   This is exactly why that logic lived in a composable from Phase 2 onward: the UI never
   needs to know which backend it's talking to.
6. Deliberately placed after the core reference-tool experience (Phases 1–4) already works
   anonymously — login is additive, and building it after the anonymous path is solid keeps
   that guarantee honest instead of assumed.

### Phase 7 — Auxiliary features
1. Static pages (Home, About, News, Privacy) — genuinely simple, low risk, can slot in whenever
   convenient; they have no data dependency so they're never blocking.
2. Lodestone character lookup (serverless scrape endpoint) — isolated, low-risk, can be built
   in parallel with anything else once hosting is set up.

### Phase 8 — Performance, SEO, and launch polish
1. Per-route meta description/OG tags (trivial with Nuxt's `useHead`, and this is the point
   where it's cheapest to add — SEO becomes expensive to retrofit once every page's copy has to
   be revisited).
2. Bundle-size audit per route; confirm no dataset larger than a page actually needs is in that
   page's chunk (Nuxt's per-route data fetching should make this the default outcome, not
   something to fix after the fact).
3. Analytics/ads wiring, Lighthouse pass, accessibility audit.
4. Security pass on the auth flow specifically: cookie flags, rate limits on sign-up, an
   account-deletion path — see the Authentication section above.
5. Launch.

### Phase 9 — Ongoing
1. Keep CI green as the non-negotiable gate — it was free on day one and should stay that way.
2. The DynamoDB table from Phase 6 is scoped tightly to auth + synced preferences on
   purpose. If new features tempt it into becoming a general-purpose store for other data,
   treat that as a new decision to make deliberately, not a default it drifts into.
