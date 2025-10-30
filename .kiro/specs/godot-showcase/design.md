# Technical Design: Godot MMORPG Showcase Project

## Document Information

- **Feature Name:** Godot MMORPG Showcase Project
- **Version:** 1.0
- **Date:** October 29, 2025
- **Status:** In Design
- **Requirements Reference:** `.kiro/specs/godot-showcase/requirements.md`

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Components](#system-components)
3. [Scene Structure](#scene-structure)
4. [Autoload Singletons](#autoload-singletons)
5. [Entity Management](#entity-management)
6. [Network Communication](#network-communication)
7. [UI System](#ui-system)
8. [Data Models](#data-models)
9. [State Management](#state-management)
10. [Testing Strategy](#testing-strategy)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Godot 4 Showcase Client                      │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  Scene Layer                                              │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │ │
│  │  │ Login    │  │Character │  │  World   │               │ │
│  │  │ Screen   │→ │ Select   │→ │  Scene   │               │ │
│  │  └──────────┘  └──────────┘  └──────────┘               │ │
│  │                                    │                      │ │
│  │                                    ▼                      │ │
│  │                          ┌─────────────────┐             │ │
│  │                          │ UI Overlays     │             │ │
│  │                          │ - HUD           │             │ │
│  │                          │ - Inventory     │             │ │
│  │                          │ - Chat          │             │ │
│  │                          │ - Guild Panel   │             │ │
│  │                          │ - Debug Overlay │             │ │
│  │                          └─────────────────┘             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  Autoload Singletons (Global Access)                     │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │ │
│  │  │ NakamaManager│  │  WorldState  │  │   UIManager  │   │ │
│  │  │              │  │              │  │              │   │ │
│  │  │ - Auth       │  │ - Entities   │  │ - Panels     │   │ │
│  │  │ - RPCs       │  │ - Snapshot   │  │ - Dialogs    │   │ │
│  │  │ - Session    │  │ - Deltas     │  │ - Tooltips   │   │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  Entity System                                            │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │ │
│  │  │  Player  │  │   NPC    │  │  Loot    │               │ │
│  │  │  Entity  │  │  Entity  │  │Container │               │ │
│  │  └──────────┘  └──────────┘  └──────────┘               │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ WebSocket/gRPC
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Nakama Server                               │
│  - Authentication (JWT)                                         │
│  - 29 RPC Endpoints                                             │
│  - Delta Stream (Match Data)                                    │
│  - Chat Channels                                                │
└─────────────────────────────────────────────────────────────────┘
```

### Design Principles

**Requirements: 1-13**

1. **Single Responsibility**: Each script/scene handles one concern (Req 1-13)
2. **Server Trust**: Never trust client state; server is authoritative (Req 3, 5)
3. **Reactive UI**: UI responds to state changes, not direct manipulation (Req 6, 7, 10, 11)
4. **Predictive Client**: Apply optimistic updates, reconcile with server (Req 3)
5. **Testability**: RPC calls abstracted for easy testing (Req 1-11)

---

## System Components

### Component Overview

| Component | Responsibility | Requirements |
|-----------|----------------|--------------|
| **NakamaManager** | Authentication, RPC calls, session management | 1, 2, 5-11 |
| **WorldState** | Entity state, snapshot/delta processing | 2, 3, 4, 12 |
| **UIManager** | Panel visibility, dialog management | All |
| **Player Entity** | Local player rendering, input handling | 3 |
| **NPC Entity** | Remote entity rendering, interpolation | 4, 12 |
| **InventoryUI** | Item display, drag-drop operations | 6, 7 |
| **ChatUI** | Message display, input handling | 11 |
| **GuildUI** | Guild roster, rank management | 10 |
| **DebugOverlay** | Diagnostic information display | 13 |

---

## Scene Structure

### Scene Hierarchy

```
godot_project/
├── scenes/
│   ├── auth/
│   │   ├── LoginScreen.tscn          # Requirement 1
│   │   └── CharacterSelect.tscn      # Requirement 1
│   │
│   ├── world/
│   │   ├── World.tscn                # Main game scene (Req 2-13)
│   │   │   └── Camera2D              # Player-centered camera
│   │   │   └── CanvasLayer           # UI overlays
│   │   │       ├── HUD.tscn
│   │   │       ├── InventoryPanel.tscn
│   │   │       ├── ChatPanel.tscn
│   │   │       ├── GuildPanel.tscn
│   │   │       ├── VendorPanel.tscn
│   │   │       ├── TradePanel.tscn
│   │   │       └── DebugOverlay.tscn
│   │   │
│   │   └── entities/
│   │       ├── PlayerEntity.tscn     # Local player (Req 3)
│   │       ├── RemotePlayer.tscn     # Other players (Req 4)
│   │       ├── NPCEntity.tscn        # NPCs (Req 12)
│   │       └── LootContainer.tscn    # Loot drops (Req 9)
│   │
│   └── ui/
│       ├── components/
│       │   ├── ItemSlot.tscn         # Reusable item slot
│       │   ├── AbilityButton.tscn    # Ability hotbar button
│       │   ├── HealthBar.tscn        # Entity health display
│       │   └── ChatMessage.tscn      # Chat message entry
│       │
│       └── dialogs/
│           ├── ConfirmDialog.tscn
│           ├── ErrorDialog.tscn
│           └── LoadingDialog.tscn
```

### Scene Responsibilities

**LoginScreen.tscn** (Requirement 1)
- Device ID authentication button
- Error message display
- Transition to character select

**CharacterSelect.tscn** (Requirement 1)
- Character list display (from `list_characters` RPC)
- Create character button → character creation form
- Select character → `select_character` RPC → world entry
- Delete character button → confirmation → `delete_character` RPC

**World.tscn** (Requirements 2-13)
- Main gameplay container
- Entity spawning/despawning
- Camera follow player
- UI overlay management

---

## Autoload Singletons

### NakamaManager (`autoload/NakamaManager.gd`)

**Purpose**: Central interface for all Nakama server communication

**Responsibilities:**
- Authenticate users (Requirement 1)
- Manage session state and token refresh
- Provide RPC wrapper functions with error handling
- Subscribe to match data for delta streams (Requirement 4)
- Emit signals for async operation results

**Key Functions:**

```gdscript
# Authentication (Requirement 1)
func authenticate_device(device_id: String) -> void
signal authentication_completed(session: NakamaSession)
signal authentication_failed(error: String)

# Character RPCs (Requirement 1)
func list_characters() -> Array
func create_character(name: String, class_type: String) -> Dictionary
func select_character(character_id: String) -> Dictionary
func delete_character(character_id: String) -> bool

# World RPCs (Requirement 2, 3)
func world_enter(character_id: String) -> Dictionary
func move_intent(position: Vector2, velocity: Vector2) -> void
func zone_snapshot(zone_id: String) -> Dictionary

# Combat RPCs (Requirement 5)
func use_ability(ability_id: String, target_id: String, position: Vector2) -> Dictionary

# Economy RPCs (Requirement 6, 7, 8, 9)
func inventory_move(from_slot: int, to_slot: int) -> bool
func inventory_create_item(item_template_id: String) -> Dictionary
func trade_open(target_player_id: String) -> String  # Returns trade_session_id
func trade_add_item(session_id: String, item_id: String) -> bool
func trade_lock(session_id: String) -> bool
func trade_commit(session_id: String) -> bool
func trade_cancel(session_id: String) -> bool
func get_vendor_catalog(vendor_id: String) -> Array
func vendor_buy(vendor_id: String, item_id: String) -> bool
func vendor_sell(vendor_id: String, item_id: String) -> Dictionary
func generate_loot(npc_template_id: String) -> Array

# Social RPCs (Requirement 10, 11)
func guild_create(name: String, tag: String) -> Dictionary
func guild_invite(player_id: String) -> bool
func guild_join(guild_id: String) -> bool
func guild_set_rank(member_id: String, rank_id: int) -> bool
func guild_kick(member_id: String) -> bool
func guild_set_motd(message: String) -> bool
func guild_storage_deposit(item_id: String) -> bool
func guild_storage_withdraw(item_id: String) -> bool
func chat_send(message: String, channel: String) -> bool
func send_direct_message(recipient_id: String, message: String) -> bool
func moderate_player(target_id: String, action: String) -> bool

# Delta Stream (Requirement 4)
func subscribe_to_delta_stream(zone_id: String) -> void
signal delta_received(delta_data: Dictionary)
```

**State:**
- `session: NakamaSession` - Current authenticated session
- `client: NakamaClient` - Nakama client instance
- `socket: NakamaSocket` - WebSocket connection for real-time
- `match_id: String` - Current zone match ID for delta stream

---

### WorldState (`autoload/WorldState.gd`)

**Purpose**: Maintain client-side world state and entity registry

**Responsibilities:**
- Store and update entity states (Requirement 2, 4, 12)
- Process snapshot data from `zone_snapshot` RPC (Requirement 2)
- Process delta updates from match data (Requirement 4)
- Spawn/despawn entity nodes (Requirement 4, 12)
- Provide entity lookup by ID

**Key Functions:**

```gdscript
# Snapshot Processing (Requirement 2)
func load_snapshot(snapshot_data: Dictionary) -> void
func decompress_snapshot(compressed: PackedByteArray) -> Dictionary
func spawn_entities_from_snapshot(entities: Array) -> void

# Delta Processing (Requirement 4)
func apply_delta(delta_data: Dictionary) -> void
func decompress_delta(compressed: PackedByteArray) -> Dictionary
func update_entity(entity_id: String, data: Dictionary) -> void
func spawn_entity(entity_id: String, data: Dictionary) -> void
func despawn_entity(entity_id: String) -> void

# Entity Registry
func get_entity(entity_id: String) -> Node2D
func get_all_entities() -> Array
func get_entities_in_radius(position: Vector2, radius: float) -> Array

# Player State
var player_entity_id: String
var player_position: Vector2
var player_health: float
var player_mana: float
var player_inventory: Array  # Array of item dictionaries

# Signals
signal entity_spawned(entity_id: String, node: Node2D)
signal entity_despawned(entity_id: String)
signal entity_updated(entity_id: String, data: Dictionary)
signal snapshot_loaded()
signal delta_applied(delta_size: int, entities_updated: int)
```

**State:**
- `entities: Dictionary` - Map of entity_id → Node2D instances
- `entity_data: Dictionary` - Map of entity_id → entity state data
- `current_zone_id: String` - Active zone identifier
- `last_snapshot_time: int` - Timestamp of last snapshot load
- `delta_stats: Dictionary` - Delta metrics for debugging (Req 13)

---

### UIManager (`autoload/UIManager.gd`)

**Purpose**: Manage UI panel visibility and dialog flows

**Responsibilities:**
- Show/hide UI panels (inventory, chat, guild, etc.)
- Display modal dialogs (confirm, error, loading)
- Manage tooltip display
- Handle UI input focus

**Key Functions:**

```gdscript
# Panel Management
func show_panel(panel_name: String) -> void
func hide_panel(panel_name: String) -> void
func toggle_panel(panel_name: String) -> void
func close_all_panels() -> void

# Dialogs
func show_error(message: String) -> void
func show_confirm(message: String, callback: Callable) -> void
func show_loading(message: String) -> void
func hide_loading() -> void

# Tooltips (Requirement 6)
func show_tooltip(item_data: Dictionary, position: Vector2) -> void
func hide_tooltip() -> void

# Signals
signal panel_opened(panel_name: String)
signal panel_closed(panel_name: String)
```

---

## Entity Management

### Entity Types

**PlayerEntity** (Local Player - Requirement 3)

```gdscript
extends CharacterBody2D

# Input Handling
func _process(delta: float) -> void:
    handle_movement_input()
    handle_ability_input()

func handle_movement_input() -> void:
    var input_vector = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    if input_vector.length() > 0:
        # Client-side prediction
        velocity = input_vector * MOVE_SPEED
        move_and_slide()

        # Send to server
        NakamaManager.move_intent(global_position, velocity)

# Server Reconciliation (Requirement 3)
func apply_server_position(server_pos: Vector2) -> void:
    var distance = global_position.distance_to(server_pos)
    if distance > SNAP_THRESHOLD:
        # Snap to server position
        global_position = server_pos
    elif distance > INTERPOLATE_THRESHOLD:
        # Smooth interpolation
        global_position = global_position.lerp(server_pos, 0.3)

# Ability Usage (Requirement 5)
func use_ability(ability_id: String, target_id: String) -> void:
    var result = await NakamaManager.use_ability(ability_id, target_id, global_position)
    if result.success:
        play_ability_animation(ability_id)
        if result.cooldown > 0:
            start_ability_cooldown(ability_id, result.cooldown)
```

**RemotePlayer / NPCEntity** (Other Entities - Requirement 4, 12)

```gdscript
extends CharacterBody2D

var entity_id: String
var entity_data: Dictionary
var target_position: Vector2
var interpolation_speed: float = 10.0

# Delta Update Handling (Requirement 4)
func apply_delta_update(data: Dictionary) -> void:
    if "position" in data:
        target_position = Vector2(data.position.x, data.position.y)

    if "health" in data:
        update_health_bar(data.health, data.max_health)

    if "state" in data:
        update_animation_state(data.state)

# Smooth Interpolation (Requirement 4)
func _process(delta: float) -> void:
    if global_position.distance_to(target_position) > 1.0:
        global_position = global_position.move_toward(target_position, interpolation_speed * delta)

# NPC Interaction (Requirement 12)
func _on_input_event(viewport, event, shape_idx):
    if event is InputEventMouseButton and event.pressed:
        show_interaction_menu()

func show_interaction_menu():
    var menu_items = []
    if entity_data.is_vendor:
        menu_items.append("Trade")
    if entity_data.is_enemy:
        menu_items.append("Attack")
    UIManager.show_context_menu(menu_items, global_position)
```

**LootContainer** (Requirement 9)

```gdscript
extends Node2D

var loot_items: Array = []
var container_id: String

func initialize(loot_data: Array):
    loot_items = loot_data
    update_visual()

func _on_clicked():
    UIManager.show_panel("loot_panel")
    get_node("/root/World/UI/LootPanel").display_loot(loot_items, container_id)

func take_item(item_id: String):
    loot_items = loot_items.filter(func(item): return item.id != item_id)
    if loot_items.is_empty():
        queue_free()  # Despawn container
```

---

## Network Communication

### RPC Call Pattern

All RPC calls follow this pattern:

```gdscript
# In NakamaManager.gd
func <rpc_name>(params...) -> Variant:
    if not session or session.is_expired():
        emit_signal("authentication_required")
        return null

    var payload = {
        # RPC-specific parameters
    }

    try:
        var result = await client.rpc_async(session, "<rpc_name>", JSON.stringify(payload))
        var data = JSON.parse_string(result.payload)

        if "error" in data:
            emit_signal("rpc_error", "<rpc_name>", data.error)
            return null

        return data
    except:
        emit_signal("rpc_error", "<rpc_name>", "Network error")
        return null
```

### Delta Stream Subscription (Requirement 4)

```gdscript
# In NakamaManager.gd
func subscribe_to_delta_stream(zone_id: String) -> void:
    # Join match for delta stream
    var result = await socket.join_match_async(zone_id)
    match_id = result.match_id

    # Listen for match data
    socket.received_match_state.connect(_on_match_state)

func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
    var delta_data = JSON.parse_string(state.data)

    # Decompress if needed
    if delta_data.compressed:
        delta_data = WorldState.decompress_delta(delta_data.payload)

    # Apply delta
    WorldState.apply_delta(delta_data)
    emit_signal("delta_received", delta_data)
```

---

## UI System

### Inventory UI (Requirement 6)

**InventoryPanel.tscn**

```gdscript
extends Panel

@onready var item_grid = $GridContainer

func _ready():
    populate_inventory()
    WorldState.connect("entity_updated", _on_entity_updated)

func populate_inventory():
    # Clear existing slots
    for child in item_grid.get_children():
        child.queue_free()

    # Create 50 item slots
    for i in range(50):
        var slot = preload("res://scenes/ui/components/ItemSlot.tscn").instantiate()
        slot.slot_index = i
        slot.connect("item_dropped", _on_item_dropped)
        item_grid.add_child(slot)

    # Populate with items
    for item in WorldState.player_inventory:
        var slot = item_grid.get_child(item.slot_index)
        slot.set_item(item)

func _on_item_dropped(from_slot: int, to_slot: int):
    var success = await NakamaManager.inventory_move(from_slot, to_slot)
    if not success:
        # Revert UI
        populate_inventory()
```

**ItemSlot.tscn** (Drag-and-Drop)

```gdscript
extends Control

var slot_index: int
var item_data: Dictionary
signal item_dropped(from_slot: int, to_slot: int)

func _get_drag_data(position):
    if item_data.is_empty():
        return null

    # Create drag preview
    var preview = TextureRect.new()
    preview.texture = load(item_data.icon)
    set_drag_preview(preview)

    return { "slot_index": slot_index, "item": item_data }

func _can_drop_data(position, data):
    return data is Dictionary and "slot_index" in data

func _drop_data(position, data):
    emit_signal("item_dropped", data.slot_index, slot_index)

func set_item(item: Dictionary):
    item_data = item
    $Icon.texture = load(item.icon)
    $StackCount.text = str(item.stack_count) if item.stack_count > 1 else ""
    $Rarity.modulate = get_rarity_color(item.rarity)

# Tooltip (Requirement 6)
func _on_mouse_entered():
    if not item_data.is_empty():
        UIManager.show_tooltip(item_data, global_position)

func _on_mouse_exited():
    UIManager.hide_tooltip()
```

### Trade UI (Requirement 7)

**TradePanel.tscn**

```gdscript
extends Panel

var trade_session_id: String
var my_items: Array = []
var their_items: Array = []
var my_locked: bool = false
var their_locked: bool = false

func open_trade(target_player_id: String):
    trade_session_id = await NakamaManager.trade_open(target_player_id)
    if trade_session_id:
        show()

func _on_item_added_to_trade(item_id: String):
    var success = await NakamaManager.trade_add_item(trade_session_id, item_id)
    if success:
        my_items.append(item_id)
        update_trade_display()

func _on_lock_pressed():
    var success = await NakamaManager.trade_lock(trade_session_id)
    if success:
        my_locked = true
        $LockButton.disabled = true
        check_commit_ready()

func check_commit_ready():
    $CommitButton.disabled = not (my_locked and their_locked)

func _on_commit_pressed():
    var success = await NakamaManager.trade_commit(trade_session_id)
    if success:
        UIManager.show_error("Trade completed successfully!")
        close_trade()
    else:
        UIManager.show_error("Trade failed. Items returned.")

func _on_cancel_pressed():
    await NakamaManager.trade_cancel(trade_session_id)
    close_trade()
```

### Chat UI (Requirement 11)

**ChatPanel.tscn**

```gdscript
extends Panel

@onready var message_list = $VBox/MessageList
@onready var input_field = $VBox/InputField
@onready var tab_container = $VBox/TabContainer

func _ready():
    NakamaManager.socket.received_channel_message.connect(_on_channel_message)

func _on_send_pressed():
    var message = input_field.text
    if message.is_empty():
        return

    var channel = get_current_channel()

    if message.starts_with("/whisper"):
        var parts = message.split(" ", true, 2)
        if parts.size() >= 3:
            await NakamaManager.send_direct_message(parts[1], parts[2])
    else:
        await NakamaManager.chat_send(message, channel)

    input_field.text = ""

func _on_channel_message(message: NakamaAPI.ApiChannelMessage):
    add_message_to_tab(message.channel_id, message.username, message.content)

func add_message_to_tab(channel: String, sender: String, content: String):
    var msg_node = preload("res://scenes/ui/components/ChatMessage.tscn").instantiate()
    msg_node.set_message(sender, content, Time.get_unix_time_from_system())

    var tab = get_tab_for_channel(channel)
    tab.add_child(msg_node)

    # Auto-scroll to bottom
    await get_tree().process_frame
    tab.scroll_vertical = tab.get_v_scroll_bar().max_value
```

### Guild UI (Requirement 10)

**GuildPanel.tscn**

```gdscript
extends Panel

@onready var roster_list = $TabContainer/Roster/List
@onready var motd_label = $TabContainer/Info/MOTD
@onready var storage_grid = $TabContainer/Storage/Grid

var guild_data: Dictionary

func _ready():
    refresh_guild_data()

func refresh_guild_data():
    # Guild data is part of character state
    guild_data = WorldState.player_guild_data
    update_display()

func _on_invite_pressed():
    var target_id = $InviteDialog/PlayerIDInput.text
    var success = await NakamaManager.guild_invite(target_id)
    if success:
        UIManager.show_error("Invite sent!")

func _on_set_rank_pressed(member_id: String, rank_id: int):
    var success = await NakamaManager.guild_set_rank(member_id, rank_id)
    if success:
        refresh_guild_data()

func _on_motd_save_pressed():
    var new_motd = $TabContainer/Info/MOTDInput.text
    var success = await NakamaManager.guild_set_motd(new_motd)
    if success:
        motd_label.text = new_motd

func _on_storage_deposit(item_id: String):
    var success = await NakamaManager.guild_storage_deposit(item_id)
    if success:
        refresh_guild_data()

func _on_storage_withdraw(item_id: String):
    var success = await NakamaManager.guild_storage_withdraw(item_id)
    if success:
        refresh_guild_data()
```

### Debug Overlay (Requirement 13)

**DebugOverlay.tscn**

```gdscript
extends CanvasLayer

@onready var fps_label = $Panel/VBox/FPS
@onready var latency_label = $Panel/VBox/Latency
@onready var entity_count_label = $Panel/VBox/EntityCount
@onready var delta_stats_label = $Panel/VBox/DeltaStats
@onready var network_log = $Panel/VBox/NetworkLog

var visible_debug: bool = false

func _ready():
    visible = false
    WorldState.connect("delta_applied", _on_delta_applied)
    NakamaManager.connect("rpc_called", _on_rpc_called)

func _process(delta):
    if Input.is_action_just_pressed("ui_f3"):
        visible_debug = not visible_debug
        visible = visible_debug

    if visible_debug:
        update_stats()

func update_stats():
    fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
    latency_label.text = "Latency: %d ms" % NakamaManager.get_latency()
    entity_count_label.text = "Entities: %d" % WorldState.get_all_entities().size()

    var stats = WorldState.delta_stats
    delta_stats_label.text = "Delta: %d bytes, %d entities" % [stats.last_size, stats.last_entity_count]

func _on_delta_applied(delta_size: int, entities_updated: int):
    add_log_entry("[DELTA] Size: %d bytes, Updated: %d entities" % [delta_size, entities_updated])

func _on_rpc_called(rpc_name: String, success: bool):
    var status = "✓" if success else "✗"
    add_log_entry("[RPC] %s %s" % [status, rpc_name])

func add_log_entry(message: String):
    network_log.text += "\n" + message
    # Keep last 50 lines
    var lines = network_log.text.split("\n")
    if lines.size() > 50:
        network_log.text = "\n".join(lines.slice(-50))
```

---

## Data Models

### Entity Data Structure

```gdscript
# Entity state from snapshot/delta
{
    "id": "entity_12345",
    "type": "player" | "npc" | "resource_node",
    "position": { "x": 100.0, "y": 200.0 },
    "velocity": { "x": 50.0, "y": 0.0 },
    "health": 80.0,
    "max_health": 100.0,
    "mana": 50.0,
    "max_mana": 100.0,
    "name": "PlayerName",
    "level": 10,
    "state": "idle" | "walking" | "attacking",
    "metadata": {
        "is_vendor": false,
        "is_enemy": true,
        "npc_template_id": "goblin_warrior"
    }
}
```

### Item Data Structure

```gdscript
# Item from inventory
{
    "id": "item_67890",
    "template_id": "sword_iron",
    "name": "Iron Sword",
    "icon": "res://assets/items/sword_iron.png",
    "rarity": "common" | "uncommon" | "rare" | "epic" | "legendary",
    "slot_index": 5,
    "stack_count": 1,
    "stats": {
        "damage": 25,
        "attack_speed": 1.2
    },
    "description": "A basic iron sword."
}
```

### Ability Data Structure

```gdscript
# Ability result from use_ability RPC
{
    "success": true,
    "ability_id": "fireball",
    "damage_dealt": 45,
    "critical": false,
    "effects": [
        { "type": "damage", "value": 45, "element": "fire" },
        { "type": "burn", "duration": 5.0, "tick_damage": 5 }
    ],
    "cooldown": 3.0,
    "mana_cost": 25,
    "targets_hit": ["entity_12346"]
}
```

---

## State Management

### Application State Machine

```
┌──────────────┐
│ Disconnected │
└──────┬───────┘
       │ authenticate_device()
       ▼
┌──────────────┐
│ Authenticated│
└──────┬───────┘
       │ list_characters()
       ▼
┌──────────────┐
│CharacterSelect│
└──────┬───────┘
       │ select_character()
       ▼
┌──────────────┐
│ WorldEntry   │
└──────┬───────┘
       │ world_enter() + zone_snapshot()
       ▼
┌──────────────┐
│   InWorld    │◄──┐
└──────┬───────┘   │
       │           │ Delta updates
       └───────────┘
```

### State Transitions

Managed by scene changes and NakamaManager signals:

```gdscript
# In main scene controller
func _ready():
    NakamaManager.authentication_completed.connect(_on_authenticated)
    NakamaManager.world_entered.connect(_on_world_entered)

func _on_authenticated(session):
    get_tree().change_scene_to_file("res://scenes/auth/CharacterSelect.tscn")

func _on_character_selected(character_id):
    var result = await NakamaManager.select_character(character_id)
    if result:
        var world_data = await NakamaManager.world_enter(character_id)
        if world_data:
            get_tree().change_scene_to_file("res://scenes/world/World.tscn")

func _on_world_entered(zone_data):
    var snapshot = await NakamaManager.zone_snapshot(zone_data.zone_id)
    WorldState.load_snapshot(snapshot)
    NakamaManager.subscribe_to_delta_stream(zone_data.zone_id)
```

---

## Testing Strategy

### Unit Testing

**Tools**: GUT (Godot Unit Testing) framework

**Test Coverage:**
- NakamaManager RPC functions with mocked server responses
- WorldState snapshot/delta processing with sample data
- Entity interpolation logic
- Inventory drag-and-drop validation

**Example Test:**

```gdscript
extends GutTest

var nakama_manager: NakamaManager

func before_each():
    nakama_manager = NakamaManager.new()
    add_child_autofree(nakama_manager)

func test_inventory_move_success():
    # Mock RPC response
    nakama_manager.mock_rpc_response("inventory_move", { "success": true })

    var result = await nakama_manager.inventory_move(0, 5)
    assert_true(result)

func test_delta_decompression():
    var compressed = load_test_delta()
    var decompressed = WorldState.decompress_delta(compressed)

    assert_has(decompressed, "entities")
    assert_typeof(decompressed.entities, TYPE_ARRAY)
```

### Integration Testing

**Approach**: Manual testing with local Nakama server

**Test Scenarios:**
1. Complete authentication → character creation → world entry flow
2. Movement synchronization with multiple clients
3. Combat ability usage with validation errors
4. Full trading workflow between two clients
5. Guild operations (create, invite, storage)
6. Chat message delivery across channels

### Performance Testing

**Metrics to Track:**
- FPS with 100+ entities in scene
- Delta processing time (should be <10ms)
- Snapshot load time (should be <100ms)
- Memory usage over 30-minute session

**Tools:**
- Godot profiler
- Custom debug overlay (Requirement 13)

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- Authentication and character selection UI
- Basic world scene with camera
- NakamaManager RPC wrappers (all 29 RPCs)
- WorldState snapshot loading

### Phase 2: Core Gameplay (Weeks 3-4)
- Player movement and prediction
- Delta stream processing
- Entity spawning/despawning
- Basic HUD

### Phase 3: Combat & Economy (Weeks 5-6)
- Ability system with targeting
- Inventory UI with drag-and-drop
- Vendor interactions
- Loot generation

### Phase 4: Social Features (Weeks 7-8)
- Chat system (zone, whisper, guild)
- Guild UI and operations
- Trading UI with 2PC flow

### Phase 5: Polish & Debug (Week 9)
- Debug overlay and diagnostics
- Error handling improvements
- Performance optimization
- Integration testing

---

## Security Considerations

1. **Never trust client data**: All validation occurs server-side (combat, inventory, trading)
2. **Token management**: Securely store session tokens, refresh before expiration
3. **Input sanitization**: Validate all user input before sending to server (chat, character names)
4. **Rate limiting awareness**: Respect server rate limits on RPCs to avoid rejection

---

## Future Enhancements

- **3D Support**: Extend to 3D worlds with same RPC infrastructure
- **Mobile Controls**: Touch input for movement and abilities
- **Audio System**: Sound effects for abilities, UI interactions
- **Advanced Animations**: Skeletal animations for entities
- **Minimap**: Zone overview with entity indicators

---

## Glossary

Same as requirements.md glossary.

---

## Design Review Checklist

**Completeness**
- ✅ All 13 requirements mapped to components
- ✅ All 29 RPCs have wrapper functions
- ✅ UI scenes defined for each requirement
- ✅ State management flow documented

**Feasibility**
- ✅ Godot 4 capabilities support all features
- ✅ nakama-godot SDK provides needed APIs
- ✅ Performance targets achievable with design
- ✅ No blocking technical constraints identified

**Maintainability**
- ✅ Clear separation of concerns (autoloads, scenes, scripts)
- ✅ Reusable UI components
- ✅ Consistent patterns for RPC calls and state updates
- ✅ Testing strategy defined

**Traceability**
- ✅ Each component references requirements it fulfills
- ✅ Scene hierarchy aligns with requirement groupings
- ✅ Data models support all RPC contracts
