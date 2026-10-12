# FFXIV Radar — Project Outline (Ground-Up Rebuild)

A gathering/tracking companion for Final Fantasy XIV: timed mining/botany/fishing nodes,
sightseeing log vistas, aether currents, elite hunts, Blue Mage abilities, live weather, an
interactive zone map, and a live Eorzea clock. Public site, hobby-scale budget, SEO- and
ad-supported. This is a rebuild of an earlier version of the same product — the decisions
below are informed by what did and didn't work there, not made in a vacuum.

---

## Guiding principles

Short version of everything below. When a new decision isn't covered by this doc, default to
these:

1. **Domain logic is framework-agnostic, typed, and tested before any UI touches it.** The
   Eorzea time/weather engine is the hardest part of this product and has nothing to do with
   Vue. It gets built and proven correct in isolation first.
2. **No God Components.** State and logic live in composables, not in one root component that
   owns everything. If a piece of logic can't be unit-tested without mounting a component,
   that's a sign it's in the wrong place.
3. **CI, linting, and formatting exist from commit one**, not retrofitted after the fact.
4. **TypeScript `strict: true` from commit one.** Loosening it later is easy; tightening it
   later means auditing the whole codebase at once.
5. **Static content stays static; only real write paths get a database.** Game reference data
   (nodes, areas, timers, weather) is read-only — it stays versioned JSON in the repo. Anything
   with an actual write path (user accounts, synced preferences, news posts) gets real
   server-side storage. Don't blur the two.
6. **Login is additive, never required.** The core tool works fully anonymously. Accounts
   unlock cross-device sync; they don't gate access to the reference content.
