# FFXIV Radar — Engineering Assessment

Read as a whole-codebase review, not a to-do list to blast through at once. Findings are
ordered by leverage: fix the top ones first, they touch the most users/code for the least risk.

This is a solid hobby-to-production codebase — the existing `CLAUDE.md` is unusually honest
about its own known bugs, the Eorzea time/weather engine (`src/hooks/hooks.ts`) is genuinely
well-designed, and accessibility got real attention (skip link, `role="table"`, the
`data-x || null` gotcha). The gaps below are normal for a project built solo and fast, not
signs of carelessness.

---

## Progress log

- **§2 (CI + lint) — done.** Added `.github/workflows/ci.yml` (two jobs: `lint`, `build-and-test`,
  both on push/PR to `main`). Added ESLint 10 (flat config, `eslint.config.js`) with
  `typescript-eslint` + `eslint-plugin-vue`, wired as `npm run lint`. `@typescript-eslint/no-explicit-any`
  is set to `warn` rather than `error` — see §6, turning it on as `error` now would mean fixing
  ~128 call sites before any PR could merge, which isn't this step's job. Also added Prettier
  (`.prettierrc.json`, `npm run format` / `format:check`) but **did not** wire `format:check`
  into CI yet: the codebase has never been run through a formatter, so it currently flags 67 of
  ~70 files. Running `npm run format` is a one-time, zero-behavior-change, repo-wide diff — worth
  doing as its own deliberate, reviewed commit, not silently bundled into this step.
- Fixing the real errors the first lint pass surfaced turned up two small pre-existing bugs,
  fixed alongside this (not architectural, safe to have folded in):
  - `App.vue`'s `data()` had `_clockInterval`/`_resizeHandler` — Vue 3's Options API reserves
    `_`/`$`-prefixed `data()` keys and won't expose them via `this.foo`; reads/writes were
    silently falling through to an unproxied plain instance property instead of the reactive
    slot. It happened to still work (nothing here needed reactivity), but relied on undocumented
    fallback behavior. Renamed to `clockIntervalHandle`/`resizeHandler`.
  - `7_WeatherPatterns.vue`'s `filteredZones` computed mutated `filterSelected` as a side effect
    of being read (auto-selecting the first expansion). Moved that into a `watch(filters, …, {
    immediate: true })` instead, so the computed is a pure derivation again. Same observable
    behavior — first expansion is still auto-selected — just not from inside a getter.
- **§1 (route-scoped loading) — quick-fix scope done, full redesign still open.** Added
  `needsData: false` route `meta` (`src/main.ts`) for the five static routes (`/`, `/aboutUs`,
  `/news`, `/privatePolicy`, the 404 catch-all) and a `routeNeedsData` computed in `App.vue` that
  the loading gate now checks (`v-if="loading && routeNeedsData"`). Those five pages render
  immediately instead of waiting on the full 14-file JSON load; the seven data-driven pages are
  unchanged. The bigger win — only loading the JSON each data page actually needs — is still open;
  see §1's "Full redesign" option.
  - **Known minor side effect, not yet fixed:** `setEorzeaClock()` only runs after the full JSON
    load finishes (inside `setupInitialFFXIVData`), even though it has no dependency on any of
    that data — `EorzeaTime()` is purely wall-clock-based. So the sidebar clock shows `00:00` for
    a moment on a static-page visit until the background load completes. Small, contained fix
    when picked up: call `setEorzeaClock()` (and maybe start the clock interval) in `created()`
    before awaiting `setupInitialFFXIVData()`, leaving the genuinely data-dependent parts
    (`createWeatherList`, `setTimerData`, `setGoldSaucerState` can stay either place) where they are.
