extends Panel

## TradePanel UI
##
## Task: 5.3 - Create Trade Panel UI
## Requirements: 7 (Player Trading System)
## Design: TradePanel.tscn (lines 589-640)
##
## Two-sided trade window with 2PC (Two-Phase Commit) workflow.
## Players add items, lock their side, then commit when both ready.

@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var my_item_grid: GridContainer = $MarginContainer/VBoxContainer/TradeContent/MyTradeArea/MyItemGrid
@onready var their_item_grid: GridContainer = $MarginContainer/VBoxContainer/TradeContent/TheirTradeArea/TheirItemGrid
@onready var my_status_label: Label = $MarginContainer/VBoxContainer/TradeContent/MyTradeArea/MyStatusLabel
@onready var their_status_label: Label = $MarginContainer/VBoxContainer/TradeContent/TheirTradeArea/TheirStatusLabel
@onready var lock_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/LockButton
@onready var commit_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/CommitButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/CancelButton

# Preload ItemSlot scene (reuse from Task 5.1)
var item_slot_scene: PackedScene = preload("res://scenes/ui/components/ItemSlot.tscn")

# Trade session state
var trade_session_id: String = ""
var trade_partner_name: String = ""
var trade_partner_id: String = ""

# Trade slots (10 slots each side)
const TRADE_SLOTS_COUNT: int = 10
var my_trade_slots: Array[Node] = []
var their_trade_slots: Array[Node] = []

# Lock states
var my_locked: bool = false
var their_locked: bool = false

# Items in trade (item_id arrays)
var my_items: Array = []
var their_items: Array = []

func _ready() -> void:
	# Create trade slots for both sides
	create_trade_slots()

	# Hide panel initially
	visible = false

## Create empty trade slots for both players
func create_trade_slots() -> void:
	# Clear existing
	for child in my_item_grid.get_children():
		child.queue_free()
	for child in their_item_grid.get_children():
		child.queue_free()

	my_trade_slots.clear()
	their_trade_slots.clear()

	# Create my slots (can receive drops)
	for i in range(TRADE_SLOTS_COUNT):
		var slot = item_slot_scene.instantiate()
		slot.slot_index = i
		slot.item_dropped.connect(_on_my_item_dropped)
		my_item_grid.add_child(slot)
		my_trade_slots.append(slot)

	# Create their slots (display only, no drop)
	for i in range(TRADE_SLOTS_COUNT):
		var slot = item_slot_scene.instantiate()
		slot.slot_index = i
		# Disable drag-drop for their side
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		their_item_grid.add_child(slot)
		their_trade_slots.append(slot)

## Open trade with target player
##
## Parameters:
##   target_player_id: ID of player to trade with
##   target_player_name: Display name of trade partner
func open_trade(target_player_id: String, target_player_name: String) -> void:
	print("[TradePanel] Opening trade with %s (ID: %s)" % [target_player_name, target_player_id])

	trade_partner_id = target_player_id
	trade_partner_name = target_player_name

	# Update title
	title_label.text = "Trade with %s" % target_player_name

	# Call trade_open RPC
	if not NakamaManager or not NakamaManager.has_method("trade_open"):
		push_error("[TradePanel] NakamaManager.trade_open not available")
		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error("trade_open RPC not implemented yet")
		return

	var result = await NakamaManager.trade_open(target_player_id)

	if result and result.get("success", false):
		trade_session_id = result.get("session_id", "")
		print("[TradePanel] Trade session opened: %s" % trade_session_id)

		# Reset state
		reset_trade_state()

		# Show panel
		visible = true
	else:
		var error_message = "Failed to open trade"
		if result and result.has("error"):
			error_message = result.error

		print("[TradePanel] Trade open failed: %s" % error_message)

		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error(error_message)

## Reset trade state
func reset_trade_state() -> void:
	my_locked = false
	their_locked = false
	my_items.clear()
	their_items.clear()

	# Clear all slots
	for slot in my_trade_slots:
		slot.clear_slot()
	for slot in their_trade_slots:
		slot.clear_slot()

	# Reset button states
	lock_button.disabled = false
	commit_button.disabled = true

	# Update status labels
	update_status_labels()

## Handle item dropped into my trade slots
##
## Parameters:
##   from_slot: Source slot index (from inventory or trade reorder)
##   to_slot: Target trade slot index
func _on_my_item_dropped(from_slot: int, to_slot: int) -> void:
	# Can't add items after locking
	if my_locked:
		print("[TradePanel] Cannot add items after locking")
		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error("Cannot modify trade after locking")
		return

	# Note: This receives the drop event from ItemSlot
	# The ItemSlot drag data includes: {slot_index, item}
	# We need to interpret this as adding item from inventory to trade

	# When dropping from inventory to trade, we get the inventory slot index
	# We should get the item from WorldState.player_inventory

	if not WorldState or not "player_inventory" in WorldState:
		print("[TradePanel] WorldState.player_inventory not available")
		return

	# Find item in inventory by slot index
	var inventory = WorldState.player_inventory
	var item_to_add: Dictionary = {}

	for item in inventory:
		if item.get("slot_index") == from_slot:
			item_to_add = item
			break

	if item_to_add.is_empty():
		print("[TradePanel] No item found in inventory slot %d" % from_slot)
		return

	# Add to trade
	add_item_to_trade(item_to_add, to_slot)

