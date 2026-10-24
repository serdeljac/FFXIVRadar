# Workbook fixes and suggestions

`FFXIVRadar_ImportReadyData.xlsx` checked against [schema.md](schema.md) on 2026-10-23.

## Fixes

1. **timers:** rename `start_sets` → `start_set` and `end_sets` → `end_set` to match the schema.
2. **expansions:** `version` for `sbs` (Shadowbringers) is 6.58. It should probably be 5.58.
3. **expansions:** format the `version` column as Text. All 7 are numbers, so `ecd` shows 8 instead of 8.00.
4. **subareas:** delete the 405 empty rows under the data.

## Suggestions

1. **vistas:** add a unique pair `(expansion_id, group_order)` so two vistas in one expansion can't share a number. The data has no repeats now.
2. **timers:** 5 timers aren't used by anything. Delete them or keep them for later:
   `timer/1/4/5/0/0/0/0`, `timer/1/5/6/0/0/0/0`, `timer/1/15/16/0/0/0/0`, `timer/1/20/6/0/0/0/0`, `timer/1/12/6/0/0/0/0`
3. **fishing_nodes:** 2 nodes have no fish: `fnode-north-isle-of-endless-summer`, `fnode-fool-falls`. Add fish or remove them.
4. **Import:** load the `zones` sheet all at once. Five zones' `connected_to` points to a zone further down the sheet, so importing row by row fails.
5. **Old tables:** the previous schema had `aetheryte`, `elite_hunts` and `elite_hunt_points`. Add them back if you still want them.
