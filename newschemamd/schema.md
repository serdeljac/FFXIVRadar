# FFXIV Radar — Database Schema (in progress)

**Status:** locations, gathering, fishing, tomes, vistas, aetherytes and timers drafted as of
2026-10-12. Fishing can't be imported yet, tomes have no source sheet yet, and the vista and timer
data still need fixing (see Open items). Weather rates and the other datasets are still to come. The
schema is designed in DBML on dbdiagram.io and will run on Postgres. Source data:
`FFXIVRadarData.xlsx` at the repo root, one sheet per dataset.

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
| **Sightseeing is stored as `vistas`**; `group_order` is a vista's number within its expansion's log | The sheet's `set` column is dropped: for ARR, set 1 is #1–20 and set 2 is #21–80, which the number already shows. |
| **An aetheryte's name comes from the sheet's `area` column** and doesn't link to the `areas` table | Aetheryte names (Summerfold Farms, Moraby Drydocks, Wineport, …) aren't area names; only 37 of the 107 happen to match one. |
| **Aetheryte `point` stays as text** | It's only used in a special case (3 of the 107 aetherytes). |
| **Timers stay as they are for now** | The timer data will be fixed later. |

---

## Current schema (DBML)

```dbml
// LOCATIONS

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

Ref: expansions.id     < zones.expansion_id        [update: cascade, delete: restrict]
Ref: regions.id        < zones.region_id           [update: cascade, delete: restrict]
Ref: zones.id          < areas.zone_id             [update: cascade, delete: restrict]
Ref: areas.id          < points.area_id            [update: cascade, delete: restrict]


// GATHERING & FISHING

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
  timer_id       varchar        [not null, default: "None"]
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
  timer_id          varchar        [not null, default: "None"]
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
  name          varchar       [not null, unique]
  default_order int           [not null, unique]
  job           job_main      [not null]
  level         int
  cost          int
  cost_type     varchar
}

Ref: tomes.id          < gathering.tome_id         [update: cascade, delete: restrict]
Ref: tomes.id          < fishing.tome_id           [update: cascade, delete: restrict]
Ref: expansions.id     < tomes.expansion_id        [update: cascade, delete: restrict]

// VISTAS

Enum vista_type {
  any
  jumppuzzle
  mount
  underwater
}

Table vistas {
  id                varchar         [pk]
  expansion_id      varchar         [not null]
  zone_id           varchar         [not null]
  timer_id          varchar         [not null, default: "None"]
  default_order     int             [not null, unique]
  group_order       int             [not null]
  type              vista_type      [not null, default: "any"]
  name              varchar         [not null]
  weather           "varchar[]"
  emote             varchar         [not null]
  point             varchar
  notes             varchar
  node_code         varchar
  x                 decimal(3,1)
  y                 decimal(3,1)
}

Ref: expansions.id     < vistas.expansion_id       [update: cascade, delete: restrict]
Ref: zones.id          < vistas.zone_id            [update: cascade, delete: restrict]

// AETHERYTE

Table aetheryte {
  id                varchar         [pk]
  zone_id           varchar         [not null]
  default_order     int             [not null, unique]
  node_code         varchar
  point             varchar
  x                 decimal(3,1)
  y                 decimal(3,1)
}

Ref: zones.id          < aetheryte.zone_id         [update: cascade, delete: restrict]

// TIMER

Table timer {
  id                varchar         [pk]
  default_order     int             [not null, unique]
  active_sets       int             [not null, default: 1]
  start_set_1       int             [not null]
  end_set_1         int             [not null]
  start_set_2       int
  end_set_2         int
  start_set_3       int
  end_set_3         int
}

Ref: timer.id          < gathering.timer_id        [update: cascade, delete: restrict]
Ref: timer.id          < fishing.timer_id          [update: cascade, delete: restrict]
Ref: timer.id          < vistas.timer_id           [update: cascade, delete: restrict]
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
| `tomb` | `tome_id` | Convert the tome name to its ID. Blank in 1,279 rows. The column header is misspelled; the values are right ("Tome of …"). |
| `time` | `timer_id` | Points to the `timer` sheet. Blank in 880 rows. |
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
| `time` | `timer_id` | Points to the `timer` sheet. Blank in 2,512 rows. |
| `bait`, `tug`, `hookset` | same names | Blank in all 368 spearfishing rows. `bait` may be `mooch` (see Decisions). |
| `mooch_name1`–`3` | `mooch` | In order. Every value is a fish name in the sheet. |
| `weather1`–`3` | `weather` | In order. 22 weather names, spelled consistently. |
| `weatherchain1`–`3` | `weather_chain` | In order. |
| `node_code` | `node_code` | A formula built from the location name; one code per location. |
| — | `tome_id` | The sheet has no tome column yet. |

### `tomes` → `tomes`

No sheet yet; a tomes CSV is planned. The 24 gathering tome names are in the gathering sheet's `tomb`
column. `expansion_id`, `level`, `cost` and `cost_type` will come from the new CSV.

### `sightseeing` sheet → `vistas`

340 rows. The vista data still needs additions and fixes (see Open items).

| Sheet column | Table column | Notes |
|---|---|---|
| `ID`, `name`, `emote`, `notes`, `node_code`, `x`, `y` | same names | |
| `order` | `default_order` | |
| `expansion` | `expansion_id` | Convert the name to the expansion's ID. Always the same as the zone's expansion. |
| `zone` | `zone_id` | Every value matches a zone. |
| `time` | `timer_id` | Points to the `timer` sheet. Blank in 258 rows. |
| `no` | `group_order` | The vista's number within its expansion's log (ARR 1–80, Heavensward 1–62, …). |
| `type` | `type` | Blank in 305 rows → `'any'`. Two rows spell it `jump puzzle` (see Open items). |
| `weather1`–`2` | `weather` | In order. 13 weather names, all also used in fishing. |
| `point` | `point` | Text. Filled in 6 rows. |
| `set` | — | Dropped (see Decisions). |
| `mount` | — | Not mapped yet (see Open items). |
| `transx`, `transy` | — | Dropped, as in gathering. |

### `aetheryte` sheet → `aetheryte`

107 rows.

| Sheet column | Table column | Notes |
|---|---|---|
| `ID`, `node_code`, `x`, `y` | same names | |
| `no` | `default_order` | |
| `zone` | `zone_id` | Every value matches a zone. |
| `area` | `name` | The aetheryte's name. Not a link to `areas`. The table needs a `name` column (see Open items). |
| `point` | `point` | Text, for a special case. Filled in 3 rows. |
| `transx`, `transy` | — | Dropped, as in gathering. |

### `timer` sheet → `timer`

135 rows. Kept as is for now; the data will be fixed later.

| Sheet column | Table column | Notes |
|---|---|---|
| `ID` (`timer1`…`timer135`) | `id`, `default_order` | The number gives the order. |
| `sets` | `active_sets` | 1, 2 or 3. |
| `start0`/`end0`, `start1`/`end1`, `start2`/`end2` | `start_set_1`/`end_set_1`, `…_2`, `…_3` | The sheet counts windows from 0, the table from 1. Hours 0–24. |

---

## Import rules

- **Blank cells load as NULL, never as empty text.** `perception` is blank in 1,345 rows, and `''`
  isn't a number. For `timer_id` and `tome_id`, the schema currently uses a `"None"` default instead
  (see Open items).
- **A default only applies when the column is left out of the insert.** An empty string counts as a
  value. So write `'world'` for blank `zones.type` and `'any'` for blank `vistas.type`.
- **0/1 columns are booleans:** `issubarea` → `is_subarea`, `isshard` → `is_shard`.
- **Expansion names become expansion IDs** for zones, gathering, fishing and vistas.
- **Array columns are built from their numbered columns in order** (`mooch_name1`–`3` → `mooch`, and
  so on). The sheets never fill a later slot while an earlier one is empty.
- **Unused timer windows load as NULL.** The timer sheet fills them with 0–0, but 0 is a real hour
  (midnight). Every window beyond `sets` is exactly 0–0, and no window in use starts and ends at the
  same hour.

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

- **`"None"` defaults on `timer_id` and `tome_id`:** all three `timer_id` columns and both `tome_id`
  columns are `not null` with the default `"None"`. Every row without a timer or tome then needs a
  row with the ID "None" in `timer` or `tomes`, or the import rejects it. That's 880 gathering,
  2,512 fishing and 258 vista rows without a timer, and 1,279 gathering rows (plus all fishing rows
  for now) without a tome. A "None" timer row would also need a window 1 (`start_set_1`/`end_set_1`
  are `not null`), which the countdown would treat as real. The alternative is nullable columns,
  where NULL means none, which is how blank times were first decided. Text defaults also need
  single quotes: `'None'`.
- **Node table:** holds the node type (`node_name`) as its category and the node's level
  (`node_level`).
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
- **Tomes:** source data comes from a tomes CSV, still to be created. The fishing sheet has no tome
  data yet.
- **Vistas:**
  - The data needs additions and fixes.
  - `type`: two rows spell it `jump puzzle` (`sightsee262` Radz-at-Han, `sightsee299` Tuliyollal);
    the enum only accepts `jumppuzzle`. The default needs single quotes: `'any'`.
  - A unique pair `(expansion_id, group_order)` would stop two vistas in one expansion getting the
    same number. The current data never repeats one.
  - The sheet's `mount` column (0/1, set on 146 rows) isn't mapped. It isn't the same as type
    `mount`, which is 26 rows.
- **Aetheryte:** the table needs a `name` column for the sheet's `area` values.
- **Timers (data to fix later):** 29 timers wrap past midnight (e.g. `timer35` 18 → 2), so there's no
  start-before-end rule. `active_sets` repeats what the filled windows already show. Three pairs
  are identical (`timer34`/`timer99`, `timer35`/`timer103`, `timer36`/`timer105`), and 3 timers
  aren't used by any sheet.
- **Table names:** `timer` and `aetheryte` are singular; the other tables are plural.
- **Remaining datasets:** weather rates (fishing and vista weather link to them later), aether
  currents, Blue Mage, hunts and hunt points, FATEs, aetherial reduction. Then names and
  translations, item page URLs, and user tables (see the end of `architecture.md`).
