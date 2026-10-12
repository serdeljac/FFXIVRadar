# FFXIV Radar — Database Schema (in progress)

**Status:** locations, gathering, fishing and tomes drafted as of 2026-10-12. Fishing can't be
imported yet, and tomes have no source sheet yet (see Open items). Timers, weather and the other
datasets are still to come. The schema is designed in DBML on dbdiagram.io and will run on Postgres.
Source data: `FFXIVRadarData.xlsx` at the repo root, one sheet per dataset.

---

## Conventions

- Every primary key is named `id`.
- Every column that links to another table is named `<thing>_id` (`zone_id`, `area_id`).
- A table that only links two others uses those two columns together as its key, with no `id`.
- `default_order` is the display order and is unique within its table.
- **IDs can still change for now.** Sheet IDs (`fish0001`, `mine1`, …) may be renumbered while the
  data is being cleaned up. Nothing should rely on them until they're declared fixed.

---

## Decisions

| Decision | Why |
|---|---|
| Location chain is **expansion → zone**, **region → zone → area → point** | A zone has exactly one region and one expansion. |
| **Expansion sits on zones, not regions** | Coerthas spans two expansions: Coerthas Central Highlands is ARR, Coerthas Western Highlands and Foundation are Heavensward. |
| **`regionicon` sits on zones, not regions** | It varies within three regions: Norvrandt (The Crystarium, Eulmore), Ilsabard (Garlemald) and Xak Tural (Shaaloani). |
| **Gathering links to an area** (`area_id`), not a zone or point | The sheet named an area in most rows and a point in 369. Those were changed to the point's parent area, so every row resolves and the schema stays simple. |
| **`gathering.expansion_id` is independent of the location** | It's the expansion that added the item to the game, which isn't always the zone's expansion. |
| **`level` is the item's level** | The node's level (`node_level`) belongs to the node table, planned for later. |
| **`category` holds the sheet's `group` column** (log / folklore / collect) | The node type (Regular / Unspoiled / Ephemeral / Legendary) becomes the node table's category, planned for later. |
| **`job_main` enum values are `miner`, `botany`, `fishing`** | They match the spreadsheet. `job_sub` keeps `mining` for the miner's sub-job. |
| **Fishing `bait` keeps the value `mooch`** (287 rows) | It stands for the in-game Mooch command, so it's real data, not a missing bait. Leave as is for now. |
| **Folklore tomes get their own `tomes` table**; gathering and fishing link to it with `tome_id` | The site will search for a tome and list its contents. One tome has many items, and the link sits on each gathering/fishing row (Stonehard Water and Potent Spice are in two tomes at different nodes). The game spells it "tome", so the sheet's `tomb` column maps to `tome_id`. |
| **A tome has one expansion** | Every tome's items share a single expansion. |

---

## Current schema (DBML)

