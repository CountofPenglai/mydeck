# Art Asset Manifest

Generated with Codex built-in image generation on 2026-06-01.

Style target: hardcore Western fantasy, DND-inspired, hand-painted concept art. Card background uses aged scroll/parchment texture with leather and metal trim.

See `non_project_docs/art_style_guide.md` for the durable style rules.

## Assets

- `enemies/chapter_two_monsters.svg`
  - 12-panel compact atlas for Chapter 2 military units, aberrations, bosses, and the Triumph Statue.
  - Each panel is `128x128`; `ChapterTwoEnemyCatalog` slices it with `AtlasTexture`.

- `battlefields/ruined_keep_courtyard.png`
  - Top-down-ish 2D no-grid ruined keep courtyard battlefield, open center, grim Western fantasy hand-painted style.
- `cards/scroll_card_background.png`
  - Blank ornate parchment scroll card face, leather and iron trim, no text.
- `portraits/warrior_alan_portrait.png`
  - 1024x1536 portrait of Alan, rugged human warrior in scratched steel armor and worn red cloak.
- `portraits/ranger_lina_portrait.png`
  - 1024x1536 portrait of Lina, hooded elven ranger in practical leather armor.
- `portraits/melee_marauder_portrait.png`
  - 1024x1536 portrait of a brutal melee marauder.
- `portraits/ranged_cultist_portrait.png`
  - 1024x1536 portrait of a sinister ranged cultist marksman.
- `battle_units/warrior_alan_battle.png`
  - 1024x1024 semi-top-down battle unit image of Alan.
- `battle_units/ranger_lina_battle.png`
  - 1024x1024 semi-top-down battle unit image of Lina.
- `battle_units/melee_marauder_battle.png`
  - 1024x1024 semi-top-down battle unit image of the melee marauder.
- `battle_units/ranged_cultist_battle.png`
  - 1024x1024 semi-top-down battle unit image of the ranged cultist; regenerated once to correct bowstring anatomy.
- `ui/discard_button.png`
  - 256x256 discard pile UI button matching the existing stone, leather, parchment, and brass-trim battle HUD style.
- `ui/ap_orb_full.png`
  - 128x128 transparent green AP orb used to mark available AP inside the existing empty AP slot frame.
- `ui/battle_hud/bottom_wood_panel.png`
  - Wide worn-oak, black-iron, and brass HUD backing used by the responsive battle bottom panel.
- `ui/battle_hud/panel_frame.png`
  - General dark leather and iron frame used for compact battle tools such as deployment.
- `ui/battle_hud/detail_frame.png`
  - Portrait parchment and black-iron frame used by the unified battle detail inspector.
- `ui/battle_hud/turn_order_rail.png`
  - Wide iron, leather, and brass rail behind the locked-round action order.
- `ui/battle_hud/command_icons.png`
  - Transparent three-command strip for move, attack, and end-turn controls.
- `ui/battle_hud/current_unit_ring.png`
  - Transparent amber portrait ring for the current acting unit.
- `ui/battle_hud/turn_ally_frame.png`
  - Transparent emerald allied turn-order portrait frame.
- `ui/battle_hud/turn_enemy_frame.png`
  - Transparent crimson enemy turn-order portrait frame.
- `ui/battle_hud/*_raw.png`
  - Chroma-key generation sources retained for the command strip and portrait frames.
- `cards/monster_card_basic.svg`
  - Compact dark teal prototype artwork shared by the eight basic monster cards.
- `cards/monster_card_mutation.svg`
  - Crimson-violet prototype artwork shared by the eight mutation cards.
- `cards/temporary_jinx.svg`
  - Prototype curse artwork for temporary monster-generated jinx cards.
- `enemies/chapter_one_monsters.svg`
  - Ten-cell 128px badge atlas for the Chapter One monster roster; used by both battle tokens and the compact inspect panel.

Raw generated sources for the normalized portrait/battle assets are kept beside the final files with `_raw` suffix.

## Source Location

Original generated files were left in the default Codex generated image directory:

`C:\Users\G5 GD\.codex\generated_images\019e71aa-b729-7b70-845d-f95144a6f0c9`

The 2026-07-31 battle HUD source generations are stored in:

`C:\Users\G5 GD\.codex\generated_images\019f3b55-7444-7040-b579-7d643adc524b`