7. **Decide infrastructure boundaries before the first file that depends on them is committed** —
   especially asset storage. An unclear boundary between "source art" and "what the app repo
   contains" is how a repo quietly accumulates hundreds of megabytes of unused files.

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Framework | **Vue 3 + Nuxt** | SSR/SSG, file-based routing, and per-route data fetching out of the box — a public, ad-supported, SEO-dependent site should never ship blank HTML to crawlers, which a bare client-rendered SPA does on every route. |
| Language | **TypeScript, `strict: true`** | Non-negotiable from commit one — see Guiding Principles. |
| Domain logic | **Standalone, framework-free package** (`packages/domain` or similar) | The Eorzea time/weather/window-prediction engine, fully unit-tested, with zero Vue dependency. Everything else imports from it. |
| Data validation | **Zod** (or equivalent) schema per JSON dataset | Reference data is hand-transcribed from gameplay, so transcription errors are expected. Validate shape *and* cross-references (an area that doesn't resolve to a zone, a weather name a rate table doesn't recognize) at build time — fail the build, don't ship a silent gap. |
| Game reference data | **Static JSON**, versioned in the repo | Read-only, no write path. Not a database concern. |
| User accounts & sync | **AWS Cognito** (identity) + **DynamoDB** (`Users` / `TrackedNodes` tables) | See Authentication & Accounts below. |
| News | **DynamoDB** (`NewsPosts` table), structured content, not stored HTML | See News below. Reuses the same AWS account/storage stood up for accounts rather than adding a third data technology or a CMS vendor for a feature this simple. |
| State management | **Composables**, Pinia only if it outgrows plain composables | `useFfxivData()`, `useTracking()`, `useEorzeaClock()`, `useNews()`. |
| Styling | **SCSS with a token file**, or Tailwind | Either works; not a high-leverage decision. Pick one and keep a single source of truth for color/spacing tokens either way. |
| Testing | **Vitest** + **@vue/test-utils** | Unit-test the domain package exhaustively (it's where the subtle bugs live); component-test the composables (filter/pagination, tracking, news) since that's exactly the layer that had zero coverage last time. |
| Linting/formatting | **ESLint + Prettier**, wired into CI from the first commit | Not optional, not "add it later." |
| Map | **Leaflet** | Raster game-map images as tile layers — the right tool for this specific job. MapLibre GL only if vector tiles become an actual requirement. |
| Images/CDN | **S3 + CDN with real `Cache-Control` headers.** Source art lives outside the app repo. | Decide this before the first image is committed — see Guiding Principles #7. |
| Hosting | **Vercel** | Native framework support, a real serverless runtime for both the Lodestone scrape and the news/auth API routes, solid free tier at this scale. |
| Package manager | **npm**, with `engines` + `.nvmrc` pinned from commit one | Not a high-leverage choice; pinning the Node version is. |

**On Vue vs React:** staying in Vue. The hard part of this product (time/weather domain logic)
is framework-agnostic either way, so there's no technical edge to switching, and a rebuild
that's already fixing real architectural problems doesn't need a second, unrelated learning
cost layered on top. The actual upgrade that matters is SPA → SSR/SSG (Nuxt), not Vue → React.

---

## Authentication & accounts

**AWS Cognito** User Pool for identity: Email/Password, Google, and Facebook as federated
identity providers. **DynamoDB** for everything that needs a write path per user.

- Session tokens are exchanged server-side for an `httpOnly`, `secure`, `sameSite` cookie —
  never stored raw client-side. Every API route validates the JWT server-side against
  Cognito's public JWKS.
- The app's only AWS credentials live in server-side (Vercel) functions, scoped by IAM policy
  to exactly the DynamoDB tables and S3 buckets they need. Nothing broader.
- Cognito's social-login setup is more manual than a Supabase/Firebase-style toggle —
  registering Google/Facebook as OAuth apps and wiring them as federated identity providers is
  real setup work, not a checkbox. Budget time for it; it's well-documented but not instant.
- Sign-up gets basic abuse protection (CAPTCHA or Cognito's adaptive authentication) from the
  start — a public sign-up form is a spam target on day one.
- Users get a real account-deletion path (including their DynamoDB data), not just log-out.
- **Anonymous-first:** tracked nodes default to `localStorage`. On first login, offer to merge
  local tracking into the account rather than silently discarding it. `useTracking()` picks its
  backend (local vs. synced) behind one interface so the rest of the app never needs to know
  which one is active.

---

## News (new for this rebuild — was static HTML last time)

The previous version hardcoded every news post directly into a Vue template — each post meant
editing a `.vue` file and redeploying, and the "content" was raw HTML markup sitting in the
component. This rebuild makes news a real, admin-authored, database-backed feed.

**Data model — `NewsPosts` table (DynamoDB):**

| Field | Type | Notes |
|---|---|---|
| `postId` | string (PK) | UUID |
| `publishedAt` | string | ISO 8601; also the sort key on a GSI for "list newest first" |
| `version` | string | e.g. `"v1.1.0"` |
| `title` | string | |
| `bullets` | string[] | Structured list items — **not** a raw HTML blob |
| `authorId` | string | Cognito `sub` of the admin who posted |

**Why structured fields instead of stored HTML:** rendering admin-authored HTML via `v-html`
means anything that can write a post can inject markup/scripts into every visitor's page.
Storing plain structured data (title, version, a list of strings) and rendering it through the
app's own Vue template — the same `bulleton` card layout the previous version already used —
gets the identical visual result with no injection surface at all, admin-only writes or not.

**Access pattern:**
- **Read:** a public, unauthenticated server route returns posts ordered by `publishedAt`
  descending, cached (`Cache-Control: public, max-age=300, stale-while-revalidate`, same
  pattern as the existing Lodestone endpoint) since news doesn't change often and doesn't need
  to be second-fresh.
- **Write:** an authenticated server route, gated on the caller's Cognito JWT showing
  membership in an `Admins` Cognito User Pool group — Cognito supports user groups natively, so
  this doesn't need a separate roles table. No public UI for posting; an admin-only form (or
  even a small internal script) is enough at this scale.

**Not recommended for v1:** a third-party headless CMS (Contentful, Sanity, etc.). The content
model here is genuinely simple — a dated list of bulletin posts — and pulling in a CMS vendor
adds a service, a billing relationship, and an integration to maintain for a feature that's a
few DynamoDB items and one admin form. Revisit only if the content needs actually grow past
what a flat post list can represent (categories, drafts/scheduling, rich embedded media, etc.).

---

## Feature scope (v1)

Pages/features carried forward from the previous version, unchanged in intent:
- Home, About, Privacy Policy (static)
- Timed Mining & Botany, Timed Fishing (filterable/paginated tables)
- Sightseeing Log Vistas (filterable table + vista images)
- Aether Currents, Blue Mage Abilities (checklists/reference tables)
- Weather Patterns (zone forecast table)
- Eorzea Overview (interactive zone map — Leaflet, every data layer plotted)
- Live Eorzea clock, live per-node countdowns, node tracking bar

New for this rebuild:
- Accounts (Email/Password, Google, Facebook) with cross-device tracked-node sync
- Database-backed News feed (admin-authored, publicly read)

---

## Build roadmap

Ordering logic: the hardest and most reusable piece (domain logic) is built and fully tested
in isolation first. The simplest content pages come before the hardest one (the map), to prove
conventions cheaply before spending them on the most complex screen. Accounts come after the
anonymous experience already works, since login is additive. News comes right after accounts,
since it depends on Cognito groups for admin gating.

### Phase 0 — Foundations
Repo scaffold (Nuxt + TS strict), ESLint/Prettier/CI wired and green on commit one, `engines` +
`.nvmrc` pinned, asset strategy decided, data strategy decided (JSON in-repo, validated at
build time).

### Phase 1 — Domain layer
TypeScript interfaces for every dataset (discriminated union on `job`), Zod schemas per JSON
file, the Eorzea time/weather/window-prediction engine as a standalone tested package. No UI
code is written against this layer until it has its own green test suite.

### Phase 2 — App shell
Nuxt layout, navigation, responsive breakpoints, design tokens, accessibility basics (carry
forward what already worked: skip link, ARIA labeling). Per-route data fetching wired from the
start — this is what prevents the "every route blocks on data it doesn't need" problem
structurally instead of patching it in later. Shared composables: `useTracking()`,
`useEorzeaClock()`.

### Phase 3 — First content pages
Build the simplest data page end to end (data fetch → filter/pagination composable → table →
tests) as the template every later page copies. Extract the filter/pagination composable here,
once, rather than letting it drift across five independent copies. Roll out the remaining
simple table pages on the same composable.

### Phase 4 — Timed/weather-gated content
Timed Mining & Botany, Timed Fishing, Sightseeing Vistas — where the domain engine actually
gets exercised by real UI. The shared live-countdown component, driven by `useEorzeaClock()`,
gets built once and reused everywhere a countdown appears.

### Phase 5 — The map
Leaflet integration, zone picker, layered markers by job/type. Deliberately last among the core
features — it's the largest, most dependency-heavy screen, and everything it needs (data layer,
icon resolution, countdown component) already exists and is already tested by this point.