```dbml
//LOCATIONS

Table expansions {
  id                   varchar  [pk]
  name                 varchar  [not null, unique]
  default_order        int      [not null, unique]
  vista_exp            int      [not null]
  vista_level_min      int      [not null]
  vista_level_max      int      [not null]
}

Table zones {
  id             varchar        [pk]
  expansion_id   varchar        [not null]
  region_id      varchar        [not null]
  name           varchar        [not null, unique]
  default_order  int            [not null, unique]
  mapcode        varchar        [not null]
  mapsize        decimal(3,1)   [not null]
  is_subarea     boolean        [not null, default: false]
  type           varchar        [not null, default: 'world']
  regionicon     varchar        [default: 'aetheryte']
}

Table regions {
  id             varchar        [pk]
  name           varchar        [not null, unique]
  default_order  int            [not null, unique]
}

Table areas {
  id              varchar        [pk]
  zone_id         varchar        [not null]
  name            varchar        [not null]
  default_order   int            [not null, unique]
}

Table points {
  id              varchar        [pk]
  area_id         varchar        [not null]
  name            varchar        [not null]
  default_order   int            [not null, unique]
}

Ref: expansions.id     < zones.expansion_id    [update: cascade, delete: restrict]
Ref: regions.id        < zones.region_id       [update: cascade, delete: restrict]
Ref: zones.id          < areas.zone_id         [update: cascade, delete: restrict]
Ref: areas.id          < points.area_id        [update: cascade, delete: restrict]


//GATHERING & FISHING

Enum job_main {
  miner
  botany
  fishing
}

Enum job_sub {
  mining
  quarrying
  logging
  harvesting
  fishing
  spearfishing
}

Table gathering {
  id             varchar        [pk]
  expansion_id   varchar        [not null]
  area_id        varchar        [not null]
  timer_id       varchar
  tome_id        varchar        [not null, default: "None"]
  name           varchar        [not null]
  default_order  int            [not null, unique]
  job            job_main       [not null]
  job_sub        job_sub        [not null]
  category       varchar
  is_shard       boolean        [not null, default: false]
  usage          varchar
  usage_info     text
  perception     int
  stars          int
  level          int            [not null]
  x              decimal(3,1)
  y              decimal(3,1)
}

Ref: expansions.id     < gathering.expansion_id    [update: cascade, delete: restrict]
Ref: areas.id          < gathering.area_id         [update: cascade, delete: restrict]

Table fishing {
  id                varchar        [pk]
  expansion_id      varchar        [not null]
  point_id          varchar        [not null]
  timer_id          varchar
  tome_id           varchar        [not null, default: "None"]
  name              varchar        [not null]
  default_order     int            [not null, unique]
  job               job_main       [not null]
  job_sub           job_sub        [not null]
  bait              varchar
  tug               int
  hookset           varchar
  mooch             "varchar[]"
  weather           "varchar[]"
  weather_chain     "varchar[]"
  notes             text
  node_code         varchar
  level             int            [not null]
  stars             int            [not null, default: 0]
  x                 decimal(3,1)
  y                 decimal(3,1)
}

Ref: points.id         < fishing.point_id          [update: cascade, delete: restrict]
Ref: expansions.id     < fishing.expansion_id      [update: cascade, delete: restrict]

Table tomes {
  id            varchar       [pk]
  expansion_id  varchar       [not null]
  name          varchar       [not null]
  level         int
  cost          int
  cost_type     varchar
}

Ref: tomes.id          < gathering.tome_id         [update: cascade, delete: restrict]
Ref: tomes.id          < fishing.tome_id           [update: cascade, delete: restrict]
Ref: expansions.id     < tomes.expansion_id        [update: cascade, delete: restrict]
```

---

## Spreadsheet → table mapping

### `expansions` sheet → `expansions`

| Sheet column | Table column | Notes |
|---|---|---|
| `ID` (`expa1`…`expa6`) | `default_order` | The number gives the order. |
| `expansion` | `name` | |
| `icon` (`arr`, `hwd`, …) | — | No column yet (see Open items). |
| `vista_exp`, `vista_min`, `vista_max` | `vista_exp`, `vista_level_min`, `vista_level_max` | |

### `areas` sheet → `regions`, `zones`, `areas`, `points`

One sheet row is one point. Regions, zones and areas are the distinct values of their columns.

| Sheet column | Table column | Notes |
|---|---|---|
| `ID` (`area1`…`area935`) | `points.id` | Named "area" in the sheet, but each one identifies a point. |
| `no` | `points.default_order` | Regions, zones and areas take their order from where they first appear. |
| `region` | `regions.name` | 18 regions. IDs to be created. |
| `zone` | `zones.name` | 72 zones. IDs to be created. |
| `expansion` | `zones.expansion_id` | Convert the name to the expansion's ID. |
| `regionicon`, `mapcode`, `mapsize` | same names on `zones` | |
| `issubarea` | `zones.is_subarea` | 0/1 → false/true. |
| `type` | `zones.type` | Blank → `'world'` (see Import rules). |
| `area` | `areas.name` | 393 areas. IDs to be created. |
| `point` | `points.name` | Not unique: "The Hedgetree" appears in 3 areas. |
| `inoverview`, `variant` | — | Dropped on purpose. |

