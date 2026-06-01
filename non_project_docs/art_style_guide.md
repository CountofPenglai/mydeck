# Art Style Guide

This document defines the current visual style for the project art pipeline.

## Core Direction

- Genre: hardcore Western fantasy, DND-inspired, grounded and dangerous.
- Medium: hand-painted oil-and-ink concept art with visible painterly texture.
- Mood: grim heroic fantasy, worn equipment, harsh travel, old ruins, low comfort.
- Avoid: cute stylization, anime gloss, clean high-fantasy sparkle, modern objects, bright toy-like colors, UI text baked into images, logos, watermarks.

## Palette

- Dominant colors: iron gray, charcoal black, weathered leather brown, aged parchment tan, umber, ash gray.
- Accent colors: oxblood red for warriors/marauders, deep forest green for ranger, sickly green for occult enemies, muted brass/iron trim.
- Lighting should feel torchlit, moonlit, overcast, or candlelit. Avoid clean studio lighting except for deliberately neutral portrait readability.

## Materials

- Metal: scratched steel, blackened iron, tarnished brass, rust and nicks.
- Cloth: torn cloak edges, rough wool, weathered tabards, dirty hems.
- Leather: worn straps, scuffed armor panels, survival gear.
- Paper/card UI: aged parchment, scroll texture, leather binding, hammered metal corners.
- Environment: cracked stone, moss, soot, ruined keep masonry, scorched ground.

## Asset Categories

### Portraits

- Purpose: character sheet, enemy preview, large UI panels.
- Required size: `1024x1536`.
- Composition: waist-up or upper-body portrait, centered, generous padding.
- Camera: front or three-quarter portrait view.
- Background: dark neutral parchment/dungeon/forest backdrop with subtle smoky vignette.
- Must not include: battle token inset, full-body inset, UI frame, text, watermark.

### Battle Units

- Purpose: map token / combat representation.
- Required size: `1024x1024`.
- Composition: full-body figure, semi-top-down three-quarter view, centered.
- Camera: readable isometric/miniature style, head-to-boots visible.
- Grounding: simple dark stone or mossy floor patch is allowed.
- Must not include: close-up portrait framing, circular inset, UI frame, text, watermark.
- Weapon anatomy must be plausible. For bows, use one continuous bowstring attached to both bow tips, with arrows correctly nocked.

### Card Backgrounds

- Purpose: reusable card face background.
- Preferred shape: portrait card ratio.
- Style: aged scroll/parchment panel with leather and iron trim.
- Must leave clean areas for artwork, title, and rules text.
- Must not include: baked text, specific faction symbols unless requested.

### Battlefields

- Purpose: 2D no-grid tactical battle background.
- Composition: top-down or semi-top-down with an open readable combat area.
- Style: ruined Western fantasy locations, hand-painted, no grid baked into the image.
- Must not include: characters, UI, text, watermark.

## Current Asset Dimensions

- Portrait finals: `assets/art/portraits/*_portrait.png`, `1024x1536`.
- Battle unit finals: `assets/art/battle_units/*_battle.png`, `1024x1024`.
- Raw generated sources are preserved with `_raw.png` suffix.

## Prompt Template

Use this as the base for future portrait or battle-unit generations:

```text
Use case: stylized-concept
Asset type: <portrait or battle unit image>, Godot RPG tactical card game
Primary request: <subject>, for a DND-style hardcore Western fantasy game
Scene/backdrop: <dark neutral parchment backdrop OR simple dark stone floor patch>
Subject: <specific character/equipment/silhouette>
Style/medium: hardcore Western fantasy, DND-inspired, hand-painted oil-and-ink concept art, gritty realistic proportions, painterly brush texture
Composition/framing: <portrait: waist-up centered / battle: square semi-top-down full-body centered>
Lighting/mood: <torchlight/moonlight/overcast>, grim heroic or hostile mood
Color palette: <role-specific muted palette>
Materials/textures: worn leather, scratched steel, torn cloth, aged wood, cracked stone
Constraints: no text, no logo, no watermark, no modern objects, no UI frame
```