### Phase 6 — Accounts & sync
Cognito User Pool + `Users`/`TrackedNodes` DynamoDB tables. Sign-in (Email/Password, Google,
Facebook) with server-side session handling. Anonymous → account tracking merge on first login.
`useTracking()` swapped to call the synced backend when logged in, `localStorage` otherwise —
same composable, same call sites, different backend under the hood.

### Phase 7 — News
`NewsPosts` DynamoDB table, public read route (cached), admin-only write route gated on a
Cognito `Admins` group. Structured-content rendering, no stored HTML. Depends on Phase 6
existing (needs Cognito groups for the write-access check).

### Phase 8 — Remaining auxiliary features
Static pages (Home, About, Privacy) — no data dependency, can slot in whenever convenient.
Lodestone character lookup (serverless scrape endpoint) — isolated, can be built in parallel
with anything else once hosting is set up.

### Phase 9 — Performance, SEO, and launch polish
Per-route meta description/OG tags. Bundle-size audit per route (confirm no route ships a
dataset it doesn't need). Analytics/ads wiring, Lighthouse pass, accessibility audit. A
dedicated security pass on the auth flow: cookie flags, sign-up rate limits, the
account-deletion path. Launch.

### Phase 10 — Ongoing
Keep CI green as the non-negotiable gate. Keep the DynamoDB tables scoped to what they were
built for (accounts/sync, news) — if a new feature tempts one into becoming a general-purpose
store for unrelated data, treat that as a new decision to make deliberately, not a default to
drift into.

---

## Explicitly out of scope for v1

Worth stating so it doesn't creep in by accident:
- A third-party CMS for news (see News section above).
- A relational database (RDS/Aurora) — DynamoDB covers every write path identified so far;
  revisit only if the data model becomes genuinely relational.
- Full AWS-native hosting (Amplify) — Vercel plus Cognito/DynamoDB for identity/storage is the
  chosen split; revisit only if there's a real reason to want everything under one platform.
- User-generated content beyond tracked-node sync (comments, ratings, etc.) — not part of the
  product today; would be its own scoping exercise if it ever comes up.