### `gathering` sheet → `gathering`

The sheet merges the old `miner` and `botany` sheets: 1,399 rows, one per item at a node.

| Sheet column | Table column | Notes |
|---|---|---|
| `ID` | `id` | |
| `order` | `default_order` | 1–1,399. |
| `job`, `job_sub` | `job`, `job_sub` | |
| `group` | `category` | log / folklore / collect. |
| `name` | `name` | |
| `isshard` | `is_shard` | 0/1 → false/true. |
| `expansion` | `expansion_id` | Convert the name to the expansion's ID. |
| `area` | `area_id` | Every value matches an area in the `areas` sheet. |
| `usage`, `usage_info`, `perception`, `stars`, `x`, `y` | same names | |
| `tomb` | `tome_id` | Convert the tome name to its ID. Blank means no tome (1,279 rows). The column header is misspelled; the values are right ("Tome of …"). |
| `time` | `timer_id` | Points to the `timer` sheet. Blank means no timer. |
| `level` | `level` | The item's level, 1–100. |
| `node_name`, `node_level` | — | Moving to the node table (later). |
| `node_code`, `transx`, `transy`, `attribute` | — | Dropped on purpose. |
| `no` | — | Not discussed yet. |

### `fishing` sheet → `fishing`

2,873 rows, one per fish at a location (fishing and spearfishing).

| Sheet column | Table column | Notes |
|---|---|---|
| `ID`, `order`, `job`, `job_sub`, `name`, `level`, `stars`, `x`, `y`, `notes` | same names (`order` → `default_order`) | |
| `expansion` | `expansion_id` | Convert the name to the expansion's ID. |
| `area` | `point_id` | Must match a point in the `areas` sheet. 1,054 rows don't yet (see Open items). |
| `time` | `timer_id` | Points to the `timer` sheet. Blank means no timer. |
| `bait`, `tug`, `hookset` | same names | Blank in all 368 spearfishing rows. `bait` may be `mooch` (see Decisions). |
| `mooch_name1`–`3` | `mooch` | In order. Every value is a fish name in the sheet. |
| `weather1`–`3` | `weather` | In order. 22 weather names, spelled consistently. |
| `weatherchain1`–`3` | `weather_chain` | In order. |
| `node_code` | `node_code` | A formula built from the location name; one code per location. |
| — | `tome_id` | The sheet has no tome column yet. |

### `tomes` → `tomes`

No sheet yet; a tomes CSV is planned. The 24 gathering tome names are in the gathering sheet's `tomb`
column. `expansion_id`, `level`, `cost` and `cost_type` will come from the new CSV.

---

## Import rules

- **Blank cells load as NULL, never as empty text.** `timer_id` is blank in 880 rows, and `''` would
  fail the link to timers. `perception` is blank in 1,345 rows, and `''` isn't a number.
- **`zones.type`: write `'world'` for blanks.** A default only applies when the column is left out
  of the insert. An empty string counts as a value.
- **0/1 columns are booleans:** `issubarea` → `is_subarea`, `isshard` → `is_shard`.
- **Expansion names become expansion IDs** for zones, gathering and fishing.
- **Array columns are built from their numbered columns in order** (`mooch_name1`–`3` → `mooch`, and
  so on). The sheet never fills a later slot while an earlier one is empty.

---

## Data fixes made in the workbook

