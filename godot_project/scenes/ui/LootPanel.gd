extends Panel

## LootPanel UI
##
## Task: 5.5 - Implement Loot Container System
## Requirements: 9 (Loot Generation and Drops)
## Design: LootPanel display pattern (lines 439-445)
##
## Displays loot items from container with rarity colors.
## Handles item pickup and inventory full errors.

# References to UI nodes
@onready var title_label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var info_label = $MarginContainer/VBoxContainer/InfoLabel
@onready var loot_grid = $MarginContainer/VBoxContainer/LootScrollContainer/LootGrid
@onready var take_all_button = $MarginContainer/VBoxContainer/ButtonContainer/TakeAllButton

# Loot state
var loot_items: Array = []
var loot_container_ref: Node = null
var loot_slots: Array[Node] = []

# ItemSlot preload
const ITEM_SLOT_SCENE = preload("res://scenes/ui/components/ItemSlot.tscn")

func _ready():
	pass

func display_loot(items: Array, container: Node):
	"""Display loot items from container"""
	loot_items = items.duplicate()
	loot_container_ref = container

	# Update title
	var item_count = loot_items.size()
	title_label.text = "Loot Container (%d item%s)" % [item_count, "s" if item_count != 1 else ""]

	# Populate loot grid
	populate_loot_grid()

	# Show panel
	visible = true

func populate_loot_grid():
	"""Display loot items in grid with rarity colors"""
	# Clear existing slots
	for slot in loot_slots:
		slot.queue_free()
	loot_slots.clear()

	# Create ItemSlot for each loot item
	for item_data in loot_items:
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.custom_minimum_size = Vector2(48, 48)

		# Set item display
		slot.set_item(item_data)

		# Connect gui_input for click to take
		if not slot.gui_input.is_connected(_on_loot_item_gui_input):
			slot.gui_input.connect(_on_loot_item_gui_input.bind(item_data))

		loot_grid.add_child(slot)
		loot_slots.append(slot)

	# Update info label
	if loot_items.is_empty():
		info_label.text = "Container is empty"
		take_all_button.disabled = true
	else:
		info_label.text = "Click items to take them"
		take_all_button.disabled = false

func _on_loot_item_gui_input(event: InputEvent, item_data: Dictionary):
	"""Handle click on loot item to take it"""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			take_item(item_data)

func take_item(item_data: Dictionary):
	"""Take single item from loot container"""
	var item_id = item_data.get("id", "")

	# Check if inventory has space
	if not has_inventory_space():
		UIManager.show_error("Inventory Full! Cannot take item.")
		return

	# Add to player inventory (simulated - in real implementation, this would call an RPC)
	# For now, we'll add directly to WorldState
	if "player_inventory" in WorldState:
		# Find empty slot
		var empty_slot = find_empty_inventory_slot()
		if empty_slot >= 0:
			# Add item to inventory
			var new_item = item_data.duplicate()
			new_item["slot_index"] = empty_slot

			# In real implementation, this would be done via RPC validation
			# For showcase, we simulate adding to inventory
			if WorldState.player_inventory.size() <= empty_slot:
				WorldState.player_inventory.resize(empty_slot + 1)
			WorldState.player_inventory[empty_slot] = new_item

			# Emit inventory updated signal
			if WorldState.has_signal("inventory_updated"):
				WorldState.inventory_updated.emit()

			# Remove from container
			if loot_container_ref and loot_container_ref.has_method("take_item"):
				loot_container_ref.take_item(item_id)

			# Remove from local loot_items
			var item_index = -1
			for i in range(loot_items.size()):
				if loot_items[i].get("id", "") == item_id:
					item_index = i
					break

			if item_index >= 0:
				loot_items.remove_at(item_index)

			# Refresh display
			populate_loot_grid()

			# Success feedback
			UIManager.show_message("Picked up: %s" % item_data.get("name", "item"))

			# Close panel if all items taken
			if loot_items.is_empty():
				close_loot_panel()
		else:
			UIManager.show_error("Inventory Full! Cannot take item.")
	else:
		UIManager.show_error("Inventory system not initialized")

func _on_take_all_button_pressed():
	"""Take all items from loot container"""
	# Take items one by one
	var items_to_take = loot_items.duplicate()
	var items_taken = 0

	for item_data in items_to_take:
		if has_inventory_space():
			take_item(item_data)
			items_taken += 1
		else:
			break

	if items_taken > 0:
		UIManager.show_message("Picked up %d item%s" % [items_taken, "s" if items_taken != 1 else ""])

	if items_taken < items_to_take.size():
		UIManager.show_error("Inventory Full! Could only take %d of %d items." % [items_taken, items_to_take.size()])

func has_inventory_space() -> bool:
	"""Check if player inventory has empty slots"""
	if not "player_inventory" in WorldState:
		return false

	var max_slots = 50  # From Task 5.1
	var current_items = 0

	for item in WorldState.player_inventory:
		if item != null and not item.is_empty():
			current_items += 1

	return current_items < max_slots

func find_empty_inventory_slot() -> int:
	"""Find first empty slot in inventory"""
	if not "player_inventory" in WorldState:
		return -1

	var max_slots = 50  # From Task 5.1

	# Ensure inventory array is large enough
	if WorldState.player_inventory.size() < max_slots:
		WorldState.player_inventory.resize(max_slots)

	# Find empty slot
	for i in range(max_slots):
		if i >= WorldState.player_inventory.size():
			return i

		var item = WorldState.player_inventory[i]
		if item == null or item.is_empty():
			return i

	return -1  # No empty slot

func _on_close_button_pressed():
	"""Close loot panel"""
	close_loot_panel()

func close_loot_panel():
	"""Reset state and hide panel"""
	loot_items.clear()
	loot_container_ref = null

	# Clear loot slots
	for slot in loot_slots:
		slot.queue_free()
	loot_slots.clear()

	# Hide panel
	visible = false
