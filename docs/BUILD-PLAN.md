# FFXIV Radar — Build Plan

Reference plan for the official FFXIV Radar build, engineered from the ground up. It replaces the test
build in the `FFXIVRadarv2` repo, a static Vue app that read 14 JSON files. This build
moves the data into SQL behind an API and adds user accounts.

_Last updated: 2026-11-06_

---

## Decisions

| Area | Decision | Notes |
|---|---|---|
| Hosting | **Hostinger VPS** | One box runs the API, the database and the static frontend. |
| Database | **MySQL 8** | Docker locally; native or Docker on the VPS. |
| Game data | **SQL tables from the dbdiagram schema** | Schema is still in progress. Its structure differs from the v2 JSON. |
| Login | **Optional accounts** | Every page stays public. Signing in syncs tracked nodes, filters and preferences. |
| Sign-in methods | **Email + password, Discord, Google** | |
| Repository | **`serdeljac/FFXIVRadar`** | Official build. `FFXIVRadarv2` is the test build and stays as reference. |

## Stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | Vue 3 + TypeScript + Vite + **Pinia** + vue-router | Same framework as v2; Pinia stores replace v2's `App.vue` as the data owner. |
| Maps | Leaflet | Already used by the Eorzea Overview page. |
| API | Node (current LTS) + **Hono** | Small, fast, TypeScript-first. |
| ORM | **Drizzle** | Typed schema, migrations, parameterized queries only. |
| Auth | **Better Auth** | Self-hosted; email/password + OAuth; stores users and sessions in our MySQL. |
| Validation | Zod | Validates every request body and query string at the API boundary. |
| Tests | Vitest (unit), Playwright (end-to-end, later) | |
| Tooling | npm workspaces, ESLint, Prettier, GitHub Actions | TypeScript stays on 6.x (`vue-tsc` does not support 7 yet). |

## Repository layout

```
FFXIVRadar/
├─ apps/
│  ├─ web/            Vue frontend
│  └─ api/            Hono API + Better Auth
├─ packages/
│  ├─ core/           Eorzea time & weather window engine (shared by web + api)
│  └─ db/             Drizzle schema, migrations, seed/import scripts
├─ docker-compose.yml MySQL (+ Mailpit for local email)
├─ .env.example       every variable, no real values
└─ .github/workflows/ CI + deploy
```

---

## Phases

Phases 1–4 do **not** depend on the game-data schema and can start now.

### Phase 1 — Foundation
- [ ] Monorepo with npm workspaces; shared `tsconfig`, ESLint, Prettier.
- [ ] `docker-compose.yml` with MySQL 8 and Mailpit (catches outgoing email locally).
- [ ] `.env.example` covering DB, auth secret, OAuth client IDs/secrets, SMTP, app URL.
- [ ] Hono API skeleton: `/health`, error handler that logs without leaking secrets, CORS, security headers.
- [ ] Vue app skeleton with router, Pinia, and the v2 SCSS variables/theme.
- [ ] CI: lint, typecheck, test, build on every push and PR.

**Done when:** `docker compose up` + `npm run dev` serves the web app and `/health` returns ok; CI is green.

### Phase 2 — Core engine (`packages/core`)
Port `src/hooks/hooks.ts`, `src/modules/weatherForecast.ts` and `src/modules/weatherRates.ts` from the `FFXIVRadarv2` repo, with their tests.

- [ ] Eorzea clock (1 ET day = 70 real minutes; 1 ET minute = 175/60 s).
- [ ] Weather windows (1,400,000 ms, anchored to the unix epoch).
- [ ] `timerWindows`, `activeRunEnd`, `nextSpawnAt`, with caching.
- [ ] Fishing weather transitions (previous window → current window).
- [ ] Endwalker/Dawntrail weather rate tables.
- [ ] Remove the dependency on the node *shape*: the engine takes plain inputs (zone, time ranges, weather lists) so it works with the new schema.

**Done when:** all v2 window/weather tests pass against the ported code.

