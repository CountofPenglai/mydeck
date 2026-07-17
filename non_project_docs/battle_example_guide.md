# Battle Example Guide

This project includes a complete prototype battle example. The project main scene is now the adventure map; the battle scene remains directly runnable for diagnostics and iteration:

- Main scene: `res://scenes/adventure_map_scene.tscn`
- Scene: `res://scenes/battle_scene.tscn`
- Scenario: `res://resources/battle/sample_battle_scenario.tres`
- Map: `res://resources/battle/sample_battle_map.tres`
- Config: `res://resources/battle/sample_battle_config.tres`

## Flow

1. Run the project to enter the adventure map, or open `battle_scene.tscn` to test combat directly.
2. A direct battle starts in the deployment phase.
3. Select each player unit in the sidebar, then click a highlighted deployment hex.
4. Click `开始战斗` once all player units are deployed.
5. During player turns:
   - Click `移动`, then select a highlighted hex. AP cost uses the path's integer movement cost.
   - Click a card, then click an enemy target to play it.
   - Click `普通攻击`, then click an enemy target for a basic attack.
   - Click `结束回合` to convert remaining AP into card draw.

## Example Units

- `阿兰`: warrior with switchable weapons, momentum cards, armor, and healing.
- `莉娜`: ranger with paired melee/ranged weapons, stealth, combo, and elements.
- `米拉`: druid with a mana zone, transformation, dual-orientation cards, and form-linked weapons.
- `近战训练敌`: melee state-machine enemy.
- `远程训练敌`: ranged state-machine enemy that tries to maintain preferred distance.

The sample battlefield uses a `12x9` hex grid. Fire, water, earth, and air sample cells are configured in `sample_battle_map.tres`.

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
