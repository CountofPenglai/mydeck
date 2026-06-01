# Battle Example Guide

This project now has a complete prototype battle example as the main scene:

- Scene: `res://scenes/battle_scene.tscn`
- Scenario: `res://resources/battle/sample_battle_scenario.tres`
- Map: `res://resources/battle/sample_battle_map.tres`
- Config: `res://resources/battle/sample_battle_config.tres`

## Flow

1. Run the project or open `battle_scene.tscn`.
2. Deployment phase starts first.
3. Select each player unit in the sidebar, then click inside the blue deployment area.
4. Click `开始战斗` once all player units are deployed.
5. During player turns:
   - Click the map to move, spending AP based on distance.
   - Click a card, then click an enemy target to play it.
   - Click `普通攻击`, then click an enemy target for a basic attack.
   - Click `结束回合` to convert remaining AP into card draw.

## Example Units

- `阿兰`: melee warrior with sword/shield art.
- `莉娜`: ranged elven ranger with bow art.
- `近战训练敌`: melee state-machine enemy.
- `远程训练敌`: ranged state-machine enemy that tries to maintain preferred distance.

## Generated Art

Project art assets are under `assets/art/`:

- `assets/art/battlefields/ruined_keep_courtyard.png`
- `assets/art/cards/scroll_card_background.png`
- `assets/art/portraits/warrior_alan_portrait.png`
- `assets/art/portraits/ranger_lina_portrait.png`
- `assets/art/portraits/melee_marauder_portrait.png`
- `assets/art/portraits/ranged_cultist_portrait.png`
- `assets/art/battle_units/warrior_alan_battle.png`
- `assets/art/battle_units/ranger_lina_battle.png`
- `assets/art/battle_units/melee_marauder_battle.png`
- `assets/art/battle_units/ranged_cultist_battle.png`

Style target: hardcore Western fantasy, DND-inspired, hand-painted, with scroll-like parchment for cards.