- **§4 (legacy countdown bug) — done.** Traced every consumer of the buggy
  `timerList[].stateActive`/`.countdown` (`App.vue`'s old `recalcTimerCountdowns`) before touching
  anything: two live call sites (`nodeTimeChecker` in `2_TimedMiningBotany.vue`'s row-highlight
  class, `isNodeActive` in `1_EorzeaOverview.vue`'s `data-rowActive`), plus `EorzeaMap` and
  `getTimerCountdown` which turned out to already be dead code (defined, never called). Migrated
  both live call sites to the correct engine (`isNodeWindowActive`/`useNow()` from `hooks.ts`,
  the same pattern `3_TimedFishing.vue`/`DetailsPane.vue`/`TrackingBarItem.vue` already used),
  preserving the `|| null` coercion on the `data-` attribute site per the gotcha `DetailsPane.vue`
  already documents (a plain `false` would still match a `[data-rowActive]` CSS selector). Then
  deleted: `recalcTimerCountdowns`, the per-second decrement loop in `onClockTick`, the now-dead
  `stateActive`/`seconds`/`countdown` fields in `setTimerData`, App.vue's `formatDuration` (a
  duplicate of the one in `hooks.ts`, only called from the deleted code), and hooks.ts's
  `isTimerActive`/`getTimerCountdown`/`isWeatherMatch`/`isNodeActive`/`EorzeaMap`/`nodeTimeChecker`.
  `findTimer` stayed — the window engine still calls it internally. Net effect: row-highlight
  "active" pulsing and `data-rowActive` now correctly light up for all 135 timers, including the
  29 that wrap midnight, and agree with the countdown text `<DisplayTime>` already showed
  correctly. Build, lint (0 errors), and all 66 tests pass.
  - **Not yet touched:** `displayRanges12Hr`/`displayRanges24Hr` (built in `setTimerData` via
    `buildRangeStrings`/`fmt12Hr`/`fmt24Hr`) turned out to be dead code too — built but never
    rendered anywhere. Left alone since it's unrelated to the countdown bug and might be
    half-finished work for a planned "browse all timer windows" page rather than an oversight;
    worth asking before deleting.

---

## Top 5 priorities

*(Status markers added after the initial pass — see Progress log above for what's shipped.)*

1. **◐ Partially done.** Every route blocks on 4.1MB of JSON it mostly doesn't need —
   including static pages like Home and About Us. This is the single biggest user-facing win
   available. The five static pages no longer wait on it; the seven data-driven pages still do.
2. **✅ Done.** No CI, no linter. Nothing stopped a broken build or an obvious mistake from
   reaching `main` except remembering to run `npm run build` yourself.
3. **232MB of images live in the repo; ~all of them appear unused in production.** Vista
   art is served from S3, not from `src/assets/sightseeing/`. That's slowing every clone,
   CI checkout, and editor index for no runtime benefit.
4. **✅ Done.** The legacy countdown engine (`recalcTimerCountdowns` in `App.vue`) had two
   known-wrong bugs and was still what table highlighting read. It's now deleted; every
   consumer goes through `hooks.ts`'s correct window engine.
5. **Filter/pagination logic is hand-copied into 5 different page components** with
   subtly different APIs. One composable would delete ~150 lines and remove a whole class
   of "works on page 2, broken on page 3" bugs.

---

## 1. Data loading blocks the whole app, not just the pages that need it

**◐ Status: quick-fix scope done, full redesign still open — see Progress log above.** The
analysis below describes the original, fully-unscoped problem; the five static routes have
since been exempted from the loading gate.

`App.vue`'s `created()` hook awaits `setupInitialFFXIVData()` — a `Promise.all` of all 14
JSON files under `src/assets/json/` — before `loading` flips to `false` and *anything*
renders (`src/App.vue:161-173`, `:228-259`). Every route receives the resulting `ffxivData`
as a prop whether it touches it or not (`src/App.vue:32-44`).

Measured: `src/assets/json/` totals **4.1MB**, with `nodes_fishing.json` alone at **1.8MB**
(`nodes_fates.json` 504K, `nodes_botany.json` 444K, `nodes_miner.json` 344K, `areas.json`
340K, …). None of it is in `vite.config.ts`'s `manualChunks` split (`vite.config.ts:56-70`
only buckets `nodes_miner`/`nodes_botany`, `nodes_fates`/`nodes_huntpoints`, and three more —
`nodes_fishing.json`, the largest file, isn't mentioned at all), so it rides along with
whatever chunk Rollup happens to put it in.

`Home.vue` and `11_AboutUs.vue` are pure static content — a welcome blurb and an about
page — and never reference `ffxivData` (confirmed by reading both). They still wait behind
the full data load because the loading gate is app-wide, not route-aware.

**What a professional team would do:**
- Move the `loading` gate to be per-route, not global — static pages (`Home`, `AboutUs`,
  `RadarNews`, `PrivatePolicy`, `Error404`) should render immediately.
- Load each JSON dataset only when a route that needs it is visited (dynamic `import()`
  inside the page's own setup, not one upfront `Promise.all` in the root). Vite's existing
  route-level code splitting (`src/main.ts:6-13`) already does this for *code* — data should
  follow the same pattern.
- Once per-route loading is in place, revisit `manualChunks`: it can likely be deleted
  entirely, since Vite will naturally split each JSON import into the chunk of the page
  that imports it.
- Longer-term, consider whether `nodes_fishing.json` (1.8MB of static reference data)
  belongs in the client bundle at all versus a small paginated/filterable API endpoint —
  but that's a bigger architectural change; the route-scoped lazy-load above is the
  20%-effort/80%-result fix.

---

## 2. No CI, no linter, no formatter

**✅ Status: done — see Progress log above.** The analysis below describes the state as found;
CI, ESLint, and Prettier now exist.

Checked: no `.eslintrc*`, no `prettier` config, no `.editorconfig`, no `.github/workflows/`
directory at all. The only automated gate is `npm run build`, which runs `vue-tsc -b` before
`vite build` (`package.json:8`) — and that only runs when a human remembers to run it, since
nothing runs it on push or PR.

Given `tsconfig.app.json` already has `noUnusedLocals`, `noUnusedParameters`, and
`noFallthroughCasesInSwitch` on (`tsconfig.app.json:9-12`), there's clearly an intent toward
rigor here — it just isn't enforced automatically, and there's no linter covering the things
`tsc` can't see (unused Vue template refs, inconsistent patterns, accidental `console.log`s).

**What a professional team would do:**
- Add a GitHub Actions workflow that runs `npm ci && npm run build && npm test` on every
  push/PR. This alone would have caught regressions before merge for the last several
  commits' worth of manual fixes (`git log` shows repeated "fix map marker issue" /
  "fixed fishing timer bugs" commits — some fraction of that churn is what CI exists to
  prevent).
- Add `eslint` with `eslint-plugin-vue` + `@typescript-eslint`, and `prettier` for
  formatting. Even a light config (no opinionated rules, just "no unused vars", "no
  implicit any drift", consistent quotes) pays for itself within a month on a codebase
  this size.

---

## 3. 232MB of images in the repo, most apparently unused

`src/assets/sightseeing/` contains hundreds of `.webp` files per expansion folder (e.g.
`arr/` alone has 80). But the only code path that renders a vista image —
`FetchVistaImage.vue:16` — fetches from
`https://ffxivradar-...s3.ca-central-1.amazonaws.com/vistas/...`, not from
`src/assets/sightseeing/`. A repo-wide search found **no other reference** to that folder
anywhere in `src/`.

`du -sh src/assets` reports **232MB**; the production `dist/` build is **3.8MB**. That gap is
almost entirely these images doing nothing at runtime — they're presumably the source
material that was uploaded to S3 once, then never removed from git.

**What a professional team would do:**
- Confirm with a full-history grep (`git log -p -- src/assets/sightseeing` or similar) that
  nothing depends on these files, then remove them from the working tree and, if repo size
  matters (clone time, CI checkout time), scrub them from history too
  (`git filter-repo`/BFG) since a plain `git rm` doesn't shrink `.git`.
- If this asset folder is intentionally kept as the "source of truth" that gets synced to
  S3, move it out of `src/` (which implies "the app imports this") and into a top-level
  `asset-pipeline/` or similar, ideally in a separate repo, so it's never mistaken for
  something the build consumes.

---

## 4. The legacy countdown engine is still live, and it's wrong

**✅ Status: done — see Progress log above.** The analysis below describes the bug as found;
the legacy path has since been deleted and every consumer migrated.

`CLAUDE.md` already documents this precisely (lines 88-96), so this section just connects
it to where it still matters. `App.vue`'s `recalcTimerCountdowns` (`src/App.vue:548-590`):

- Converts Eorzea minutes to real seconds as `minsUntil * 3`, but the correct factor is
  `175/60 ≈ 2.9167`. Every countdown fed by this path runs ~2.9% long.
- Only checks `curMin <= s` / `curMin <= e` per window — for a wraparound timer like
  `18 → 2`, both branches are false all day, so `stateActive` is permanently `false` for
  those 29 of 135 timers.

The replacement engine in `hooks.ts` (`timerWindows`, `activeRunEnd`, `nextSpawnAt`) fixes
both problems and is what `<DisplayTime>` renders — so the *printed countdown text* is
correct wherever that component is used. But `timerList[].stateActive` is still what drives
row highlighting: `2_TimedMiningBotany.vue:73` binds
`{'nodeIsActive': nodeTimeChecker(d, timerList, true)}`, and `nodeTimeChecker`
(`src/hooks/hooks.ts:542-554`) reads `timerListObj.stateActive` straight off the buggy list.
So today, a wraparound-timer node can show the *correct* countdown text next to a row that
never gets the "active" pulse styling it should.

**What a professional team would do:** retire `recalcTimerCountdowns`/`onClockTick`'s manual
timer math entirely and have every remaining consumer (`nodeTimeChecker`, `isNodeActive`,
`EorzeaMap`) go through `isNodeWindowActive`/`nodeCountdown` from `hooks.ts` instead, the
same way `<DisplayTime>` already does. This is a deletion, not a rewrite — the correct logic
already exists.

---

## 5. Filter/pagination logic is copy-pasted across pages, with drifting APIs

`changeFilter`, `resetFilters`, `filterByInputValue`, and the `filters.value.forEach(...)`
reset pattern are independently reimplemented in at least five route components:
`2_TimedMiningBotany.vue`, `3_TimedFishing.vue`, `4_SightseeingVistas.vue`,
`5_AetherCurrents.vue`, `6_BlueMageAbilities.vue`. They've already diverged:
`2_TimedMiningBotany.vue:201` and `3_TimedFishing.vue:208` take a `Filter` object (multi-
select, opt-out style), while `4_SightseeingVistas.vue:190`, `5_AetherCurrents.vue:134`, and
`6_BlueMageAbilities.vue:92` take an `arrayIndex` (looks like single-select). That may be
intentional per-page UX — but if it isn't, this is exactly the kind of inconsistency that
copy-paste produces: nobody decided it, it just happened because each page started from a
clipboard paste of the last one.

**What a professional team would do:** extract a `useFilterablePagedList` (or two — one for
multi-select opt-out filters, one for single-select) composable in `src/hooks/`, taking the
source array and group keys, returning `filters`, `compiledDataForTable`, `arraySet`, and
the mutator functions. Each page then becomes a thin template + one composable call. This
also makes the filtering logic unit-testable in isolation, which it currently isn't (see
§7).

---

## 6. Type safety is opted out of almost everywhere it matters

`tsconfig.app.json:8` sets `"strict": false`, and it shows: `App.vue` alone has **67**
`: any` annotations, **128** across `src/` as a whole. `ffxivData` — the single object every
page in the app depends on — is typed as `{ areas: any[], miner: any[], fishing: any[], ... }`
(`src/App.vue:128-141`). `hooks.ts` follows the same pattern (`node: any`, `timerList: any[]`
throughout).

This isn't a style nitpick: it means `vue-tsc -b`, the only automated check gating a merge,
is structurally unable to catch a large class of real bugs here — e.g. a typo'd field name
on a node object, or passing a `fishing` node where a `sightseeing` node was expected,
compiles clean either way. The domain is even naturally suited to strong types — 14 fixed
JSON shapes, a closed set of `job` values (`'miner' | 'botany' | 'fishing' | 'sightseeing' |
...`) driving `switch`-like branches throughout `hooks.ts` and `App.vue`.

**What a professional team would do:** this doesn't need to be a big-bang rewrite. A
practical path:
1. Define interfaces for the 14 JSON shapes once (`src/types/data.ts` or similar) — these
   are static reference data, so the shapes are stable and worth writing by hand or
   generating once from the JSON.
2. Define a `Node` discriminated union keyed on `job`, so `node.job === 'sightseeing'` narrows
   `node.weather1` etc. the way `hooks.ts`'s branching logic already assumes at runtime.
3. Turn on `strict` incrementally — TypeScript supports enabling strict per-file gradually
   isn't built in, but tackling `hooks.ts` first (it's the most logic-dense, best-tested
   file, and already has good comments explaining *why* — turning those into types makes
   the "why" enforced, not just documented) gives the best return.

---

## 7. Test coverage is real but narrow — business logic in `.vue` files is untested

The existing tests are genuinely good: `fishWindows.test.ts`, `weatherForecast.test.ts`,
`weatherRates.test.ts`, `nodeGroups.test.ts`, `localIcons.test.ts`, `leafletIcon.test.ts`,
`mapAsset.test.ts` — 7 files, all covering the hardest, most bug-prone logic (the time/weather
engine) against real data rather than toy fixtures. That's the right instinct.

But `@vue/test-utils` is installed (`package.json:30`) and **zero** `.vue` components have
tests. That means:
- The tracking round-trip (`changeTracked`, `restoreTrackedState`, localStorage
  persistence — `src/App.vue:576-615`) is untested.
- The filter/pagination logic in every page component (§5) is untested — and is exactly the
  kind of logic (array slicing, opt-out set math) that's cheap to unit test and easy to get
  off-by-one wrong.
- The known-bad `recalcTimerCountdowns` (§4) has no regression test, so a future "fix" could
  silently reintroduce either bug.

**What a professional team would do:** once §6's typing and §5's composable extraction
happen, the filter/pagination and tracking logic moves out of `.vue` files into plain
functions/composables — which are far cheaper to test than mounting components. Prioritize
testing *that* over adding `@vue/test-utils` mount tests for every page.

---

## 8. `App.vue` is a ~740-line God Component mixing two Vue styles

*(Was ~790 lines at the time of the initial pass; trimmed to ~740 as a side effect of §4's
cleanup — the God Component problem itself is unchanged, just slightly smaller.)*

`App.vue` uses the Options API (`data()`, `methods: {}}`) while every page under `router/`
uses `<script setup>` composition API. Both are valid Vue, but having both in one small
codebase means a new contributor has to learn two idioms to understand data flow, and
`App.vue`'s ~30 methods can't be unit tested or reused outside the component (Options API
methods aren't plain functions) — which is exactly the gap §7 flags for tracking/filter
logic that currently lives there.

This is the root cause behind several other findings, not a separate bug: because all state
and all loading logic live in one Options-API component, there's no natural seam to load
data per-route (§1) or to unit-test the tracking logic (§7).

**What a professional team would do:** incrementally extract `App.vue`'s responsibilities
into composables under `src/hooks/` — a `useFfxivData()` for loading/normalizing, a
`useTracking()` for the tracked-nodes/localStorage logic, a `useEorzeaClock()` for the
clock/timer tick. `App.vue` itself shrinks to a `<script setup>` shell that wires them
together and renders the layout. This is the same pattern `useNow()` in `hooks.ts` already
demonstrates working well (`src/hooks/hooks.ts:14-33`) — it just hasn't been applied to the
rest of App.vue's state yet.

---

## 9. Custom image caching in `FetchVistaImage.vue` duplicates the browser and leaks memory

`src/modules/FetchVistaImage.vue:11-45` manually fetches vista images via `axios` as blobs,
stores them in a hand-rolled `caches.open('ffxivmap_vistas')` bucket, and sets
`background-image: url(createObjectURL(blob))` on a plain `<div>`.

Problems with this approach:
- `URL.createObjectURL()` results are never revoked (`URL.revokeObjectURL`), so every vista
  viewed in a session leaks its blob URL for the page's lifetime.
- It reimplements what `Cache-Control` headers on the S3 objects + a native `<img>` tag
  would give for free, correctly, with far less code — the browser's HTTP cache already
  does conditional revalidation, doesn't need custom bucket management, and isn't defeated
  by ad blockers the way an XHR-style fetch to a third-party domain sometimes is.
- Using a `<div>` background-image instead of `<img>` drops `alt` text (an accessibility
  regression relative to the rest of the app, which is otherwise careful about this — see
  the skip link and `aria-label`s in `2_TimedMiningBotany.vue`) and loses native lazy
  loading (`loading="lazy"`) and responsive `srcset` for free.

**What a professional team would do:** set `Cache-Control: public, max-age=31536000,
immutable` on the S3 vista objects (they're static, filename-addressed, never mutated in
place), and replace the whole component with `<img :src="imageUrl" loading="lazy"
decoding="async" :alt="...">`. That's a net deletion of most of this file's logic.

---

## 10. No per-route SEO metadata

`src/main.ts:43-46` sets `document.title` per route via `router.afterEach`, but nothing
updates the meta description, canonical URL, or Open Graph tags — those are all hardcoded
once in `index.html` for the whole site (`index.html:20-34`). Given the site carries Google
Analytics and AdSense (`index.html:8-18`), it's presumably relying at least partly on
organic search traffic, and distinct pages like "Weather Patterns" or "Blue Mage Abilities"
currently all share one generic description in search results.

**What a professional team would do:** each route already has a `meta.title`
(`src/main.ts:27-38`) — extend that to `meta.description` and update `<meta
name="description">` / `og:description` in the same `router.afterEach` hook, or adopt a
small head-management library (`@unhead/vue`) if per-route `<head>` needs grow beyond a
couple of tags.

---

## Suggested order of attack

These are independent enough to tackle in almost any order, but if picking a sequence:

1. ~~**CI first** (§2)~~ — ✅ done.
2. ~~**Route-scoped data loading** (§1)~~ — ◐ quick-fix scope done (static pages unblocked);
   the full per-route dataset redesign is still open.
3. ~~**Retire the legacy countdown path** (§4)~~ — ✅ done.
4. **Extract the filter/pagination composable** (§5) — deletes more duplicated code, makes
   §7's testing gap easy to close.
5. **Asset cleanup** (§3) — no code risk, just needs confirmation before deleting.
6. **Typing pass on `hooks.ts` and the data shapes** (§6) — biggest effort, biggest
   long-term payoff; do this once the surface area above has already shrunk.
7. **Vista image component simplification** (§9) and **per-route SEO** (§10) — smaller,
   do whenever convenient.
