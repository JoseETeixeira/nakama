# Design: Sprite Generation and Application

**Document Information**
- **Feature Name:** Sprite Generation and Application
- **Version:** 1.0
- **Date:** October 31, 2025
- **Author:** Kiro AI
- **Status:** Draft

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Sprite Asset Specifications](#sprite-asset-specifications)
4. [Asset Directory Structure](#asset-directory-structure)
5. [Sprite Generation Strategy](#sprite-generation-strategy)
6. [Godot Integration](#godot-integration)
7. [Scene Modifications](#scene-modifications)
8. [Data Models](#data-models)
9. [Performance Considerations](#performance-considerations)
10. [Testing Strategy](#testing-strategy)
11. [Implementation Phases](#implementation-phases)

---

## Overview

### Design Goals

This design addresses the transformation of the MMORPG Nakama Godot client from a functional prototype using placeholder ColorRect nodes to a visually polished 2D top-down game with proper sprite assets.

**Primary Objectives:**
- Generate pixel-art sprite assets for all entity types, projectiles, and UI elements
- Integrate sprites into existing Godot scenes with minimal script changes
- Maintain 60+ FPS performance with 100+ simultaneous sprite entities
- Establish reusable asset pipeline for future content additions

**Design Principles:**
- **Visual Consistency:** Unified 16-color palette, consistent pixel-art style
- **Performance First:** Optimize for batching, use sprite atlases where beneficial
- **Maintainability:** Clear naming conventions, organized directory structure
- **Backward Compatibility:** Preserve existing node names and script references

### Traceability to Requirements

| Requirement | Design Section |
|-------------|----------------|
| Req 1: Player Entity Sprites | §3.1, §6.1, §7.1 |
| Req 2: NPC Differentiation | §3.2, §6.2, §7.2 |
| Req 3: Projectile Visuals | §3.3, §6.3, §7.3 |
| Req 4: UI Icons | §3.4, §6.4, §7.4 |
| Req 5: Loot Containers | §3.5, §6.5, §7.5 |
| Req 6: Godot Integration | §4, §5, §6 |
| NFR: Performance | §9 |
| NFR: Visual Quality | §3, §5.3 |

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Godot Client Runtime                     │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │ Scene Trees   │  │ WorldState   │  │  UI Manager     │  │
│  │ (Entity Nodes)│◄─┤ Autoload     │  │  Autoload       │  │
│  └───────┬───────┘  └──────────────┘  └────────┬────────┘  │
│          │                                      │           │
│  ┌───────▼────────────────────────────────────▼────────┐   │
│  │         Sprite2D / AnimatedSprite2D Nodes          │   │
│  │    (render TextureRect / SpriteFrames)             │   │
│  └────────────────────────┬───────────────────────────┘   │
│                           │                                │
└───────────────────────────┼────────────────────────────────┘
                            │
                ┌───────────▼────────────┐
                │  Godot Import System   │
                │  (.import files)       │
                └───────────┬────────────┘
                            │
                ┌───────────▼────────────┐
                │  Asset Storage Layer   │
                │  (PNG sprite files)    │
                └────────────────────────┘
```

**Key Components:**

1. **Asset Storage Layer**
   - Location: `godot_project/assets/sprites/`
   - Format: PNG with transparency
   - Organization: Subdirectories by asset category

2. **Godot Import System**
   - Generates `.import` files for each PNG
   - Configuration: 2D Pixel preset, nearest-neighbor filtering
   - Output: `CompressedTexture2D` resources in `.godot/imported/`

3. **Scene Node Layer**
   - Replaces ColorRect nodes with Sprite2D/AnimatedSprite2D
   - References texture resources via `res://` paths
   - Maintains existing node names for script compatibility

4. **Runtime Rendering**
   - Godot's 2D renderer batches draw calls by texture
   - Camera2D controls viewport, zoom settings
   - CanvasLayer for UI elements (HUD, panels)

---

## Sprite Asset Specifications

### 3.1 Player Character Sprites (Requirement 1)

**Resolution:** 32x32 pixels  
**Animation Frames:** 8 total (4 directions × 2 states)  
**States:** Idle, Walking  
**Directions:** Up, Down, Left, Right

**Frame Layout:**
```
player_idle_up.png      (32x32)
player_idle_down.png    (32x32)
player_idle_left.png    (32x32)
player_idle_right.png   (32x32)
player_walk_up.png      (32x32, 2-frame animation)
player_walk_down.png    (32x32, 2-frame animation)
player_walk_left.png    (32x32, 2-frame animation)
player_walk_right.png   (32x32, 2-frame animation)
```

**Visual Design Guidelines:**
- Humanoid character silhouette (head, torso, legs visible)
- Base color: Blue (#3399ff) to match existing ColorRect modulation
- Clear directional indicators (face direction, hair/cape flow)
- Transparent background
- 2-frame walk cycle: feet apart → feet together

**SpriteFrames Configuration:**
- Animation "idle_up": [player_idle_up.png]
- Animation "idle_down": [player_idle_down.png]
- Animation "idle_left": [player_idle_left.png]
- Animation "idle_right": [player_idle_right.png]
- Animation "walk_up": [player_walk_up_0.png, player_walk_up_1.png] @ 8 FPS
- Animation "walk_down": [player_walk_down_0.png, player_walk_down_1.png] @ 8 FPS
- Animation "walk_left": [player_walk_left_0.png, player_walk_left_1.png] @ 8 FPS
- Animation "walk_right": [player_walk_right_0.png, player_walk_right_1.png] @ 8 FPS

### 3.2 NPC Sprites (Requirement 2)

**Resolution:** 32x32 pixels  
**Variants:** 3 base types + palette swaps

#### Vendor NPC
```
npc_vendor_idle.png (32x32)
```
- Visual: Rotund humanoid with merchant apron/pack
- Color: Gold/brown palette (#d4af37, #8b4513)
- Icon: Coin purse visible on sprite

#### Quest Giver NPC
```
npc_quest_idle.png (32x32)
```
- Visual: Robed figure with staff or book
- Color: Purple/blue palette (#9370db, #4169e1)
- Icon: Scroll or quest marker in hand

#### Hostile Mob (Base)
```
npc_hostile_slime.png (32x32)
npc_hostile_goblin.png (32x32)
npc_hostile_skeleton.png (32x32)
```
- Visual: Distinct enemy types (blob, humanoid, undead)
- Color: Red-tinted aggressive palette (#dc143c, #8b0000)
- Variations: Palette swaps for leveled versions

**Design Notes:**
- NPCs are static (idle-only, no walk animations initially)
- Server metadata `{type: "vendor"}` maps to `npc_vendor_idle.png`
- Hostile detection via metadata, not sprite filename

### 3.3 Projectile Sprites (Requirement 3)

**Resolution:** 16x16 pixels  
**Variants:** 3 types

```
projectile_fireball.png     (16x16, orange/red flame orb)
projectile_arrow.png        (16x16, wooden arrow with tip)
projectile_magic_missile.png (16x16, purple/blue energy bolt)
```

**Visual Design:**
- **Fireball:** Circular orange gradient (#ff4500 → #ff8c00) with yellow core
- **Arrow:** Brown shaft (#8b4513), gray tip (#808080), fletching visible
- **Magic Missile:** Elongated purple gradient (#9370db → #4b0082) with glow

**Rotation Handling:**
- Sprites designed facing right (0° reference)
- Godot rotates sprite via `rotation` property based on velocity vector
- Symmetric designs minimize rotation artifacts

### 3.4 UI Icon Sprites (Requirement 4)

**Resolutions:** Variable by purpose

#### Inventory Item Icons (24x24)
```
item_potion_health.png      (24x24, red vial)
item_potion_mana.png        (24x24, blue vial)
item_sword.png              (24x24, gray blade)
item_shield.png             (24x24, brown/metal shield)
item_armor.png              (24x24, chest plate)
item_gold.png               (24x24, gold coin stack)
item_key.png                (24x24, golden key)
item_scroll.png             (24x24, parchment)
item_gem.png                (24x24, red gemstone)
item_food.png               (24x24, bread/meat)
```

#### Ability Icons (32x32)
```
ability_fireball.png        (32x32, flame icon)
ability_heal.png            (32x32, green cross/heart)
ability_shield.png          (32x32, blue barrier)
ability_dash.png            (32x32, speed lines)
ability_stun.png            (32x32, yellow star burst)
```

#### Status Effect Icons (16x16)
```
status_poison.png           (16x16, green droplet)
status_burn.png             (16x16, red flame)
status_frozen.png           (16x16, blue snowflake)
status_blessed.png          (16x16, yellow halo)
```

#### Chat Channel Icons (12x12)
```
chat_guild.png              (12x12, green 'G')
chat_party.png              (12x12, blue 'P')
chat_system.png             (12x12, yellow '!')
chat_whisper.png            (12x12, purple 'W')
```

**Design Consistency:**
- All icons use same 16-color palette
- Clear symbolic representations (avoid detailed illustrations)
- High contrast borders for visibility against varied backgrounds

### 3.5 Loot Container Sprites (Requirement 5)

**Resolution:** 32x32 pixels  
**States:** 2 per container type

```
loot_chest_closed.png       (32x32, wooden chest, lid shut)
loot_chest_open.png         (32x32, wooden chest, lid open, empty interior visible)
loot_corpse.png             (32x32, tombstone or body outline)
```

**Rarity Variants (Palette Swaps):**
- Common: Brown wood (#8b4513)
- Rare: Blue-tinted (#4169e1 accents)
- Epic: Purple-tinted (#9370db accents)

**Interaction States:**
- Closed: Default spawn state
- Open: Displayed after loot collection
- Corpse: Single-state marker for defeated enemies

---

## Asset Directory Structure

```
godot_project/
└── assets/
    └── sprites/
        ├── entities/
        │   ├── player/
        │   │   ├── player_idle_up.png
        │   │   ├── player_idle_down.png
        │   │   ├── player_idle_left.png
        │   │   ├── player_idle_right.png
        │   │   ├── player_walk_up_0.png
        │   │   ├── player_walk_up_1.png
        │   │   ├── player_walk_down_0.png
        │   │   ├── player_walk_down_1.png
        │   │   ├── player_walk_left_0.png
        │   │   ├── player_walk_left_1.png
        │   │   ├── player_walk_right_0.png
        │   │   └── player_walk_right_1.png
        │   ├── npcs/
        │   │   ├── npc_vendor_idle.png
        │   │   ├── npc_quest_idle.png
        │   │   ├── npc_hostile_slime.png
        │   │   ├── npc_hostile_goblin.png
        │   │   └── npc_hostile_skeleton.png
        │   └── loot/
        │       ├── loot_chest_closed.png
        │       ├── loot_chest_open.png
        │       └── loot_corpse.png
        ├── vfx/
        │   ├── projectile_fireball.png
        │   ├── projectile_arrow.png
        │   └── projectile_magic_missile.png
        ├── ui/
        │   ├── items/
        │   │   ├── item_potion_health.png
        │   │   ├── item_potion_mana.png
        │   │   ├── item_sword.png
        │   │   ├── item_shield.png
        │   │   ├── item_armor.png
        │   │   ├── item_gold.png
        │   │   ├── item_key.png
        │   │   ├── item_scroll.png
        │   │   ├── item_gem.png
        │   │   └── item_food.png
        │   ├── abilities/
        │   │   ├── ability_fireball.png
        │   │   ├── ability_heal.png
        │   │   ├── ability_shield.png
        │   │   ├── ability_dash.png
        │   │   └── ability_stun.png
        │   ├── status/
        │   │   ├── status_poison.png
        │   │   ├── status_burn.png
        │   │   ├── status_frozen.png
        │   │   └── status_blessed.png
        │   └── chat/
        │       ├── chat_guild.png
        │       ├── chat_party.png
        │       ├── chat_system.png
        │       └── chat_whisper.png
        └── README.md (asset creation guidelines)
```

**Naming Convention:**
- Format: `<category>_<name>_<state>_<direction>.png`
- All lowercase, underscores for spaces
- Consistent ordering: category → specific → variant

---

## Sprite Generation Strategy

### 5.1 Generation Approach

**Tool Selection:**
Given constraints (no budget, open-source compatible, rapid generation), use:

**Primary Tool: AI Image Generation (Stable Diffusion / DALL-E)**
- Prompt engineering for pixel-art style
- Batch generation with consistent parameters
- Post-processing in GIMP/Aseprite for cleanup

**Fallback: Manual Pixel Art**
- Aseprite (open-source alternative: LibreSprite)
- 16-color palette enforcement
- Reusable templates for variations

### 5.2 Color Palette Definition

**16-Color Palette (PICO-8 Inspired):**
```
#000000 - Black (outlines, shadows)
#1d2b53 - Dark Blue (night sky, deep shadows)
#7e2553 - Dark Purple (magic effects, rare items)
#008751 - Dark Green (vegetation, poison)
#ab5236 - Brown (wood, earth)
#5f574f - Dark Gray (stone, metal)
#c2c3c7 - Light Gray (highlights, metal)
#fff1e8 - White (highlights, text)
#ff004d - Red (health, danger, fire)
#ffa300 - Orange (fire, warmth)
#ffec27 - Yellow (gold, light)
#00e436 - Green (health, nature)
#29adff - Light Blue (water, mana, player)
#83769c - Purple (magic, rare)
#ff77a8 - Pink (accents)
#ffccaa - Peach (skin tones)
```

**Application:**
- All sprites constrain to this palette
- Ensures visual consistency across assets
- Simplifies palette swaps for variations

### 5.3 Import Configuration Template

**Godot .import File Template:**
```ini
[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://[auto-generated]"
path="res://.godot/imported/[filename].png"

[deps]

source_file="res://assets/sprites/[path]/[filename].png"
dest_files=["res://.godot/imported/[filename].png"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
svg/scale=1.0
editor/scale_with_editor_scale=false
editor/convert_colors_with_editor_theme=false
```

**Critical Settings:**
- `compress/mode=0` - No compression (preserves pixels)
- `mipmaps/generate=false` - No mipmaps (pixel-art clarity)
- `detect_3d/compress_to=0` - Force 2D optimization
- `process/fix_alpha_border=true` - Clean transparency edges

**Godot Project Setting:**
```
[rendering]
textures/canvas_textures/default_texture_filter=0
```
- `0` = Nearest-neighbor filtering (global default)

---

## Godot Integration

### 6.1 PlayerEntity Scene Modifications

**Current Structure (PlayerEntity.tscn):**
```gdscript
[node name="PlayerEntity" type="CharacterBody2D"]
├── [node name="CollisionShape2D" type="CollisionShape2D"]
├── [node name="Sprite2D" type="Sprite2D"]  # Currently uses ColorRect child
│   └── [node name="ColorRect" type="ColorRect"]  # ← REMOVE
├── [node name="NameLabel" type="Label"]
├── [node name="HealthBar" type="ProgressBar"]
└── [node name="ManaBar" type="ProgressBar"]
```

**New Structure:**
```gdscript
[node name="PlayerEntity" type="CharacterBody2D"]
├── [node name="CollisionShape2D" type="CollisionShape2D"]
├── [node name="AnimatedSprite2D" type="AnimatedSprite2D"]  # ← REPLACE Sprite2D
│   # SpriteFrames resource with animations (idle/walk × 4 directions)
├── [node name="NameLabel" type="Label"]
├── [node name="HealthBar" type="ProgressBar"]
└── [node name="ManaBar" type="ProgressBar"]
```

**Scene File Changes:**
```diff
- [node name="Sprite2D" type="Sprite2D" parent="."]
- modulate = Color(0.2, 0.6, 1, 1)
- texture = null
- 
- [node name="ColorRect" type="ColorRect" parent="Sprite2D"]
- offset_left = -16.0
- offset_top = -16.0
- offset_right = 16.0
- offset_bottom = 16.0
- color = Color(0.2, 0.6, 1, 1)

+ [node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
+ sprite_frames = ExtResource("2_player_frames")  # SpriteFrames resource
+ animation = "idle_down"
+ offset = Vector2(0, 0)
```

**SpriteFrames Resource (player_frames.tres):**
```gdscript
[gd_resource type="SpriteFrames" load_steps=13 format=3]

[ext_resource type="Texture2D" path="res://assets/sprites/entities/player/player_idle_up.png" id="1"]
[ext_resource type="Texture2D" path="res://assets/sprites/entities/player/player_idle_down.png" id="2"]
# ... (load all 12 frames)

[resource]
animations = [{
"frames": [{
"duration": 1.0,
"texture": ExtResource("2")
}],
"loop": true,
"name": &"idle_down",
"speed": 5.0
}, {
"frames": [{
"duration": 1.0,
"texture": ExtResource("10")
}, {
"duration": 1.0,
"texture": ExtResource("11")
}],
"loop": true,
"name": &"walk_down",
"speed": 8.0
}]
# ... (8 animations total)
```

### 6.2 NPCEntity Scene Modifications

**Current Structure:**
```gdscript
[node name="NPCEntity" type="CharacterBody2D"]
├── [node name="CollisionShape2D"]
├── [node name="Sprite2D" type="ColorRect"]  # ← REPLACE with Sprite2D
├── [node name="NameLabel" type="Label"]
├── [node name="HealthBar" type="ProgressBar"]
├── [node name="VendorIcon" type="ColorRect"]  # Keep (overlay)
├── [node name="QuestIcon" type="ColorRect"]   # Keep (overlay)
└── [node name="AggroIcon" type="ColorRect"]   # Keep (overlay)
```

**New Structure:**
```gdscript
[node name="NPCEntity" type="CharacterBody2D"]
├── [node name="CollisionShape2D"]
├── [node name="Sprite2D" type="Sprite2D"]  # ← Dynamically assigned texture
├── [node name="NameLabel" type="Label"]
├── [node name="HealthBar" type="ProgressBar"]
├── [node name="VendorIcon" type="ColorRect"]  # Keep (overlay icons remain)
├── [node name="QuestIcon" type="ColorRect"]
└── [node name="AggroIcon" type="ColorRect"]
```

**NPCEntity.gd Script Changes:**
```gdscript
# Add sprite mapping dictionary
const NPC_SPRITES = {
	"vendor": preload("res://assets/sprites/entities/npcs/npc_vendor_idle.png"),
	"quest_giver": preload("res://assets/sprites/entities/npcs/npc_quest_idle.png"),
	"hostile_slime": preload("res://assets/sprites/entities/npcs/npc_hostile_slime.png"),
	"hostile_goblin": preload("res://assets/sprites/entities/npcs/npc_hostile_goblin.png"),
	"hostile_skeleton": preload("res://assets/sprites/entities/npcs/npc_hostile_skeleton.png"),
}

@onready var sprite: Sprite2D = $Sprite2D

func set_npc_type(npc_type: String) -> void:
	if NPC_SPRITES.has(npc_type):
		sprite.texture = NPC_SPRITES[npc_type]
	else:
		# Fallback to default hostile sprite
		sprite.texture = NPC_SPRITES["hostile_slime"]
```

### 6.3 AbilityProjectile Scene Modifications

**Current:**
```gdscript
[node name="Sprite" type="ColorRect" parent="."]
offset_left = -8.0
offset_top = -8.0
offset_right = 8.0
offset_bottom = 8.0
color = Color(1, 0.5, 0, 1)
```

**New:**
```gdscript
[node name="Sprite" type="Sprite2D" parent="."]
texture = null  # Set dynamically by script
centered = true
```

**AbilityProjectile.gd Script Changes:**
```gdscript
const PROJECTILE_SPRITES = {
	"fireball": preload("res://assets/sprites/vfx/projectile_fireball.png"),
	"arrow": preload("res://assets/sprites/vfx/projectile_arrow.png"),
	"magic_missile": preload("res://assets/sprites/vfx/projectile_magic_missile.png"),
}

@onready var sprite: Sprite2D = $Sprite

func setup(effect_type: String, start_pos: Vector2, target_pos: Vector2) -> void:
	position = start_pos
	
	# Set sprite based on effect type
	if PROJECTILE_SPRITES.has(effect_type):
		sprite.texture = PROJECTILE_SPRITES[effect_type]
	
	# Calculate rotation toward target
	var direction = (target_pos - start_pos).normalized()
	rotation = direction.angle()
	
	# ... (existing velocity/movement code)
```

### 6.4 UI Panel Sprite Integration

**InventoryPanel.gd - Item Icon Display:**
```gdscript
# Preload item icon atlas or individual icons
const ITEM_ICONS = {
	"potion_health": preload("res://assets/sprites/ui/items/item_potion_health.png"),
	"potion_mana": preload("res://assets/sprites/ui/items/item_potion_mana.png"),
	"sword": preload("res://assets/sprites/ui/items/item_sword.png"),
	# ... (all 10+ item types)
}

func create_item_slot(item_data: Dictionary) -> TextureRect:
	var slot = TextureRect.new()
	slot.custom_minimum_size = Vector2(24, 24)
	slot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	var item_type = item_data.get("type", "unknown")
	if ITEM_ICONS.has(item_type):
		slot.texture = ITEM_ICONS[item_type]
	
	return slot
```

**HUD.gd - Ability Bar Icons:**
```gdscript
const ABILITY_ICONS = {
	"fireball": preload("res://assets/sprites/ui/abilities/ability_fireball.png"),
	"heal": preload("res://assets/sprites/ui/abilities/ability_heal.png"),
	# ... (5-8 abilities)
}

func setup_ability_slot(ability_id: String, slot_index: int) -> void:
	var ability_button = get_node("AbilityBar/Slot" + str(slot_index))
	if ABILITY_ICONS.has(ability_id):
		ability_button.icon = ABILITY_ICONS[ability_id]
	ability_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
```

### 6.5 LootContainer Scene Modifications

**LootContainer.gd Script:**
```gdscript
const LOOT_SPRITES = {
	"chest_closed": preload("res://assets/sprites/entities/loot/loot_chest_closed.png"),
	"chest_open": preload("res://assets/sprites/entities/loot/loot_chest_open.png"),
	"corpse": preload("res://assets/sprites/entities/loot/loot_corpse.png"),
}

@onready var sprite: Sprite2D = $Sprite2D

var is_open: bool = false
var container_type: String = "chest"

func _ready() -> void:
	update_sprite()

func update_sprite() -> void:
	if container_type == "corpse":
		sprite.texture = LOOT_SPRITES["corpse"]
	else:
		if is_open:
			sprite.texture = LOOT_SPRITES["chest_open"]
		else:
			sprite.texture = LOOT_SPRITES["chest_closed"]

func open_container() -> void:
	is_open = true
	update_sprite()
```

---

## Scene Modifications

### 7.1 PlayerEntity.tscn Complete Update

**File:** `godot_project/scenes/world/entities/PlayerEntity.tscn`

**Changes:**
1. Remove `Sprite2D` node and `ColorRect` child
2. Add `AnimatedSprite2D` node with SpriteFrames resource reference
3. Create `player_frames.tres` SpriteFrames resource with 8 animations
4. Update `PlayerEntity.gd` to control animation playback

**Script Animation Control (PlayerEntity.gd):**
```gdscript
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var last_direction: Vector2 = Vector2.DOWN
var is_moving: bool = false

func _physics_process(delta: float) -> void:
	# ... (existing movement code)
	
	update_animation()

func update_animation() -> void:
	var current_velocity = velocity
	
	if current_velocity.length() > 10:
		is_moving = true
		last_direction = current_velocity.normalized()
	else:
		is_moving = false
	
	var anim_prefix = "walk" if is_moving else "idle"
	var anim_suffix = get_direction_suffix(last_direction)
	
	var anim_name = anim_prefix + "_" + anim_suffix
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)

func get_direction_suffix(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"
```

### 7.2 NPCEntity.tscn Update

**File:** `godot_project/scenes/world/entities/NPCEntity.tscn`

**Changes:**
1. Replace `ColorRect` node with `Sprite2D`
2. Remove inline color definition
3. Texture assigned dynamically by script based on metadata

**WorldState.gd Spawning Update:**
```gdscript
func spawn_npc(entity_id: String, entity_data: Dictionary) -> void:
	var npc_scene = preload("res://scenes/world/entities/NPCEntity.tscn")
	var npc = npc_scene.instantiate()
	
	npc.position = Vector2(entity_data.position.x, entity_data.position.y)
	npc.set_npc_type(entity_data.get("npc_type", "hostile_slime"))
	
	get_node("/root/Zone/Entities").add_child(npc)
	active_entities[entity_id] = npc
```

### 7.3 AbilityProjectile.tscn Update

**File:** `godot_project/scenes/vfx/AbilityProjectile.tscn`

**Changes:**
1. Replace `ColorRect` with `Sprite2D`
2. Texture set dynamically in `setup()` function
3. Rotation applied to align with movement direction

### 7.4 UI Scene Updates

**HUD.tscn:**
- Replace placeholder ColorRect ability slots with TextureRect nodes
- Set texture_filter to NEAREST for all icon displays

**InventoryPanel.tscn:**
- Update item slot template to use TextureRect instead of ColorRect
- Apply TEXTURE_FILTER_NEAREST to inventory grid

**ChatPanel.tscn:**
- Add channel icon TextureRect nodes to message rows
- Size: 12x12 pixels, nearest-neighbor filtering

### 7.5 LootContainer.tscn Update

**File:** `godot_project/scenes/world/entities/LootContainer.tscn`

**Changes:**
1. Replace placeholder ColorRect with Sprite2D
2. Texture switches between closed/open/corpse states
3. Script controls state transitions via `open_container()` method

---

## Data Models

### 8.1 SpriteFrames Resource Structure

**player_frames.tres:**
```gdscript
[gd_resource type="SpriteFrames" load_steps=13 format=3]

# ExtResource declarations for all 12 player sprite PNGs
[ext_resource type="Texture2D" uid="uid://player_idle_up" path="res://assets/sprites/entities/player/player_idle_up.png" id="1"]
# ... (11 more texture loads)

[resource]
animations = [
	{
		"frames": [{"duration": 1.0, "texture": ExtResource("1")}],
		"loop": true,
		"name": &"idle_up",
		"speed": 5.0
	},
	{
		"frames": [{"duration": 1.0, "texture": ExtResource("2")}],
		"loop": true,
		"name": &"idle_down",
		"speed": 5.0
	},
	{
		"frames": [{"duration": 1.0, "texture": ExtResource("3")}],
		"loop": true,
		"name": &"idle_left",
		"speed": 5.0
	},
	{
		"frames": [{"duration": 1.0, "texture": ExtResource("4")}],
		"loop": true,
		"name": &"idle_right",
		"speed": 5.0
	},
	{
		"frames": [
			{"duration": 1.0, "texture": ExtResource("5")},
			{"duration": 1.0, "texture": ExtResource("6")}
		],
		"loop": true,
		"name": &"walk_up",
		"speed": 8.0
	},
	{
		"frames": [
			{"duration": 1.0, "texture": ExtResource("7")},
			{"duration": 1.0, "texture": ExtResource("8")}
		],
		"loop": true,
		"name": &"walk_down",
		"speed": 8.0
	},
	{
		"frames": [
			{"duration": 1.0, "texture": ExtResource("9")},
			{"duration": 1.0, "texture": ExtResource("10")}
		],
		"loop": true,
		"name": &"walk_left",
		"speed": 8.0
	},
	{
		"frames": [
			{"duration": 1.0, "texture": ExtResource("11")},
			{"duration": 1.0, "texture": ExtResource("12")}
		],
		"loop": true,
		"name": &"walk_right",
		"speed": 8.0
	}
]
```

### 8.2 Sprite Mapping Dictionaries

**Centralized in Autoload (SpriteRegistry.gd - NEW):**
```gdscript
extends Node

# Entity sprites
const PLAYER_FRAMES = preload("res://assets/sprites/entities/player/player_frames.tres")

const NPC_SPRITES = {
	"vendor": preload("res://assets/sprites/entities/npcs/npc_vendor_idle.png"),
	"quest_giver": preload("res://assets/sprites/entities/npcs/npc_quest_idle.png"),
	"hostile_slime": preload("res://assets/sprites/entities/npcs/npc_hostile_slime.png"),
	"hostile_goblin": preload("res://assets/sprites/entities/npcs/npc_hostile_goblin.png"),
	"hostile_skeleton": preload("res://assets/sprites/entities/npcs/npc_hostile_skeleton.png"),
}

# Projectile sprites
const PROJECTILE_SPRITES = {
	"fireball": preload("res://assets/sprites/vfx/projectile_fireball.png"),
	"arrow": preload("res://assets/sprites/vfx/projectile_arrow.png"),
	"magic_missile": preload("res://assets/sprites/vfx/projectile_magic_missile.png"),
}

# UI sprites
const ITEM_ICONS = {
	"potion_health": preload("res://assets/sprites/ui/items/item_potion_health.png"),
	"potion_mana": preload("res://assets/sprites/ui/items/item_potion_mana.png"),
	"sword": preload("res://assets/sprites/ui/items/item_sword.png"),
	"shield": preload("res://assets/sprites/ui/items/item_shield.png"),
	"armor": preload("res://assets/sprites/ui/items/item_armor.png"),
	"gold": preload("res://assets/sprites/ui/items/item_gold.png"),
	"key": preload("res://assets/sprites/ui/items/item_key.png"),
	"scroll": preload("res://assets/sprites/ui/items/item_scroll.png"),
	"gem": preload("res://assets/sprites/ui/items/item_gem.png"),
	"food": preload("res://assets/sprites/ui/items/item_food.png"),
}

const ABILITY_ICONS = {
	"fireball": preload("res://assets/sprites/ui/abilities/ability_fireball.png"),
	"heal": preload("res://assets/sprites/ui/abilities/ability_heal.png"),
	"shield": preload("res://assets/sprites/ui/abilities/ability_shield.png"),
	"dash": preload("res://assets/sprites/ui/abilities/ability_dash.png"),
	"stun": preload("res://assets/sprites/ui/abilities/ability_stun.png"),
}

const STATUS_ICONS = {
	"poison": preload("res://assets/sprites/ui/status/status_poison.png"),
	"burn": preload("res://assets/sprites/ui/status/status_burn.png"),
	"frozen": preload("res://assets/sprites/ui/status/status_frozen.png"),
	"blessed": preload("res://assets/sprites/ui/status/status_blessed.png"),
}

const CHAT_ICONS = {
	"guild": preload("res://assets/sprites/ui/chat/chat_guild.png"),
	"party": preload("res://assets/sprites/ui/chat/chat_party.png"),
	"system": preload("res://assets/sprites/ui/chat/chat_system.png"),
	"whisper": preload("res://assets/sprites/ui/chat/chat_whisper.png"),
}

const LOOT_SPRITES = {
	"chest_closed": preload("res://assets/sprites/entities/loot/loot_chest_closed.png"),
	"chest_open": preload("res://assets/sprites/entities/loot/loot_chest_open.png"),
	"corpse": preload("res://assets/sprites/entities/loot/loot_corpse.png"),
}

func get_npc_sprite(npc_type: String) -> Texture2D:
	return NPC_SPRITES.get(npc_type, NPC_SPRITES["hostile_slime"])

func get_projectile_sprite(effect_type: String) -> Texture2D:
	return PROJECTILE_SPRITES.get(effect_type, PROJECTILE_SPRITES["fireball"])

func get_item_icon(item_type: String) -> Texture2D:
	return ITEM_ICONS.get(item_type, null)

# ... (similar getters for other sprite types)
```

**Project Settings Addition:**
```
[autoload]
SpriteRegistry="*res://autoload/SpriteRegistry.gd"
```

---

## Performance Considerations

### 9.1 Rendering Optimization

**Batching Strategy:**
- Godot automatically batches draw calls for nodes using the same texture
- Group entities using identical sprites (e.g., multiple slimes) benefits from automatic batching
- UI icons with different textures may cause batch breaks, but small draw call overhead acceptable for UI layer

**Sprite Atlas (Optional Future Optimization):**
- If profiling shows excessive draw calls, combine sprites into atlas textures
- Use AtlasTexture resources to reference subregions
- Trade-off: Increased complexity vs. potential FPS gains

### 9.2 Memory Management

**Texture Memory Estimates:**
- Player sprites: 12 × 32×32 × 4 bytes (RGBA) = 49 KB uncompressed
- NPC sprites: 5 × 32×32 × 4 bytes = 20 KB
- Projectiles: 3 × 16×16 × 4 bytes = 3 KB
- UI icons: ~30 × (12-32)² × 4 bytes ≈ 50 KB
- **Total:** ~122 KB uncompressed sprite data

**Godot Compression:**
- CompressedTexture2D reduces GPU memory by ~75%
- Estimated VRAM usage: ~30 KB for all sprites
- Negligible impact on 2GB+ GPU memory budget

### 9.3 Performance Targets Validation

**Test Scenario:** 200 entities (150 NPCs + 50 players) with sprites
- Draw calls: ~10-15 (batched by texture type)
- GPU load: <5% on mid-range GPU (GTX 1060 equivalent)
- CPU load: Unchanged (sprite rendering GPU-bound)
- **Expected FPS:** 60+ on target hardware ✓

**Load Time:**
- Godot preloads textures on scene instantiation
- 30 KB compressed data loads in <50ms
- Well within 2-second budget ✓

---

## Testing Strategy

### 10.1 Visual Verification Tests

**Test 1: Player Sprite Display**
- Spawn player entity in Zone scene
- Verify AnimatedSprite2D displays "idle_down" animation
- Move player in all 4 directions, confirm correct walk animations play
- **Pass Criteria:** Correct sprite for each direction, smooth transitions

**Test 2: NPC Type Differentiation**
- Spawn 3 NPCs with metadata: `{type: "vendor"}`, `{type: "quest_giver"}`, `{type: "hostile_slime"}`
- Visually confirm distinct sprites render
- **Pass Criteria:** Each NPC shows unique sprite matching type

**Test 3: Projectile Rotation**
- Cast fireball ability at target 45° from player
- Verify sprite rotates to face direction of travel
- **Pass Criteria:** Arrow tip/flame direction aligns with velocity vector

**Test 4: UI Icon Rendering**
- Open inventory with 10 different item types
- Confirm each displays correct 24x24 icon
- **Pass Criteria:** All icons visible, no missing textures

### 10.2 Performance Tests

**Test 5: Entity Stress Test**
- Spawn 200 NPC entities with sprites in single zone
- Monitor FPS via Godot performance overlay
- **Pass Criteria:** ≥60 FPS maintained

**Test 6: Texture Memory Validation**
- Open Godot debugger, check "Video Mem" usage
- Load all scenes with sprites active
- **Pass Criteria:** Sprite texture memory <50 MB

### 10.3 Integration Tests

**Test 7: Animation State Persistence**
- Move player, then open inventory (pause game)
- Close inventory, verify animation resumes correctly
- **Pass Criteria:** No animation glitches or resets

**Test 8: Dynamic Sprite Assignment**
- Server sends NPC spawn with new `npc_type: "hostile_orc"` (not yet implemented)
- Verify fallback sprite displays (hostile_slime)
- **Pass Criteria:** No crashes, fallback sprite renders

### 10.4 Import Validation

**Test 9: Godot Import Settings**
- Check `.import` files for all sprites
- Verify `compress/mode=0` and `mipmaps/generate=false`
- **Pass Criteria:** All import files match template configuration

**Test 10: Missing Asset Handling**
- Temporarily rename a sprite file
- Open scene in Godot editor
- **Pass Criteria:** Console warning displayed, no editor crash

---

## Implementation Phases

### Phase 1: Asset Creation (Requirement 6)
**Duration:** 2-3 days

**Tasks:**
1. Define 16-color palette, export as GIMP/Aseprite palette file
2. Generate player sprite set (12 frames)
3. Generate NPC sprites (5 types)
4. Generate projectile sprites (3 types)
5. Generate UI icons (items: 10, abilities: 5, status: 4, chat: 4)
6. Generate loot sprites (3 states)
7. Organize files into `assets/sprites/` directory structure
8. Create `assets/sprites/README.md` with creation guidelines

**Deliverables:**
- 41 PNG sprite files organized in subdirectories
- README.md with palette, naming conventions, tool instructions

### Phase 2: Godot Import Configuration (Requirement 6)
**Duration:** 1 day

**Tasks:**
1. Copy all PNG files into `godot_project/assets/sprites/`
2. Open Godot editor, allow auto-import
3. Verify all `.import` files generated correctly
4. Manually configure any incorrectly imported textures (set to 2D Pixel preset)
5. Test texture display in Godot inspector (should show crisp pixels)

**Deliverables:**
- All sprites imported as CompressedTexture2D
- Import settings validated

### Phase 3: Player Entity Integration (Requirement 1)
**Duration:** 1 day

**Tasks:**
1. Create `player_frames.tres` SpriteFrames resource
2. Configure 8 animations (idle/walk × 4 directions)
3. Modify `PlayerEntity.tscn` to use AnimatedSprite2D
4. Update `PlayerEntity.gd` with animation control logic
5. Test in-game: movement in all directions, animation transitions

**Deliverables:**
- Updated PlayerEntity.tscn scene
- Updated PlayerEntity.gd script
- player_frames.tres resource

### Phase 4: NPC Entity Integration (Requirement 2)
**Duration:** 1 day

**Tasks:**
1. Create `SpriteRegistry.gd` autoload
2. Populate NPC_SPRITES dictionary
3. Modify `NPCEntity.tscn` to use Sprite2D
4. Update `NPCEntity.gd` with `set_npc_type()` method
5. Update `WorldState.gd` NPC spawning to pass type metadata
6. Test: Spawn vendor, quest, and hostile NPCs, verify visual differences

**Deliverables:**
- SpriteRegistry.gd autoload
- Updated NPCEntity.tscn/.gd
- Updated WorldState.gd spawning logic

### Phase 5: Projectile & VFX Integration (Requirement 3)
**Duration:** 0.5 days

**Tasks:**
1. Add PROJECTILE_SPRITES to SpriteRegistry.gd
2. Modify `AbilityProjectile.tscn` to use Sprite2D
3. Update `AbilityProjectile.gd` setup() to assign texture and rotation
4. Test: Cast fireball, arrow, magic missile abilities, verify rotation

**Deliverables:**
- Updated AbilityProjectile.tscn/.gd

### Phase 6: UI Icon Integration (Requirement 4)
**Duration:** 1.5 days

**Tasks:**
1. Add ITEM_ICONS, ABILITY_ICONS, STATUS_ICONS, CHAT_ICONS to SpriteRegistry.gd
2. Update `InventoryPanel.gd` item slot creation with TextureRect
3. Update `HUD.gd` ability bar with icon textures
4. Update `ChatPanel.gd` message rows with channel icons
5. Test: Open all UI panels, verify icons display correctly

**Deliverables:**
- Updated InventoryPanel.gd
- Updated HUD.gd
- Updated ChatPanel.gd

### Phase 7: Loot Container Integration (Requirement 5)
**Duration:** 0.5 days

**Tasks:**
1. Add LOOT_SPRITES to SpriteRegistry.gd
2. Modify `LootContainer.tscn` to use Sprite2D
3. Update `LootContainer.gd` with state-based texture switching
4. Test: Spawn chest, interact to loot, verify open sprite displays

**Deliverables:**
- Updated LootContainer.tscn/.gd

### Phase 8: Testing & Polish (All Requirements)
**Duration:** 1 day

**Tasks:**
1. Run all 10 test cases from Testing Strategy (§10)
2. Fix any visual artifacts, missing textures, or performance issues
3. Validate FPS with 200 entities (stress test)
4. Document any known issues or future optimizations
5. Create before/after screenshots for documentation

**Deliverables:**
- Test results documentation
- Performance benchmarks
- Bug fixes applied

---

## Dependencies and Risks

### Dependencies
- Godot 4.3+ (AnimatedSprite2D, TextureRect features)
- AI image generation access (Stable Diffusion/DALL-E) OR pixel art tools (Aseprite)
- Existing scene structure (node names must remain consistent)

### Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| AI-generated sprites inconsistent quality | Medium | Manual cleanup in Aseprite, fallback to hand-drawn |
| Import settings misconfigured, blurry sprites | High | Automated validation script, template .import files |
| Script references break after node type changes | High | Preserve node names, update @onready references carefully |
| Performance degradation with many sprites | Medium | Profile early, implement atlasing if needed |
| Color palette violations reduce visual cohesion | Low | Strict palette enforcement during generation |

### Assumptions Validation
- ✓ 32x32 resolution adequate for readability (validated against existing ColorRect sizes)
- ✓ 4-directional sprites sufficient (no diagonal movement in current design)
- ✓ Nearest-neighbor filtering preferred (pixel-art aesthetic confirmed)
- ? Budget/timeline constraints (assumes 5-7 day implementation window)

---

## Appendix

### A. Sprite Generation Prompts (AI Tools)

**Player Character (Stable Diffusion Prompt):**
```
pixel art character sprite, 32x32 resolution, 2D top-down view, fantasy warrior, blue tunic, facing down, idle stance, transparent background, PICO-8 color palette, crisp pixels, retro game style, single character centered
```

**Vendor NPC (Stable Diffusion Prompt):**
```
pixel art NPC sprite, 32x32 resolution, 2D top-down view, merchant character, gold and brown colors, carrying pack, facing down, idle stance, transparent background, PICO-8 palette, retro JRPG style
```

**Fireball Projectile (Stable Diffusion Prompt):**
```
pixel art fireball sprite, 16x16 resolution, orange and red flame orb, glowing effect, side view, transparent background, PICO-8 color palette, retro game style, simple design
```

### B. Manual Pixel Art Workflow (Aseprite)

1. Create new sprite: 32×32 canvas (or 16×16 for projectiles)
2. Import 16-color palette from file
3. Use pencil tool (1px brush) to draw outline
4. Fill with base colors
5. Add highlights/shadows (limited to palette)
6. Create additional frames for animations (linked cels for color sync)
7. Export as PNG sequence with naming: `<name>_<state>_<direction>_<frame>.png`
8. Run batch export script for all variations

### C. Import Settings Automation Script

**Godot GDScript (run in editor via EditorScript):**
```gdscript
@tool
extends EditorScript

func _run() -> void:
	var dir = DirAccess.open("res://assets/sprites/")
	configure_recursive(dir, "res://assets/sprites/")

func configure_recursive(dir: DirAccess, path: String) -> void:
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_path = path + "/" + file_name
		if dir.current_is_dir():
			var subdir = DirAccess.open(full_path)
			configure_recursive(subdir, full_path)
		elif file_name.ends_with(".png"):
			configure_sprite_import(full_path)
		file_name = dir.get_next()

func configure_sprite_import(png_path: String) -> void:
	var import_path = png_path + ".import"
	var config = ConfigFile.new()
	config.load(import_path)
	
	# Force 2D pixel settings
	config.set_value("params", "compress/mode", 0)
	config.set_value("params", "mipmaps/generate", false)
	config.set_value("params", "detect_3d/compress_to", 0)
	
	config.save(import_path)
	print("Configured: ", png_path)
```

---

**End of Design Document**

This design provides a comprehensive technical blueprint for implementing sprite generation and application across the MMORPG Nakama Godot client. All requirements are addressed with specific implementation details, code examples, and testing strategies.