### Phase 3 — Accounts & login
- [ ] Better Auth wired to MySQL through Drizzle (it creates `user`, `session`, `account`, `verification`).
- [ ] Email + password: argon2 hashing, email verification, password reset.
- [ ] Discord and Google OAuth.
- [ ] Rate limiting on sign-in, sign-up and reset endpoints.
- [ ] HttpOnly, Secure, SameSite cookies; CSRF protection.
- [ ] Login screen, sign-up, forgot/reset password, account settings (change password, link/unlink providers, delete account).
- [ ] Unit tests for auth flows; manual check of each OAuth provider.

**Done when:** a user can sign up, verify, sign in with each method, reset a password and delete their account.

### Phase 4 — User data
- [ ] `user_preferences` (theme, default filters, timezone, etc.).
- [ ] `user_tracked_nodes` — stores node keys as strings (e.g. `fishing:fish0001`) until the game tables exist, then gains a foreign key.
- [ ] API: `GET/PUT /me/preferences`, `GET/POST/DELETE /me/tracked`.
- [ ] Guests keep using `localStorage`; on first sign-in the local list is merged into the account.

**Done when:** tracking a node on one device shows up on another after signing in.

### Phase 5 — Game data _(blocked on the dbdiagram schema)_
- [ ] Translate the DBML into the Drizzle schema + migrations.
- [ ] Import script: v2 JSON → new tables. Produce a report of every v2 field that doesn't map cleanly.
- [ ] Read-only API routes per dataset, with filtering and pagination; HTTP caching headers.
- [ ] Item icons and map art enriched from xivapi, cached server-side.

**Done when:** every v2 dataset is in SQL and the import report has no unresolved fields.

### Phase 6 — Pages
Rebuild in this order (simplest first, map last):

1. [ ] App shell: sidebar, tracking bar, details pane, search, shared clock (`useNow`).
2. [ ] Timed Mining & Botany
3. [ ] Timed Fishing
4. [ ] Sightseeing Vistas
5. [ ] Weather Patterns
6. [ ] Aether Currents
7. [ ] Blue Mage Abilities
8. [ ] Home, News, About (Lodestone scrape), Privacy Policy, 404
9. [ ] Eorzea Overview (Leaflet map)

Carry over the accessibility fixes from `UI-UX-AUDIT.md` in `FFXIVRadarv2` (keyboard access, ARIA, reduced motion).

### Phase 7 — Deploy
- [ ] VPS: Nginx (static files + reverse proxy to the API), PM2, HTTPS via Let's Encrypt, firewall.
- [ ] MySQL user with least privilege; nightly backups copied off the box.
- [ ] GitHub Actions deploy on push to `main` (build → upload → migrate → restart).
- [ ] Production OAuth redirect URLs and SMTP (Hostinger mail or Resend).
- [ ] Error and uptime monitoring.
- [ ] DNS cutover from Vercel once everything is confirmed working.

---

## Lessons from v2 to keep

These caused real bugs in v2 and should be designed out, not repeated:

- **ET minute conversion:** one ET minute is `175/60` seconds, not 3. The legacy `timerList` countdown used 3 and ran ~2.9% long.
- **Timers crossing midnight:** 29 of 135 timers (e.g. 18 → 2) wrap. Store or expand them as non-wrapping intervals.
- **One shared clock:** all countdowns read one app-wide timestamp, or the same node shows different times in different places.
- **Weather lookup by zone, not `mapcode`:** sub-areas and all Endwalker/Dawntrail areas had no mapcode. The new schema should link every area to a zone with a weather table.
- **Known data gaps:** 7 fishing areas (Diadem cloudtops, Open Sirensong Sea) have no zone in v2; some weather names never occur in their zone. Flag these in the import report.
- **Incomplete icon set:** missing icons should render a placeholder, not break layout.

## Security checklist

- No credentials in code; all secrets come from environment variables; `.env` is git-ignored.
- All SQL goes through Drizzle (parameterized); no string-built queries.
- Validate and sanitize every input with Zod.
- Logs never include passwords, tokens, cookies or full emails.
- Rate limiting on auth routes; secure cookie flags; HTTPS only in production.

## Open questions

- [ ] dbdiagram schema — share the DBML export when complete.
- [ ] Email provider for verification/reset (Hostinger SMTP or Resend).
- [ ] Keep AdSense and analytics? (v2 used Vercel Analytics, which won't apply on the VPS.)
- [ ] Admin area for editing game data and news — now or later?
