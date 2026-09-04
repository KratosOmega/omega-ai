---
name: 2d-sprite-pipeline
description: Use when setting up or repairing 2D sprite import in Godot 4.x — pixels-per-unit, filtering, atlases, and animation import.
---

# 2D Sprite Pipeline

Decide these before importing the first asset, and record the decision in the
repository:

1. **Base resolution and stretch mode.** Set `display/window/size/viewport_width`
   and `height` to the design resolution. Use stretch mode `canvas_items` with
   aspect `keep` for most 2D games; use `viewport` for strict pixel art.
2. **Pixels per unit.** One value for the project. All art is authored to it.
3. **Filtering.** For pixel art, set the project default texture filter to
   Nearest (`rendering/textures/canvas_textures/default_texture_filter`), and
   never override it per-sprite without a written reason.
4. **Atlases.** Group by draw order and lifetime. UI, characters, and level
   tiles get separate atlases so one does not stall the other.
5. **Animation.** Import sprite sheets as `AtlasTexture` regions or use
   `SpriteFrames`. Keep frame rate a property of the animation resource, not of
   code.

When an asset does not fit these rules, change the rules deliberately and update
the record. Do not add a per-asset exception.
