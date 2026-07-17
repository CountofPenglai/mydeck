# Battle Scene Prototype Guide

Battle scenes are now data-driven through `BattleScenePrototype`.

## Core Resource

Example:

`res://resources/battle/prototypes/scene_001_ruined_keep.tres`

Fields:

- `scene_id`: scene number / identifier, such as `BATTLE-001`.
- `difficulty`: display-only difficulty value. It does not modify stats.
- `scene_texture`: battlefield artwork used as the map background.
- `map_data`: map dimensions, deployment zone, enemy spawn zone, and actual boundary polygon.
- `enemy_configs`: enemy state + count list.
- `global_effects`: scene-wide effect interfaces. Current sample uses a no-op placeholder.

## Hex Map

`BattleMapData` is the authoritative source for the battle grid. Current maps use pointy-top offset hex cells and integer `Vector2i` coordinates.

Important fields:

- `grid_columns` / `grid_rows`: valid cell dimensions.
- `hex_size`: visual radius of each hex.
- `grid_origin`: map-space position of cell `(0, 0)`.
- `player_deployment_columns`: deployment columns on the left.
- `enemy_spawn_columns`: spawn columns on the right.
- `element_cells`: configured base-element cells.

`map_size` remains the visual canvas size. It is not the movement boundary. Cell validity, distance, lines and ranges are derived through `BattleHexGrid` and `BattleMapData`.

## Initialization Flow

`BattleScenario` may still keep direct `map_data` and `enemies`, but initialization prefers:

- `scenario.scene_prototype.map_data`
- `scenario.scene_prototype.enemy_configs`
- `scenario.scene_prototype.global_effects`

This keeps old resources usable while making new battle scenes prototype-driven.

## Global Effects

`BattleGlobalEffect` is the extension point for scene-wide rules:

- `on_battle_setup(context)`
- `on_turn_start(context)`
- `on_turn_end(context)`

The context includes `controller`, `scenario`, `scene_prototype`, and the current `unit` when relevant.