| Date | Change |
|---|---|
| 2026-10-11 | 369 gathering rows that named a point now name that point's parent area (e.g. Ahm Nohl → Ostrakon Deka-okto). |
| 2026-10-11 | `miner` and `botany` sheets merged into one `gathering` sheet. |
| 2026-10-11 | Gathering `order` renumbered 1–1,399. The old sheets reused 338–341. |
| 2026-10-11 | `level` typos fixed on `logg246` and `logg247` (were 922). |
| 2026-10-11 | Stray asterisks removed from three fishing locations: The Adventure, The Kobayashi Maru, and Kobayashi Maru's Northern Wake (spelled as the game does). 19 rows; their `node_code` formulas recalculated. |
| 2026-10-11 | Leading space removed from the point `Saibai Cavern` (`area415`) in the areas sheet. |
| 2026-10-11 | Fishing: blank `stars` set to 0 (129 rows); Silver Shark (`fish0148`) mooch `Fullmoon` + `Sardine` merged into `Fullmoon Sardine`; Catkiller's (`fish0998`) catching instructions moved from mooch to `notes`; bait `Leech (Bait)` / `Dragonfly (Bait)` renamed `Leech` / `Dragonfly` to match the game. |
| 2026-10-11 | Fishing: added Grade 2 Skybuilders' Cloud Cutter at Blustery Cloudtop as `fish2804`. The rows after it were renumbered `fish2805`–`fish2873`. |
| 2026-10-11 | Fishing rows whose location isn't a point in the areas sheet are highlighted: **light red** = matches nothing (714 rows), **light yellow** = matches an area but not a point (340 rows). |
| 2026-10-11 | Fishing: Silver Shark at Costa del Sol (`fish0158`) has its mooch fish `Fullmoon Sardine` back. A note about the highlight colours was added to the workbook. |
| 2026-10-12 | Gathering: the 5 items in *Tome of Botanical Folklore - Norvrandt* marked Stormblood (`logg294`–`logg298`) set to Shadowbringers, so every tome has one expansion. |

---

## Open items

- **Node table:** holds the node type (`node_name`) as its category and the node's level
  (`node_level`).
- **Timers table:** the target of `gathering.timer_id`. The `timer` sheet has 135 timers with up to
  3 windows each. Some windows wrap past midnight (e.g. 18 → 2), so the end can be smaller than the
  start.
- **Expansion icon codes** (`arr`, `hwd`, `sbd`, `sbs`, `ewr`, `dtl`): no column yet. One option is
  to use them as `expansions.id`.
- **IDs:** the tables use text IDs, and they can still change (see Conventions). `architecture.md`
  says to key game data by the game's own IDs, which isn't settled for these tables yet.
- **Fishing locations (blocks the import):** `point_id` is required, but 1,054 rows have no matching
  point. They're highlighted in the sheet. 44 location names are areas rather than points (yellow).
  101 aren't in the areas sheet at all (red): sub-spots like the Loch Seld lakebeds, ocean fishing,
  the Diadem and the Cloudtops. Also, 6 names are a point in two areas of the same zone (Yedlihmad,
  Giantsgall Grounds, The Wakeful Torana, Pavana's Remorse, The Wellspring of Regret, Lethe), so a
  name lookup can't pick one.
- **Fishing data to check:**
  - 18 rows in The Lavender Beds and The Goblet have x or y = 0, which should probably load as NULL.
  - 63 of the 70 Diadem and Cloudtop rows have no bait, tug or hookset.
- **Fishing schema choices:** whether rows with no mooch or weather get NULL or an empty array
  `{}`; whether to keep `node_code`, which describes the location rather than the fish.
- **Tomes:**
  - `tome_id` is `not null` with default `"None"` on gathering and fishing. As written, every row
    without a tome (1,279 gathering rows, all fishing rows for now) fails the link unless a tome
    with the ID "None" exists. The alternative is a nullable `tome_id`, where NULL means no tome,
    as with `timer_id`. Text defaults also need single quotes once exported to SQL.
  - Source data: a tomes CSV, still to be created. The fishing sheet has no tome data yet.
  - Possible additions: `unique` on `name`, a `default_order` for the search list, and a `job`
    column for filtering.
- **Remaining datasets:** weather rates (fishing weather links to them later), sightseeing, aether
  currents, Blue Mage, hunts, FATEs, aetherytes. Then names and translations, item page URLs, and
  user tables (see the end of `architecture.md`).
