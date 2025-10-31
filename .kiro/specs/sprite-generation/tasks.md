# Tasks: Sprite Generation and Application

**Feature:** Sprite Generation and Application  
**Status:** Not Started  
**Version:** 1.0  
**Last Updated:** October 31, 2025

---

## Task Overview

This document breaks down the sprite generation and application feature into discrete, trackable implementation tasks. Each task is linked to specific requirements and design sections.

**Total Estimated Duration:** 7-8 days  
**Dependencies:** Godot 4.3+, pixel art generation tools

---

## Phase 1: Asset Creation

### Task 1.1: Define Color Palette and Setup Tools
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** High

**Description:**
Create the 16-color palette that will be used for all sprite assets and configure sprite generation tools.

**Acceptance Criteria:**
- [ ] 16-color palette defined with hex codes
- [ ] Palette exported as .gpl file (GIMP) and .ase file (Aseprite)
- [ ] AI generation tool configured (Stable Diffusion) OR manual tool setup (Aseprite/LibreSprite)
- [ ] Test sprite created to validate palette and tool workflow

**Traceability:**
- Requirements: NFR - Visual Quality Requirements
- Design: §5.2 Color Palette Definition

**Implementation Notes:**
```
Palette colors (PICO-8 inspired):
#000000, #1d2b53, #7e2553, #008751, #ab5236, #5f574f, 
#c2c3c7, #fff1e8, #ff004d, #ffa300, #ffec27, #00e436, 
#29adff, #83769c, #ff77a8, #ffccaa
```

---

### Task 1.2: Generate Player Character Sprites
**Status:** ⬜ Not Started  
**Estimated Time:** 4 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 1.1

**Description:**
Create all 12 player sprite frames (4 directions × idle + 4 directions × 2-frame walk animations).

