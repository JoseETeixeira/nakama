extends Panel

## InventoryPanel UI
##
## Task: 5.1 - Create Inventory Panel UI
## Task: 5.2 - Create Debug Item Creation Tool
## Requirements: 6 (Inventory Management)
## Design: InventoryPanel.tscn (lines 510-545)
##
## Displays 50 inventory slots in grid layout.
## Handles drag-and-drop item movement with server validation.
## Includes debug item creation tool for development testing.

@onready var item_grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/ItemGrid
@onready var close_button: Button = $MarginContainer/VBoxContainer/Header/CloseButton
@onready var debug_create_button: Button = $MarginContainer/VBoxContainer/Header/DebugCreateButton

# Preload scenes
var item_slot_scene: PackedScene = preload("res://scenes/ui/components/ItemSlot.tscn")
var item_template_dialog_scene: PackedScene = preload("res://scenes/ui/components/ItemTemplateDialog.tscn")

# Inventory size
const INVENTORY_SIZE: int = 50

# Cached inventory slots
var inventory_slots: Array[Node] = []

func _ready() -> void:
	# Create 50 item slots
	create_inventory_slots()

	# Connect to WorldState for inventory updates
	if WorldState:
		if WorldState.has_signal("inventory_updated"):
			WorldState.inventory_updated.connect(_on_inventory_updated)

	# Initially populate from WorldState
	populate_inventory()

	# Hide debug button in non-debug builds
	# Task 5.2 - Only show debug item creation in development builds
	if debug_create_button:
		debug_create_button.visible = OS.is_debug_build()

	# Hide panel initially (will be shown by UIManager)
	visible = false

## Create 50 empty inventory slots
func create_inventory_slots() -> void:
	# Clear existing slots
	for child in item_grid.get_children():
		child.queue_free()

	inventory_slots.clear()

	# Create 50 ItemSlot instances
	for i in range(INVENTORY_SIZE):
		var slot = item_slot_scene.instantiate()
		slot.slot_index = i
		slot.item_dropped.connect(_on_item_dropped)
		item_grid.add_child(slot)
		inventory_slots.append(slot)

## Populate inventory from WorldState
func populate_inventory() -> void:
	if not WorldState:
		return

	# Clear all slots first
	for slot in inventory_slots:
		slot.clear_slot()

	# Get player inventory from WorldState
	var player_inventory = WorldState.player_inventory

	# Populate slots with items
	for item in player_inventory:
		var slot_idx = item.get("slot_index", -1)
		if slot_idx >= 0 and slot_idx < inventory_slots.size():
			inventory_slots[slot_idx].set_item(item)

## Handle item drop between slots
##
## Parameters:
##   from_slot: Source slot index
##   to_slot: Destination slot index
func _on_item_dropped(from_slot: int, to_slot: int) -> void:
	print("[InventoryPanel] Moving item from slot %d to slot %d" % [from_slot, to_slot])

	# Call inventory_move RPC
	if not NakamaManager:
		push_error("[InventoryPanel] NakamaManager not available")
		return

	if not NakamaManager.has_method("inventory_move"):
		push_error("[InventoryPanel] NakamaManager.inventory_move method not found")
		# For now, optimistically update local state
		_optimistic_move(from_slot, to_slot)
		return

	# Optimistically update UI
	_optimistic_move(from_slot, to_slot)

	# Call RPC
	var result = await NakamaManager.inventory_move(from_slot, to_slot)

	if not result or not result.get("success", false):
		# RPC failed, revert UI
		print("[InventoryPanel] inventory_move RPC failed, reverting UI")
		populate_inventory()

		# Show error message
		var error_message = "Failed to move item"
		if result and result.has("error"):
			error_message = result.error

		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error(error_message)

## Optimistically update UI before RPC response
##
## Parameters:
##   from_slot: Source slot index
##   to_slot: Destination slot index
func _optimistic_move(from_slot: int, to_slot: int) -> void:
	if from_slot < 0 or from_slot >= inventory_slots.size():
		return
	if to_slot < 0 or to_slot >= inventory_slots.size():
		return

	# Get items from both slots
	var from_item = inventory_slots[from_slot].item_data.duplicate()
	var to_item = inventory_slots[to_slot].item_data.duplicate()

	# Swap slot indices in item data
	if not from_item.is_empty():
		from_item["slot_index"] = to_slot
	if not to_item.is_empty():
		to_item["slot_index"] = from_slot

	# Update UI
	inventory_slots[to_slot].set_item(from_item)
	inventory_slots[from_slot].set_item(to_item)

	# Update WorldState locally (will be overwritten by server delta if wrong)
	if WorldState:
		_update_worldstate_inventory(from_slot, to_slot)

## Update WorldState.player_inventory array
##
## Parameters:
##   from_slot: Source slot index
##   to_slot: Destination slot index
func _update_worldstate_inventory(from_slot: int, to_slot: int) -> void:
	var inventory = WorldState.player_inventory

	# Find items in these slots
	var from_item_idx = -1
	var to_item_idx = -1

	for i in range(inventory.size()):
		var item = inventory[i]
		if item.get("slot_index") == from_slot:
			from_item_idx = i
		if item.get("slot_index") == to_slot:
			to_item_idx = i

	# Swap slot indices
	if from_item_idx >= 0:
		inventory[from_item_idx]["slot_index"] = to_slot
	if to_item_idx >= 0:
		inventory[to_item_idx]["slot_index"] = from_slot

## Handle inventory update from WorldState
func _on_inventory_updated() -> void:
	print("[InventoryPanel] Inventory updated from server")
	populate_inventory()

## Handle debug create button click
## Task 5.2 - Create Debug Item Creation Tool
func _on_debug_create_button_pressed() -> void:
	# Only allow in debug builds
	if not OS.is_debug_build():
		print("[InventoryPanel] Debug item creation disabled in release builds")
		return

	# Create and show item template dialog
	var dialog = item_template_dialog_scene.instantiate()
	add_child(dialog)

	# Connect to template selection
	dialog.template_selected.connect(_on_item_template_selected)

	# Show dialog
	dialog.popup_centered()

## Handle item template selection from debug dialog
## Task 5.2 - Create Debug Item Creation Tool
##
## Parameters:
##   template_id: ID of item template to create
func _on_item_template_selected(template_id: String) -> void:
	print("[InventoryPanel] Creating item from template: %s" % template_id)

	if not NakamaManager:
		push_error("[InventoryPanel] NakamaManager not available")
		return

	if not NakamaManager.has_method("inventory_create_item"):
		push_error("[InventoryPanel] NakamaManager.inventory_create_item method not found")
		# For now, show error message
		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error("inventory_create_item RPC not implemented yet")
		return

	# Call RPC to create item
	var result = await NakamaManager.inventory_create_item(template_id)

	if result and result.get("success", false):
		print("[InventoryPanel] Item created successfully: %s" % result.get("item_id", ""))

		# Inventory will be updated via WorldState.inventory_updated signal
		# which triggers populate_inventory()

		# Show success message
		if UIManager and UIManager.has_method("show_message"):
			var item_name = result.get("name", template_id)
			UIManager.show_message("Created: %s" % item_name)
	else:
		# Show error message
		var error_message = "Failed to create item"
		if result and result.has("error"):
			error_message = result.error

		print("[InventoryPanel] Item creation failed: %s" % error_message)

		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error(error_message)
	populate_inventory()

## Handle close button
func _on_close_button_pressed() -> void:
	if UIManager and UIManager.has_method("hide_panel"):
		UIManager.hide_panel("inventory")
	else:
		visible = false
