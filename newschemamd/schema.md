# FFXIV Radar — Database Schema

Designed in DBML on dbdiagram.io, to run on Postgres. Source data: `FFXIVRadar_ImportReadyData.xlsx`, one sheet per table.

```dbml
// LOCATIONS

Table expansions { 
  id                   varchar      [pk]
  default_order        int          [not null, unique]
  name                 varchar      [not null, unique]
  vista_exp            int          [not null]
  vista_level_min      int          [not null]
  vista_level_max      int          [not null]
  version              varchar      [not null]
  active               boolean      [not null]
}

Table regions {
  id             varchar        [pk]
  default_order  int            [not null, unique]
  name           varchar        [not null, unique]
  region_icon    varchar        [not null, default: 'aetheryte']
}

Table zones {
  id             varchar        [pk]
  default_order  int            [not null, unique]
  expansion_id   varchar        [not null]
  region_id      varchar        [not null]
  name           varchar        [not null, unique]
  mapcode        varchar        [not null]
  mapsize        decimal(3,1)   [not null]
  type           varchar        [not null, default: 'world']
  has_subarea    boolean        [not null, default: false]
  connected_to   varchar
}

Table subareas {
  id              varchar        [pk]
  default_order   int            [not null, unique]
  zone_id         varchar        [not null]
  name            varchar        [not null, unique]
}

Ref: expansions.id < zones.expansion_id [update: cascade, delete: restrict]
Ref: regions.id < zones.region_id [update: cascade, delete: restrict]
Ref: zones.id < zones.connected_to [update: cascade, delete: restrict]
Ref: zones.id < subareas.zone_id [update: cascade, delete: restrict]

// TIMERS

Table timers {
  id                varchar         [pk]
  start_set         "int[]"         [not null]
  end_set           "int[]"         [not null]
}

Ref: timers.id < gathering_items.timer_id [update: cascade, delete: restrict]
Ref: timers.id < fishing_items.timer_id [update: cascade, delete: restrict]
Ref: timers.id < vistas.timer_id [update: cascade, delete: restrict]

// AETHERIALS

Table aetherials {
  id                varchar         [pk]
  default_order     int             [not null, unique]
  expansion_id      varchar         [not null]
  name              varchar         [not null, unique]
  primary_extract   varchar
  secondary_extract "varchar[]"
}

Ref: expansions.id < aetherials.expansion_id [update: cascade, delete: restrict]
Ref: aetherials.id < gathering_items.aetherial_id [update: cascade, delete: restrict]
Ref: aetherials.id < fishing_items.aetherial_id [update: cascade, delete: restrict]

// TOMES

Table tomes {
  id            varchar       [pk]
  default_order int           [not null, unique]
  name          varchar       [not null, unique]
  job_type      job_main      [not null]
  expansion_id  varchar       [not null]
  level         int
  cost          int
  cost_type     varchar 
}

Ref: tomes.id < gathering_items.tome_id [update: cascade, delete: restrict]
Ref: tomes.id < fishing_items.tome_id [update: cascade, delete: restrict]
Ref: expansions.id < tomes.expansion_id [update: cascade, delete: restrict]

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

Table gathering_nodes {
  id                varchar        [pk]
  default_order     int            [not null, unique]
  expansion_id      varchar        [not null]
  zone_id           varchar        [not null]
  node_area         varchar        [not null]
  node_type         varchar        [not null, default: 'Regular']
  node_level        int            [not null]
  x                 decimal(3,1)   [not null, default: 00.0]
  y                 decimal(3,1)   [not null, default: 00.0]
  job_sub           job_sub        [not null]
}

Ref: expansions.id < gathering_nodes.expansion_id [update: cascade, delete: restrict]
Ref: zones.id < gathering_nodes.zone_id [update: cascade, delete: restrict]

Table gathering_items {
  id                  varchar        [pk]
  default_order       int            [not null, unique]
  group_order         int            [not null]
  expansion_id        varchar        [not null]
  category            varchar        [not null]
  name                varchar        [not null]
  gathering_node_id   varchar        [not null]
  is_shard            boolean        [not null, default: false]
  attribute           varchar
  usage               varchar
  usage_info          text
  timer_id            varchar
  tome_id             varchar
  aetherial_id        varchar
  perception          int
  level               int            [not null]
  stars               int            [not null, default: 0]
}

Ref: gathering_nodes.id < gathering_items.gathering_node_id [update: cascade, delete: restrict]
Ref: expansions.id < gathering_items.expansion_id [update: cascade, delete: restrict]

Table fishing_nodes {
  id                varchar        [pk]
  default_order     int            [not null, unique]
  expansion_id      varchar        [not null]
  zone_id           varchar        [not null]
  node_area         varchar        [not null]
  node_level        int            [not null]
  x                 decimal(3,1)   [not null, default: 00.0]
  y                 decimal(3,1)   [not null, default: 00.0]
  job_sub           job_sub        [not null]
}

Ref: expansions.id < fishing_nodes.expansion_id [update: cascade, delete: restrict]
Ref: zones.id < fishing_nodes.zone_id [update: cascade, delete: restrict]

Table fishing_items {
  id                varchar        [pk]
  default_order     int            [not null, unique]
  expansion_id      varchar        [not null]
  fishing_node_id   varchar        [not null]
  timer_id          varchar
  tome_id           varchar
  aetherial_id      varchar
  name              varchar        [not null] 
  level             int            [not null]
  stars             int            [not null, default: 0]
  bait              varchar
  tug               int
  hookset           varchar
  mooch             "varchar[]"
  weather           "varchar[]"
  weather_chain     "varchar[]" 
  notes             text
}

Ref: expansions.id < fishing_items.expansion_id [update: cascade, delete: restrict]
Ref: fishing_nodes.id < fishing_items.fishing_node_id [update: cascade, delete: restrict]

// VISTAS

Enum vista_type {
  any
  jumppuzzle
  mount
  underwater
}

Table vistas {
  id                varchar         [pk]
  default_order     int             [not null, unique]
  group_order       int             [not null]
  expansion_id      varchar         [not null]
  zone_id           varchar         [not null]
  subarea_id        varchar
  timer_id          varchar
  emote             varchar         [not null]
  type              vista_type      [not null, default: 'any']
  name              varchar         [not null, unique]
  x                 decimal(3,1)
  y                 decimal(3,1)
  notes             varchar         [not null]
  weather           "varchar[]"
}

Ref: expansions.id < vistas.expansion_id [update: cascade, delete: restrict]
Ref: zones.id < vistas.zone_id [update: cascade, delete: restrict]
Ref: subareas.id < vistas.subarea_id [update: cascade, delete: restrict]
```
