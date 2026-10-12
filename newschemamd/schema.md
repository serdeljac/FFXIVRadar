# FFXIV Radar — Database Schema (in progress)

**Status:** locations and gathering items drafted as of 2026-10-11. Fishing, timers, weather and the
other datasets are still to come. The schema is designed in DBML on dbdiagram.io and will run on
Postgres. Source data: `FFXIVRadarData.xlsx` at the repo root, one sheet per dataset.

---

## Conventions

- Every primary key is named `id`.
- Every column that links to another table is named `<thing>_id` (`zone_id`, `area_id`).
- A table that only links two others uses those two columns together as its key, with no `id`.
- `default_order` is the display order and is unique within its table.

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
  timer_id       varchar
  expansion_id   varchar        [not null]
  area_id        varchar        [not null]
  name           varchar        [not null]
  default_order  int            [not null, unique]
  job            job_main       [not null]
  job_sub        job_sub        [not null]
  category       varchar
  is_shard       boolean        [not null, default: false]
  usage          varchar
  usage_info     text
  tomb           varchar
  perception     int
  stars          int
  level          int            [not null]
  x              decimal(3,1)
  y              decimal(3,1)
}

Ref: expansions.id     < gathering.expansion_id    [update: cascade, delete: restrict]
Ref: areas.id          < gathering.area_id         [update: cascade, delete: restrict]
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
| `usage`, `usage_info`, `tomb`, `perception`, `stars`, `x`, `y` | same names | |
| `time` | `timer_id` | Points to the `timer` sheet. Blank means no timer. |
| `level` | `level` | The item's level, 1–100. |
| `node_name`, `node_level` | — | Moving to the node table (later). |
| `node_code`, `transx`, `transy`, `attribute` | — | Dropped on purpose. |
| `no` | — | Not discussed yet. |

---

## Import rules

- **Blank cells load as NULL, never as empty text.** `timer_id` is blank in 880 rows, and `''` would
  fail the link to timers. `perception` is blank in 1,345 rows, and `''` isn't a number.
- **`zones.type`: write `'world'` for blanks.** A default only applies when the column is left out
  of the insert. An empty string counts as a value.
- **0/1 columns are booleans:** `issubarea` → `is_subarea`, `isshard` → `is_shard`.
- **Expansion names become expansion IDs**, for zones and gathering alike.

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

---

## Open items

- **Node table:** holds the node type (`node_name`) as its category and the node's level
  (`node_level`).
- **Timers table:** the target of `gathering.timer_id`. The `timer` sheet has 135 timers with up to
  3 windows each. Some windows wrap past midnight (e.g. 18 → 2), so the end can be smaller than the
  start.
- **Expansion icon codes** (`arr`, `hwd`, `sbd`, `sbs`, `ewr`, `dtl`): no column yet. One option is
  to use them as `expansions.id`.
- **IDs:** the tables use text IDs. `architecture.md` says to key game data by the game's own IDs,
  which isn't settled for these tables yet.
- **Remaining datasets:** fishing (spots, bait, weather, mooch), weather rates, sightseeing, aether
  currents, Blue Mage, hunts, FATEs, aetherytes. Then names and translations, item page URLs, and
  user tables (see the end of `architecture.md`).