**Acceptance Criteria:**
- [ ] 4 idle sprites created (up, down, left, right) - 32x32 pixels
- [ ] 8 walk animation frames created (2 frames per direction) - 32x32 pixels
- [ ] All sprites use defined 16-color palette
- [ ] Transparent backgrounds applied
- [ ] Sprites visually consistent with blue player theme (#29adff base color)
- [ ] Files named correctly: `player_idle_<direction>.png`, `player_walk_<direction>_<frame>.png`

**Traceability:**
- Requirements: Requirement 1 - Player Entity Sprite Assets
- Design: §3.1 Player Character Sprites, §7.1 PlayerEntity.tscn Complete Update

**File Outputs:**
```
player_idle_up.png
player_idle_down.png
player_idle_left.png
player_idle_right.png
player_walk_up_0.png, player_walk_up_1.png
player_walk_down_0.png, player_walk_down_1.png
player_walk_left_0.png, player_walk_left_1.png
player_walk_right_0.png, player_walk_right_1.png
```

---

### Task 1.3: Generate NPC Sprites
**Status:** ⬜ Not Started  
**Estimated Time:** 3 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 1.1

**Description:**
Create 5 distinct NPC sprite types for vendors, quest givers, and hostile mobs.

**Acceptance Criteria:**
- [ ] Vendor NPC sprite created (gold/brown merchant theme) - 32x32 pixels
- [ ] Quest Giver NPC sprite created (purple/blue robed figure) - 32x32 pixels
- [ ] Hostile Slime sprite created (red-tinted blob) - 32x32 pixels
- [ ] Hostile Goblin sprite created (red-tinted humanoid) - 32x32 pixels
- [ ] Hostile Skeleton sprite created (red-tinted undead) - 32x32 pixels
- [ ] All sprites use 16-color palette
- [ ] Visual differentiation clear between NPC types
- [ ] Files named correctly: `npc_<type>_idle.png`

**Traceability:**
- Requirements: Requirement 2 - NPC Entity Sprite Differentiation
- Design: §3.2 NPC Sprites, §6.2 NPCEntity Scene Modifications

**File Outputs:**
```
npc_vendor_idle.png
npc_quest_idle.png
npc_hostile_slime.png
npc_hostile_goblin.png
npc_hostile_skeleton.png
```

---

### Task 1.4: Generate Projectile Sprites
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 1.1

**Description:**
Create 3 projectile sprite types for combat abilities.

**Acceptance Criteria:**
- [ ] Fireball sprite created (orange/red flame orb) - 16x16 pixels
- [ ] Arrow sprite created (brown shaft, gray tip, facing right) - 16x16 pixels
- [ ] Magic Missile sprite created (purple/blue energy bolt) - 16x16 pixels
- [ ] All sprites use 16-color palette
- [ ] Sprites designed for rotation (symmetric or directional clarity)
- [ ] Files named correctly: `projectile_<type>.png`

**Traceability:**
- Requirements: Requirement 3 - Ability Projectile Visual Assets
- Design: §3.3 Projectile Sprites, §6.3 AbilityProjectile Scene Modifications

**File Outputs:**
```
projectile_fireball.png
projectile_arrow.png
projectile_magic_missile.png
```

---

### Task 1.5: Generate UI Item Icons
**Status:** ⬜ Not Started  
**Estimated Time:** 3 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 1.1

**Description:**
Create 10 inventory item icons at 24x24 pixel resolution.

**Acceptance Criteria:**
- [ ] 10 item icons created: health potion, mana potion, sword, shield, armor, gold, key, scroll, gem, food
- [ ] All icons 24x24 pixels
- [ ] Clear symbolic representations (avoid over-detail)
- [ ] High contrast for visibility
- [ ] 16-color palette used
- [ ] Files named correctly: `item_<name>.png`

**Traceability:**
- Requirements: Requirement 4 - UI Icon and Element Sprites
- Design: §3.4 UI Icon Sprites (Inventory Items)

**File Outputs:**
```
item_potion_health.png, item_potion_mana.png, item_sword.png,
item_shield.png, item_armor.png, item_gold.png, item_key.png,
item_scroll.png, item_gem.png, item_food.png
```

---

### Task 1.6: Generate UI Ability and Status Icons
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 1.1

**Description:**
Create ability icons (32x32), status effect icons (16x16), and chat channel icons (12x12).

**Acceptance Criteria:**
- [ ] 5 ability icons created: fireball, heal, shield, dash, stun - 32x32 pixels
- [ ] 4 status icons created: poison, burn, frozen, blessed - 16x16 pixels
- [ ] 4 chat icons created: guild, party, system, whisper - 12x12 pixels
- [ ] All icons use 16-color palette
- [ ] Clear symbolic representations
- [ ] Files named correctly: `ability_<name>.png`, `status_<name>.png`, `chat_<name>.png`

**Traceability:**
- Requirements: Requirement 4 - UI Icon and Element Sprites
- Design: §3.4 UI Icon Sprites (Abilities, Status, Chat)

**File Outputs:**
```
Abilities (32x32): ability_fireball.png, ability_heal.png, ability_shield.png, ability_dash.png, ability_stun.png
Status (16x16): status_poison.png, status_burn.png, status_frozen.png, status_blessed.png
Chat (12x12): chat_guild.png, chat_party.png, chat_system.png, chat_whisper.png
```

---

### Task 1.7: Generate Loot Container Sprites
**Status:** ⬜ Not Started  
**Estimated Time:** 1.5 hours  
**Assigned To:** TBD  
**Priority:** Low  
**Dependencies:** Task 1.1

**Description:**
Create loot container sprites with open/closed states.

**Acceptance Criteria:**
- [ ] Chest closed sprite created (brown wooden chest) - 32x32 pixels
- [ ] Chest open sprite created (lid open, empty interior) - 32x32 pixels
- [ ] Corpse marker sprite created (tombstone or body outline) - 32x32 pixels
- [ ] All sprites use 16-color palette
- [ ] Visual distinction clear between states
- [ ] Files named correctly: `loot_<type>_<state>.png`

**Traceability:**
- Requirements: Requirement 5 - Loot Container Visual Representation
- Design: §3.5 Loot Container Sprites

**File Outputs:**
```
loot_chest_closed.png
loot_chest_open.png
loot_corpse.png
```

---

### Task 1.8: Organize Assets and Create Documentation
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Tasks 1.2-1.7

**Description:**
Organize all sprite files into proper directory structure and create asset creation guidelines.

**Acceptance Criteria:**
- [ ] Directory structure created: `assets/sprites/entities/`, `assets/sprites/vfx/`, `assets/sprites/ui/`
- [ ] All 41 sprite files moved to correct subdirectories
- [ ] `assets/sprites/README.md` created with:
  - Color palette reference
  - Naming convention documentation
  - Tool setup instructions
  - Sprite creation workflow
- [ ] File count validation: 12 player + 5 NPC + 3 projectile + 10 items + 5 abilities + 4 status + 4 chat + 3 loot = 46 total files

**Traceability:**
- Requirements: Requirement 6 - NFR Maintainability
- Design: §4 Asset Directory Structure

**Deliverable:**
- Organized sprite directory ready for Godot import
- README.md documentation file

---

## Phase 2: Godot Import Configuration

### Task 2.1: Import Sprites into Godot Project
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 1.8

**Description:**
Copy sprite directory into Godot project and trigger auto-import.

**Acceptance Criteria:**
- [ ] `assets/sprites/` directory copied to `godot_project/assets/sprites/`
- [ ] Godot editor opened and auto-import completed
- [ ] All 46 sprite files have corresponding `.import` files generated
- [ ] No import errors in Godot console
- [ ] Sprites visible in Godot FileSystem panel

**Traceability:**
- Requirements: Requirement 6 - Sprite Asset Integration into Godot Scenes
- Design: §5.3 Import Configuration Template

**Validation Command:**
```powershell
# Count .import files
(Get-ChildItem -Path "godot_project/assets/sprites" -Filter "*.png.import" -Recurse).Count
# Should equal 46
```

---

### Task 2.2: Configure Import Settings for Pixel-Perfect Rendering
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 2.1

**Description:**
Validate and configure all sprite import settings to use 2D Pixel preset with nearest-neighbor filtering.

**Acceptance Criteria:**
- [ ] All `.import` files have `compress/mode=0` (no compression)
- [ ] All `.import` files have `mipmaps/generate=false`
- [ ] All `.import` files have `detect_3d/compress_to=0` (force 2D)
- [ ] Project setting `textures/canvas_textures/default_texture_filter=0` verified (nearest-neighbor global default)
- [ ] Test sprite loaded in inspector shows crisp pixel edges (no blur)

**Traceability:**
- Requirements: Requirement 6 - NFR Visual Quality
- Design: §5.3 Import Configuration Template

**Validation Script (Optional):**
```gdscript
# Run in Godot Editor Script
# See Design Appendix C for full automation script
```

---

### Task 2.3: Verify Texture Import Quality
**Status:** ⬜ Not Started  
**Estimated Time:** 0.5 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 2.2

**Description:**
Manual verification that all sprites imported correctly with pixel-perfect quality.

**Acceptance Criteria:**
- [ ] Randomly sample 10 sprites in Godot inspector
- [ ] Verify pixel edges are crisp (no anti-aliasing blur)
- [ ] Check transparency works correctly (no white halos)
- [ ] Confirm file paths resolve correctly (no missing texture icons)
- [ ] Document any import issues for fixing

**Traceability:**
- Requirements: Requirement 6 - Acceptance Criteria
- Design: §10.4 Import Validation

**Test Sprites to Sample:**
```
player_idle_down.png
npc_vendor_idle.png
projectile_fireball.png
item_potion_health.png
ability_heal.png
```

---

## Phase 3: Player Entity Integration

### Task 3.1: Create Player SpriteFrames Resource
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 2.3

**Description:**
Create `player_frames.tres` SpriteFrames resource with 8 animations configured.

**Acceptance Criteria:**
- [ ] `player_frames.tres` file created in `godot_project/assets/sprites/entities/player/`
- [ ] All 12 player sprite textures loaded as ExtResources
- [ ] 8 animations configured: idle_up, idle_down, idle_left, idle_right, walk_up, walk_down, walk_left, walk_right
- [ ] Idle animations: 1 frame each, 5 FPS, looping
- [ ] Walk animations: 2 frames each, 8 FPS, looping
- [ ] Test playback in AnimationPlayer preview works

**Traceability:**
- Requirements: Requirement 1 - Player Entity Sprite Assets
- Design: §8.1 SpriteFrames Resource Structure

**Resource Structure:**
```gdscript
animations = [
  {name: "idle_up", frames: [player_idle_up.png], speed: 5.0},
  {name: "idle_down", frames: [player_idle_down.png], speed: 5.0},
  # ... 6 more animations
]
```

---

### Task 3.2: Update PlayerEntity Scene with AnimatedSprite2D
**Status:** ⬜ Not Started  
**Estimated Time:** 1.5 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 3.1

**Description:**
Modify `PlayerEntity.tscn` to replace Sprite2D+ColorRect with AnimatedSprite2D node.

**Acceptance Criteria:**
- [ ] `Sprite2D` node removed from PlayerEntity.tscn
- [ ] `ColorRect` child node removed
- [ ] `AnimatedSprite2D` node added as child of PlayerEntity root
- [ ] `sprite_frames` property set to `player_frames.tres` resource
- [ ] Default animation set to "idle_down"
- [ ] Node name remains "AnimatedSprite2D" (or update script references)
- [ ] Scene loads without errors in Godot editor

**Traceability:**
- Requirements: Requirement 1 - WHEN player entity spawns
- Design: §7.1 PlayerEntity.tscn Complete Update

**Scene Diff Preview:**
```diff
- [node name="Sprite2D" type="Sprite2D" parent="."]
-   [node name="ColorRect" type="ColorRect" parent="Sprite2D"]

+ [node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
+ sprite_frames = ExtResource("2_player_frames")
+ animation = "idle_down"
```

---

### Task 3.3: Implement Player Animation Control Logic
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 3.2

**Description:**
Update `PlayerEntity.gd` script to control AnimatedSprite2D animation playback based on movement.

**Acceptance Criteria:**
- [ ] `@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D` reference added
- [ ] `update_animation()` function implemented
- [ ] Direction detection logic implemented (up/down/left/right from velocity vector)
- [ ] Animation state logic: idle vs walk based on velocity magnitude
- [ ] `update_animation()` called in `_physics_process()`
- [ ] Animation transitions smooth (no jitter or stuck frames)

**Traceability:**
- Requirements: Requirement 1 - IF player moves in any direction
- Design: §7.1 Script Animation Control

**Code Implementation:**
```gdscript
func update_animation() -> void:
    var anim_prefix = "walk" if velocity.length() > 10 else "idle"
    var anim_suffix = get_direction_suffix(velocity.normalized())
    var anim_name = anim_prefix + "_" + anim_suffix
    if animated_sprite.animation != anim_name:
        animated_sprite.play(anim_name)
```

---

### Task 3.4: Test Player Entity Sprite Rendering
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 3.3

**Description:**
In-game testing of player sprite display and animation transitions.

**Acceptance Criteria:**
- [ ] Load Zone.tscn scene and run game
- [ ] Player spawns with visible sprite (idle_down by default)
- [ ] Move player up → walk_up animation plays
- [ ] Move player down → walk_down animation plays
- [ ] Move player left → walk_left animation plays
- [ ] Move player right → walk_right animation plays
- [ ] Stop moving → correct idle animation plays for last direction
- [ ] No visual glitches, stuck frames, or missing sprites

**Traceability:**
- Requirements: Requirement 1 - All Acceptance Criteria
- Design: §10.1 Test 1 - Player Sprite Display

**Test Checklist:**
- [ ] Visual: Sprite displays correctly
- [ ] Animation: All 8 animations work
- [ ] Performance: No FPS drop with player sprite

---

## Phase 4: NPC Entity Integration

### Task 4.1: Create SpriteRegistry Autoload
**Status:** ⬜ Not Started  
**Estimated Time:** 1.5 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 2.3

**Description:**
Create centralized SpriteRegistry.gd autoload singleton to manage all sprite texture references.

**Acceptance Criteria:**
- [ ] `SpriteRegistry.gd` file created in `godot_project/autoload/`
- [ ] NPC_SPRITES dictionary populated with 5 NPC texture preloads
- [ ] PROJECTILE_SPRITES dictionary defined (populated in Phase 5)
- [ ] ITEM_ICONS, ABILITY_ICONS, STATUS_ICONS, CHAT_ICONS dictionaries defined (populated in Phase 6)
- [ ] LOOT_SPRITES dictionary defined (populated in Phase 7)
- [ ] Helper functions: `get_npc_sprite()`, `get_projectile_sprite()`, etc.
- [ ] Autoload configured in project.godot: `SpriteRegistry="*res://autoload/SpriteRegistry.gd"`

**Traceability:**
- Requirements: Requirement 2, 3, 4, 5 - Centralized sprite management
- Design: §8.2 Sprite Mapping Dictionaries

**Code Template:**
```gdscript
extends Node

const NPC_SPRITES = {
    "vendor": preload("res://assets/sprites/entities/npcs/npc_vendor_idle.png"),
    # ... 4 more NPC types
}

func get_npc_sprite(npc_type: String) -> Texture2D:
    return NPC_SPRITES.get(npc_type, NPC_SPRITES["hostile_slime"])
```

---

### Task 4.2: Update NPCEntity Scene to Use Sprite2D
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 4.1

**Description:**
Modify `NPCEntity.tscn` to replace ColorRect with proper Sprite2D node.

**Acceptance Criteria:**
- [ ] ColorRect node (currently named "Sprite2D") replaced with actual Sprite2D node
- [ ] Sprite2D node positioned at center (offset 0,0)
- [ ] `centered` property set to true
- [ ] `texture` property initially null (set dynamically by script)
- [ ] Overlay icons (VendorIcon, QuestIcon, AggroIcon) remain unchanged
- [ ] Scene loads without errors

**Traceability:**
- Requirements: Requirement 2 - NPC Entity Sprite Differentiation
- Design: §6.2 NPCEntity Scene Modifications

**Scene Change:**
```diff
- [node name="Sprite2D" type="ColorRect" parent="."]
- offset_left = -16.0
- offset_top = -16.0
- offset_right = 16.0
- offset_bottom = 16.0
- color = Color(0.8, 0.8, 0.8, 1)

+ [node name="Sprite2D" type="Sprite2D" parent="."]
+ texture = null
+ centered = true
```

---

### Task 4.3: Implement NPC Sprite Assignment Logic
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 4.2

**Description:**
Update `NPCEntity.gd` to assign sprite textures based on NPC type metadata.

**Acceptance Criteria:**
- [ ] `@onready var sprite: Sprite2D = $Sprite2D` reference added
- [ ] `set_npc_type(npc_type: String)` function implemented
- [ ] Function retrieves texture from `SpriteRegistry.get_npc_sprite(npc_type)`
- [ ] Fallback to "hostile_slime" sprite if type unknown
- [ ] Function called during NPC initialization

**Traceability:**
- Requirements: Requirement 2 - WHEN NPC spawns with metadata {type: X}
- Design: §6.2 NPCEntity.gd Script Changes

**Code Implementation:**
```gdscript
func set_npc_type(npc_type: String) -> void:
    sprite.texture = SpriteRegistry.get_npc_sprite(npc_type)
```

---

### Task 4.4: Update WorldState NPC Spawning
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 4.3

**Description:**
Modify `WorldState.gd` to pass NPC type metadata when spawning NPCs.

**Acceptance Criteria:**
- [ ] Locate NPC spawning logic in `WorldState.gd`
- [ ] Extract `npc_type` from server entity metadata
- [ ] Call `npc.set_npc_type(npc_type)` after NPC instantiation
- [ ] Handle missing `npc_type` metadata gracefully (default to "hostile_slime")
- [ ] Test with mock entity data containing various npc_type values

**Traceability:**
- Requirements: Requirement 2 - Server metadata integration
- Design: §6.2 WorldState.gd Spawning Update

**Code Addition:**
```gdscript
func spawn_npc(entity_id: String, entity_data: Dictionary) -> void:
    var npc = npc_scene.instantiate()
    npc.position = Vector2(entity_data.position.x, entity_data.position.y)
    npc.set_npc_type(entity_data.get("npc_type", "hostile_slime"))
    # ... rest of spawning logic
```

---

### Task 4.5: Test NPC Sprite Differentiation
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Task 4.4

**Description:**
In-game testing of NPC sprite visual differentiation.

**Acceptance Criteria:**
- [ ] Spawn vendor NPC → displays merchant sprite
- [ ] Spawn quest_giver NPC → displays robed figure sprite
- [ ] Spawn hostile_slime NPC → displays red blob sprite
- [ ] Spawn hostile_goblin NPC → displays goblin sprite
- [ ] Spawn hostile_skeleton NPC → displays skeleton sprite
- [ ] Spawn NPC with unknown type → displays fallback sprite (slime)
- [ ] All NPC sprites render at correct size (32x32 centered)
- [ ] No console errors during spawning

**Traceability:**
- Requirements: Requirement 2 - All Acceptance Criteria
- Design: §10.1 Test 2 - NPC Type Differentiation

**Test Data:**
```gdscript
# Mock entity spawn for testing
WorldState.spawn_npc("npc1", {position: {x: 100, y: 100}, npc_type: "vendor"})
WorldState.spawn_npc("npc2", {position: {x: 200, y: 100}, npc_type: "quest_giver"})
WorldState.spawn_npc("npc3", {position: {x: 300, y: 100}, npc_type: "hostile_goblin"})
```

---

## Phase 5: Projectile & VFX Integration

### Task 5.1: Add Projectile Sprites to SpriteRegistry
**Status:** ⬜ Not Started  
**Estimated Time:** 0.5 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 4.1, Task 2.3

**Description:**
Populate PROJECTILE_SPRITES dictionary in SpriteRegistry.gd.

**Acceptance Criteria:**
- [ ] PROJECTILE_SPRITES dictionary updated with 3 texture preloads
- [ ] Textures: fireball, arrow, magic_missile
- [ ] `get_projectile_sprite(effect_type: String)` function implemented
- [ ] Fallback to "fireball" sprite if effect_type unknown
- [ ] No compilation errors

**Traceability:**
- Requirements: Requirement 3 - Ability Projectile Visual Assets
- Design: §8.2 Sprite Mapping Dictionaries

**Code Addition:**
```gdscript
const PROJECTILE_SPRITES = {
    "fireball": preload("res://assets/sprites/vfx/projectile_fireball.png"),
    "arrow": preload("res://assets/sprites/vfx/projectile_arrow.png"),
    "magic_missile": preload("res://assets/sprites/vfx/projectile_magic_missile.png"),
}
```

---

### Task 5.2: Update AbilityProjectile Scene to Use Sprite2D
**Status:** ⬜ Not Started  
**Estimated Time:** 0.5 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 5.1

**Description:**
Modify `AbilityProjectile.tscn` to replace ColorRect with Sprite2D.

**Acceptance Criteria:**
- [ ] ColorRect node removed
- [ ] Sprite2D node added with name "Sprite"
- [ ] `centered` property set to true
- [ ] `texture` property null (set dynamically)
- [ ] Trail Line2D node remains unchanged
- [ ] Scene loads without errors

**Traceability:**
- Requirements: Requirement 3 - Projectile visual representation
- Design: §6.3 AbilityProjectile Scene Modifications

**Scene Change:**
```diff
- [node name="Sprite" type="ColorRect" parent="."]
- color = Color(1, 0.5, 0, 1)

+ [node name="Sprite" type="Sprite2D" parent="."]
+ texture = null
+ centered = true
```

---

### Task 5.3: Implement Projectile Sprite and Rotation Logic
**Status:** ⬜ Not Started  
**Estimated Time:** 1.5 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 5.2

**Description:**
Update `AbilityProjectile.gd` to assign sprite texture and rotate toward target.

**Acceptance Criteria:**
- [ ] `@onready var sprite: Sprite2D = $Sprite` reference added
- [ ] `setup()` function updated to accept `effect_type` parameter
- [ ] Sprite texture retrieved from `SpriteRegistry.get_projectile_sprite(effect_type)`
- [ ] Rotation calculated from direction vector: `rotation = direction.angle()`
- [ ] Projectile moves in correct direction with sprite aligned
- [ ] Arrow sprite points toward target during flight

**Traceability:**
- Requirements: Requirement 3 - WHERE projectiles travel, sprites rotate
- Design: §6.3 AbilityProjectile.gd Script Changes

**Code Implementation:**
```gdscript
func setup(effect_type: String, start_pos: Vector2, target_pos: Vector2) -> void:
    position = start_pos
    sprite.texture = SpriteRegistry.get_projectile_sprite(effect_type)
    
    var direction = (target_pos - start_pos).normalized()
    rotation = direction.angle()
    velocity = direction * projectile_speed
```

---

### Task 5.4: Test Projectile Sprite Rendering
**Status:** ⬜ Not Started  
**Estimated Time:** 0.5 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 5.3

**Description:**
In-game testing of projectile sprites with rotation.

**Acceptance Criteria:**
- [ ] Cast fireball ability → orange/red fireball sprite appears, rotates toward target
- [ ] Cast arrow ability → arrow sprite appears, tip points in flight direction
- [ ] Cast magic_missile ability → purple/blue bolt sprite appears, oriented correctly
- [ ] Projectiles travel smoothly without visual glitches
- [ ] Sprite disappears on impact (no orphaned sprites)

**Traceability:**
- Requirements: Requirement 3 - All Acceptance Criteria
- Design: §10.1 Test 3 - Projectile Rotation

**Test Actions:**
- Cast abilities at 0°, 45°, 90°, 135°, 180° angles
- Verify sprite rotation matches flight direction

---

## Phase 6: UI Icon Integration

### Task 6.1: Add UI Icon Sprites to SpriteRegistry
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 4.1, Task 2.3

**Description:**
Populate ITEM_ICONS, ABILITY_ICONS, STATUS_ICONS, CHAT_ICONS dictionaries.

**Acceptance Criteria:**
- [ ] ITEM_ICONS dictionary updated with 10 item texture preloads
- [ ] ABILITY_ICONS dictionary updated with 5 ability texture preloads
- [ ] STATUS_ICONS dictionary updated with 4 status texture preloads
- [ ] CHAT_ICONS dictionary updated with 4 chat texture preloads
- [ ] Getter functions implemented for each icon type
- [ ] All preload paths resolve correctly (no missing files)

**Traceability:**
- Requirements: Requirement 4 - UI Icon and Element Sprites
- Design: §8.2 Sprite Mapping Dictionaries

**Code Additions:**
```gdscript
const ITEM_ICONS = {
    "potion_health": preload("res://assets/sprites/ui/items/item_potion_health.png"),
    # ... 9 more items
}

const ABILITY_ICONS = {
    "fireball": preload("res://assets/sprites/ui/abilities/ability_fireball.png"),
    # ... 4 more abilities
}
# ... STATUS_ICONS, CHAT_ICONS
```

---

### Task 6.2: Update InventoryPanel Item Icon Display
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 6.1

**Description:**
Modify `InventoryPanel.gd` to display item icons using TextureRect nodes.

**Acceptance Criteria:**
- [ ] `create_item_slot()` function updated to use TextureRect instead of ColorRect
- [ ] Texture retrieved from `SpriteRegistry.get_item_icon(item_type)`
- [ ] TextureRect size set to 24x24 pixels
- [ ] `texture_filter` set to TEXTURE_FILTER_NEAREST
- [ ] `stretch_mode` set to STRETCH_KEEP_CENTERED
- [ ] Fallback for unknown item types (display placeholder or skip icon)
- [ ] Icons display correctly in inventory grid

**Traceability:**
- Requirements: Requirement 4 - WHEN inventory displays item
- Design: §6.4 InventoryPanel.gd - Item Icon Display

**Code Implementation:**
```gdscript
func create_item_slot(item_data: Dictionary) -> TextureRect:
    var slot = TextureRect.new()
    slot.custom_minimum_size = Vector2(24, 24)
    slot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    
    var item_type = item_data.get("type", "unknown")
    slot.texture = SpriteRegistry.get_item_icon(item_type)
    
    return slot
```

---

### Task 6.3: Update HUD Ability Bar Icons
**Status:** ⬜ Not Started  
**Estimated Time:** 1.5 hours  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Task 6.1

**Description:**
Modify `HUD.gd` to display ability icons in the ability bar.

**Acceptance Criteria:**
- [ ] Ability bar slots updated to use TextureRect or TextureButton
- [ ] Icons retrieved from `SpriteRegistry.get_ability_icon(ability_id)`
- [ ] Icon size 32x32 pixels
- [ ] `texture_filter` set to TEXTURE_FILTER_NEAREST
- [ ] Ability tooltips still functional (if implemented)
- [ ] Icons update dynamically when abilities change

**Traceability:**
- Requirements: Requirement 4 - IF ability bar shows abilities
- Design: §6.4 HUD.gd - Ability Bar Icons

**Code Implementation:**
```gdscript
func setup_ability_slot(ability_id: String, slot_index: int) -> void:
    var ability_button = get_node("AbilityBar/Slot" + str(slot_index))
    ability_button.icon = SpriteRegistry.get_ability_icon(ability_id)
    ability_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
```

---

### Task 6.4: Update ChatPanel Channel Icons
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** Low  
**Dependencies:** Task 6.1

**Description:**
Modify `ChatPanel.gd` to display channel icons next to messages.

**Acceptance Criteria:**
- [ ] Message row template updated to include TextureRect for channel icon
- [ ] Icon retrieved from `SpriteRegistry.get_chat_icon(channel)`
- [ ] Icon size 12x12 pixels
- [ ] `texture_filter` set to TEXTURE_FILTER_NEAREST
- [ ] Icons display to left of message text
- [ ] Different channels show distinct icons (guild, party, system, whisper)

**Traceability:**
- Requirements: Requirement 4 - IF chat panel shows message types
- Design: §6.4 UI Panel Sprite Integration (Chat)

**Code Implementation:**
```gdscript
func add_message(channel: String, sender: String, text: String) -> void:
    var message_row = HBoxContainer.new()
    
    var icon = TextureRect.new()
    icon.custom_minimum_size = Vector2(12, 12)
    icon.texture = SpriteRegistry.get_chat_icon(channel)
    icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    message_row.add_child(icon)
    
    # ... add label with message text
```

---

### Task 6.5: Test UI Icon Display
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** Tasks 6.2, 6.3, 6.4

**Description:**
In-game testing of all UI icon rendering.

**Acceptance Criteria:**
- [ ] Open inventory → all 10 item types display correct 24x24 icons
- [ ] HUD ability bar → 5 abilities show correct 32x32 icons
- [ ] Status effects active → 16x16 status icons visible in HUD
- [ ] Chat messages → 12x12 channel icons display per message type
- [ ] All icons pixel-perfect (no blur artifacts)
- [ ] No missing texture warnings in console

**Traceability:**
- Requirements: Requirement 4 - All Acceptance Criteria
- Design: §10.1 Test 4 - UI Icon Rendering

**Test Checklist:**
- [ ] Inventory: 10 item types visible
- [ ] Abilities: 5 ability icons correct
- [ ] Status: 4 status icons correct
- [ ] Chat: 4 channel types correct

---

## Phase 7: Loot Container Integration

### Task 7.1: Add Loot Sprites to SpriteRegistry
**Status:** ⬜ Not Started  
**Estimated Time:** 0.25 hours  
**Assigned To:** TBD  
**Priority:** Low  
**Dependencies:** Task 4.1, Task 2.3

**Description:**
Populate LOOT_SPRITES dictionary in SpriteRegistry.gd.

**Acceptance Criteria:**
- [ ] LOOT_SPRITES dictionary updated with 3 texture preloads
- [ ] Textures: chest_closed, chest_open, corpse
- [ ] `get_loot_sprite(sprite_type: String)` function implemented
- [ ] No compilation errors

**Traceability:**
- Requirements: Requirement 5 - Loot Container Visual Representation
- Design: §8.2 Sprite Mapping Dictionaries

**Code Addition:**
```gdscript
const LOOT_SPRITES = {
    "chest_closed": preload("res://assets/sprites/entities/loot/loot_chest_closed.png"),
    "chest_open": preload("res://assets/sprites/entities/loot/loot_chest_open.png"),
    "corpse": preload("res://assets/sprites/entities/loot/loot_corpse.png"),
}
```

---

### Task 7.2: Update LootContainer Scene and Script
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** Low  
**Dependencies:** Task 7.1

**Description:**
Modify `LootContainer.tscn` and `LootContainer.gd` to use sprite textures with state management.

**Acceptance Criteria:**
- [ ] LootContainer.tscn updated with Sprite2D node (replace placeholder)
- [ ] `@onready var sprite: Sprite2D = $Sprite2D` added to script
- [ ] `update_sprite()` function implemented
- [ ] Function checks `container_type` (chest vs corpse) and `is_open` state
- [ ] Correct sprite assigned for each state combination
- [ ] `open_container()` function calls `update_sprite()` after state change

**Traceability:**
- Requirements: Requirement 5 - WHEN loot container spawns, IF looted
- Design: §6.5 LootContainer Scene Modifications

**Code Implementation:**
```gdscript
func update_sprite() -> void:
    if container_type == "corpse":
        sprite.texture = SpriteRegistry.get_loot_sprite("corpse")
    else:
        var state = "chest_open" if is_open else "chest_closed"
        sprite.texture = SpriteRegistry.get_loot_sprite(state)
```

---

### Task 7.3: Test Loot Container Sprites
**Status:** ⬜ Not Started  
**Estimated Time:** 0.5 hours  
**Assigned To:** TBD  
**Priority:** Low  
**Dependencies:** Task 7.2

**Description:**
In-game testing of loot container sprite state transitions.

**Acceptance Criteria:**
- [ ] Spawn chest container → closed sprite displays
- [ ] Interact with chest → open sprite displays after looting
- [ ] Spawn corpse loot → corpse sprite displays
- [ ] State transitions smooth (no visual glitches)
- [ ] Sprites render at correct size (32x32 centered)

**Traceability:**
- Requirements: Requirement 5 - All Acceptance Criteria
- Design: §10.1 Test (Loot Containers)

**Test Actions:**
- Spawn multiple chests, loot them, verify sprite changes
- Spawn corpse markers, verify correct sprite

---

## Phase 8: Testing & Polish

### Task 8.1: Performance Stress Test
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** All previous phases

**Description:**
Validate game performance with 200+ entities using sprites.

**Acceptance Criteria:**
- [ ] Spawn 200 entities (150 NPCs, 50 players with sprites)
- [ ] Enable Godot performance overlay (FPS, draw calls, VRAM)
- [ ] Measure FPS: target ≥60 FPS on mid-range hardware
- [ ] Measure draw calls: should be <20 (batched by texture)
- [ ] Measure VRAM usage: sprite textures <50 MB
- [ ] Document results in performance report
- [ ] If FPS <60, profile bottleneck and optimize (consider sprite atlasing)

**Traceability:**
- Requirements: NFR - Performance Requirements
- Design: §9 Performance Considerations, §10.2 Test 5 - Entity Stress Test

**Performance Targets:**
```
FPS: ≥60
Draw Calls: <20
VRAM (Sprites): <50 MB
CPU Frame Time: <16ms
```

---

### Task 8.2: Visual Quality Validation
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** Medium  
**Dependencies:** All previous phases

**Description:**
Verify all sprites render with pixel-perfect quality and no visual artifacts.

**Acceptance Criteria:**
- [ ] Zoom camera to various levels (0.5x, 1x, 2x)
- [ ] Verify pixel edges remain crisp at all zoom levels
- [ ] Check transparency edges (no white halos or dark outlines)
- [ ] Validate color palette consistency across all sprites
- [ ] Confirm contrast sufficient against different background colors
- [ ] Take screenshots for visual documentation

**Traceability:**
- Requirements: NFR - Visual Quality Requirements
- Design: §10 Testing Strategy

**Visual Checks:**
- [ ] Player sprites crisp
- [ ] NPC sprites crisp
- [ ] UI icons crisp
- [ ] No blur artifacts
- [ ] Transparency clean

---

### Task 8.3: Integration Test - Animation State Persistence
**Status:** ⬜ Not Started  
**Estimated Time:** 0.5 hours  
**Assigned To:** TBD  
**Priority:** Low  
**Dependencies:** Task 3.4 (Player integration)

**Description:**
Test that player animations persist correctly across UI interactions.

**Acceptance Criteria:**
- [ ] Move player to trigger walk animation
- [ ] Open inventory (pauses game input)
- [ ] Close inventory
- [ ] Verify animation resumes correctly (walk continues or idle plays)
- [ ] No animation resets, glitches, or stuck frames

**Traceability:**
- Requirements: Requirement 1 - Animation state consistency
- Design: §10.3 Test 7 - Animation State Persistence

---

### Task 8.4: Missing Asset Handling Test
**Status:** ⬜ Not Started  
**Estimated Time:** 0.5 hours  
**Assigned To:** TBD  
**Priority:** Low  
**Dependencies:** All previous phases

**Description:**
Validate graceful handling of missing or incorrectly referenced sprites.

**Acceptance Criteria:**
- [ ] Temporarily rename a sprite file (e.g., `npc_vendor_idle.png` → `npc_vendor_idle_backup.png`)
- [ ] Open Godot editor
- [ ] Verify console warning displayed (not error crash)
- [ ] Check fallback sprite displays (if implemented)
- [ ] Restore file, verify auto-recovery
- [ ] Document behavior for future asset management

**Traceability:**
- Requirements: Requirement 6 - IF sprite resource missing
- Design: §10.4 Test 10 - Missing Asset Handling

---

### Task 8.5: Create Before/After Documentation
**Status:** ⬜ Not Started  
**Estimated Time:** 1 hour  
**Assigned To:** TBD  
**Priority:** Low  
**Dependencies:** All previous phases

**Description:**
Document visual transformation from placeholder ColorRects to sprites.

**Acceptance Criteria:**
- [ ] Capture "before" screenshots (ColorRect placeholders)
- [ ] Capture "after" screenshots (sprite assets applied)
- [ ] Create side-by-side comparison images for:
  - Player entity (idle and walking)
  - NPC types (vendor, quest, hostile)
  - Combat scene with projectiles
  - UI panels (inventory, HUD, chat)
- [ ] Write brief summary of visual improvements
- [ ] Add screenshots to project documentation

**Traceability:**
- Requirements: Business Value - Marketing Readiness
- Design: §11 Implementation Phases

**Screenshot Comparisons:**
- Player: before/after
- NPCs: before/after
- Combat: before/after
- UI: before/after

---

### Task 8.6: Final Bug Fixes and Polish
**Status:** ⬜ Not Started  
**Estimated Time:** 2 hours  
**Assigned To:** TBD  
**Priority:** High  
**Dependencies:** Tasks 8.1-8.5

**Description:**
Address any bugs discovered during testing and apply final polish.

**Acceptance Criteria:**
- [ ] All bugs from test phases documented in issue tracker
- [ ] Critical bugs fixed (crashes, missing sprites, broken animations)
- [ ] Medium-priority bugs fixed (visual glitches, minor performance issues)
- [ ] Low-priority bugs triaged for future work
- [ ] Code reviewed for consistency and quality
- [ ] All scenes saved and tested one final time

**Traceability:**
- Requirements: Success Criteria - Definition of Done
- Design: §11 Implementation Phases - Phase 8

**Bug Triage:**
- Critical: Fix immediately
- Medium: Fix if time permits
- Low: Document for future sprint

---

## Success Metrics

### Definition of Done (All Tasks Complete)
- [ ] All 46 sprite files created and imported into Godot
- [ ] All scenes updated: PlayerEntity, NPCEntity, AbilityProjectile, LootContainer, UI panels
- [ ] SpriteRegistry autoload implemented with all sprite dictionaries populated
- [ ] Player animations (8 total) working correctly
- [ ] NPC type differentiation visible (5 types)
- [ ] Projectile sprites rotating correctly (3 types)
- [ ] UI icons displaying (10 items + 5 abilities + 4 status + 4 chat)
- [ ] No ColorRect placeholder nodes remain in entity/projectile scenes
- [ ] Performance target achieved: ≥60 FPS with 200 entities
- [ ] All import settings configured for pixel-perfect rendering
- [ ] Zero broken texture references in Godot console
- [ ] Documentation complete (README.md, screenshots)

### Acceptance Metrics
- [ ] **Visual Identification:** 95% of playtesters distinguish NPC types without labels (user testing)
- [ ] **Performance Benchmark:** 200+ entities render at 60 FPS (automated test)
- [ ] **Asset Coverage:** 100% of entity types have sprites (inventory check)
- [ ] **Import Success:** Zero missing texture warnings (console validation)

---

## Risk Mitigation Checklist

### Before Starting
- [ ] Godot 4.3+ installed and project opens without errors
- [ ] Sprite generation tools available (AI access or Aseprite installed)
- [ ] Backup created of current project state
- [ ] Team alignment on 16-color palette and visual style

### During Implementation
- [ ] Test sprite imports incrementally (don't wait until all 46 files complete)
- [ ] Validate performance after each phase (catch regressions early)
- [ ] Keep placeholder ColorRect nodes until sprites confirmed working (rollback safety)
- [ ] Commit frequently with descriptive messages (easy rollback points)

### After Completion
- [ ] Tag release version in git
- [ ] Document known issues or future optimizations
- [ ] Archive sprite source files (AI prompts, Aseprite projects)
- [ ] Share before/after screenshots with stakeholders

---

## Appendix: Quick Reference

### File Counts by Category
- Player: 12 files (4 idle + 8 walk frames)
- NPCs: 5 files
- Projectiles: 3 files
- Items: 10 files
- Abilities: 5 files
- Status: 4 files
- Chat: 4 files
- Loot: 3 files
- **Total: 46 sprite files**

### Scenes to Modify
1. `PlayerEntity.tscn` (Phase 3)
2. `NPCEntity.tscn` (Phase 4)
3. `AbilityProjectile.tscn` (Phase 5)
4. `HUD.tscn` (Phase 6)
5. `InventoryPanel.tscn` (Phase 6)
6. `ChatPanel.tscn` (Phase 6)
7. `LootContainer.tscn` (Phase 7)

### Scripts to Modify
1. `PlayerEntity.gd` (Phase 3)
2. `NPCEntity.gd` (Phase 4)
3. `WorldState.gd` (Phase 4)
4. `AbilityProjectile.gd` (Phase 5)
5. `InventoryPanel.gd` (Phase 6)
6. `HUD.gd` (Phase 6)
7. `ChatPanel.gd` (Phase 6)
8. `LootContainer.gd` (Phase 7)
9. `SpriteRegistry.gd` (Phase 4 - NEW FILE)

### New Files to Create
- `SpriteRegistry.gd` (autoload)
- `player_frames.tres` (SpriteFrames resource)
- `assets/sprites/README.md` (documentation)
- 46 PNG sprite files

---

**End of Tasks Document**