## Add item to trade
##
## Parameters:
##   item_data: Item dictionary with id, name, icon, etc.
##   slot_index: Trade slot to place item in
func add_item_to_trade(item_data: Dictionary, slot_index: int = -1) -> void:
	if my_locked:
		print("[TradePanel] Cannot add items after locking")
		return

	# Find empty slot if not specified
	if slot_index < 0:
		for i in range(my_trade_slots.size()):
			if my_trade_slots[i].item_data.is_empty():
				slot_index = i
				break

	if slot_index < 0 or slot_index >= my_trade_slots.size():
		print("[TradePanel] No empty trade slots")
		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error("Trade slots full")
		return

	var item_id = item_data.get("id", "")
	if item_id.is_empty():
		return

	print("[TradePanel] Adding item %s to trade slot %d" % [item_id, slot_index])

	# Call trade_add_item RPC
	if not NakamaManager or not NakamaManager.has_method("trade_add_item"):
		push_error("[TradePanel] NakamaManager.trade_add_item not available")
		return

	var result = await NakamaManager.trade_add_item(trade_session_id, item_id)

	if result and result.get("success", false):
		# Add to my items
		my_items.append(item_id)

		# Update slot display
		my_trade_slots[slot_index].set_item(item_data)

		print("[TradePanel] Item added to trade successfully")
	else:
		var error_message = "Failed to add item to trade"
		if result and result.has("error"):
			error_message = result.error

		print("[TradePanel] Add item failed: %s" % error_message)

		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error(error_message)

## Handle Lock button press
func _on_lock_button_pressed() -> void:
	if my_locked:
		return

	print("[TradePanel] Locking my side of trade")

	# Call trade_lock RPC
	if not NakamaManager or not NakamaManager.has_method("trade_lock"):
		push_error("[TradePanel] NakamaManager.trade_lock not available")
		return

	var result = await NakamaManager.trade_lock(trade_session_id)

	if result and result.get("success", false):
		my_locked = true
		lock_button.disabled = true

		update_status_labels()
		check_commit_ready()

		print("[TradePanel] Locked successfully")
	else:
		var error_message = "Failed to lock trade"
		if result and result.has("error"):
			error_message = result.error

		print("[TradePanel] Lock failed: %s" % error_message)

		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error(error_message)

## Check if both sides locked and enable commit
func check_commit_ready() -> void:
	commit_button.disabled = not (my_locked and their_locked)

	if my_locked and their_locked:
		print("[TradePanel] Both sides locked - commit ready")

## Handle Commit button press (2PC)
func _on_commit_button_pressed() -> void:
	if not my_locked or not their_locked:
		return

	print("[TradePanel] Committing trade")

	# Call trade_commit RPC
	if not NakamaManager or not NakamaManager.has_method("trade_commit"):
		push_error("[TradePanel] NakamaManager.trade_commit not available")
		return

	var result = await NakamaManager.trade_commit(trade_session_id)

	if result and result.get("success", false):
		print("[TradePanel] Trade completed successfully")

		if UIManager and UIManager.has_method("show_message"):
			UIManager.show_message("Trade completed!")

		# Close trade panel
		close_trade()

		# Inventory will update via WorldState.inventory_updated signal
	else:
		var error_message = "Trade failed. Items returned."
		if result and result.has("error"):
			error_message = result.error

		print("[TradePanel] Commit failed: %s" % error_message)

		if UIManager and UIManager.has_method("show_error"):
			UIManager.show_error(error_message)

		# Close and reset on failure
		close_trade()

## Handle Cancel button press
func _on_cancel_button_pressed() -> void:
	cancel_trade()

## Handle close button press
func _on_close_button_pressed() -> void:
	cancel_trade()

## Cancel trade and close panel
func cancel_trade() -> void:
	if trade_session_id.is_empty():
		close_trade()
		return

	print("[TradePanel] Cancelling trade")

	# Call trade_cancel RPC
	if not NakamaManager or not NakamaManager.has_method("trade_cancel"):
		push_error("[TradePanel] NakamaManager.trade_cancel not available")
		close_trade()
		return

	var result = await NakamaManager.trade_cancel(trade_session_id)

	if result and result.get("success", false):
		print("[TradePanel] Trade cancelled")
	else:
		print("[TradePanel] Cancel RPC failed (trade may already be closed)")

	close_trade()

## Close trade panel and reset
func close_trade() -> void:
	trade_session_id = ""
	trade_partner_id = ""
	trade_partner_name = ""

	reset_trade_state()

	visible = false

	print("[TradePanel] Trade panel closed")

## Update status labels based on lock states
func update_status_labels() -> void:
	if my_locked:
		my_status_label.text = "✓ Locked"
		my_status_label.modulate = Color(0.2, 1.0, 0.2)  # Green
	else:
		my_status_label.text = "Not Locked"
		my_status_label.modulate = Color(1.0, 1.0, 1.0)  # White

	if their_locked:
		their_status_label.text = "✓ Locked"
		their_status_label.modulate = Color(0.2, 1.0, 0.2)  # Green
	else:
		their_status_label.text = "Not Locked"
		their_status_label.modulate = Color(1.0, 1.0, 1.0)  # White

## Update trade state from server (called by external systems)
##
## Parameters:
##   state: Trade state dictionary with their_items, their_locked, etc.
func update_trade_state(state: Dictionary) -> void:
	# Update their lock status
	if state.has("their_locked"):
		their_locked = state.their_locked

	# Update their items
	if state.has("their_items"):
		their_items = state.their_items

		# Update display
		for i in range(their_trade_slots.size()):
			if i < their_items.size():
				# TODO: Get full item data from item_id
				# For now, display placeholder
				var item_data = {"id": their_items[i], "name": "Item", "icon": ""}
				their_trade_slots[i].set_item(item_data)
			else:
				their_trade_slots[i].clear_slot()

	update_status_labels()
	check_commit_ready()
