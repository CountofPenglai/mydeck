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

## Map Boundary

`BattleMapData.boundary_points` stores the actual playable edge as a polygon coordinate list.

Example:

```gdscript
PackedVector2Array(28, 54, 862, 45, 890, 570, 38, 584)
```

The battle controller uses this polygon for movement/deployment validation. If no polygon is configured, it falls back to the rectangular `map_size`.

## Initialization Flow

`BattleScenario` may still keep legacy `map_data` and `enemies`, but initialization now prefers:

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
