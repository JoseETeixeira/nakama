extends Panel

# VendorPanel.gd
# Handles vendor catalog display, item purchases, and item selling
# Following Requirement 8: Vendor Interactions

# References to UI nodes
@onready var title_label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var close_button = $MarginContainer/VBoxContainer/Header/CloseButton
@onready var currency_value = $MarginContainer/VBoxContainer/CurrencyContainer/CurrencyValue
@onready var vendor_grid = $MarginContainer/VBoxContainer/VendorContent/VendorCatalogArea/VendorScrollContainer/VendorGrid
@onready var sell_grid = $MarginContainer/VBoxContainer/VendorContent/PlayerSellArea/SellScrollContainer/SellGrid

# Vendor state
var vendor_id: String = ""
var vendor_name: String = ""
var vendor_catalog: Array = []
var vendor_slots: Array[Node] = []
var sell_slots: Array[Node] = []
var player_currency: int = 0

# ItemSlot preload
const ITEM_SLOT_SCENE = preload("res://scenes/ui/components/ItemSlot.tscn")

func _ready():
	# Create sell slots (10 slots for player to drag items into)
	create_sell_slots()

	# Connect to WorldState for currency updates
	if WorldState.has_signal("player_currency_updated"):
		WorldState.player_currency_updated.connect(_on_player_currency_updated)

	# Connect to WorldState for inventory updates (affects sell value calculation)
	if WorldState.has_signal("inventory_updated"):
		WorldState.inventory_updated.connect(_on_inventory_updated)

func create_sell_slots():
	"""Create 10 ItemSlot instances for the sell area"""
	for i in range(10):
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.custom_minimum_size = Vector2(48, 48)
		slot.slot_index = i + 100  # Offset to distinguish from inventory slots

		# Enable drop acceptance for selling
		if slot.has_signal("item_dropped"):
			slot.item_dropped.connect(_on_inventory_item_dropped)

		sell_grid.add_child(slot)
		sell_slots.append(slot)

func open_vendor(target_vendor_id: String, target_vendor_name: String):
	"""Open vendor panel and load catalog via RPC"""
	vendor_id = target_vendor_id
	vendor_name = target_vendor_name

	# Update title
	title_label.text = "Vendor: " + vendor_name

	# Load vendor catalog from server
	var catalog_result = await NakamaManager.get_vendor_catalog(vendor_id)

	if catalog_result == null:
		UIManager.show_error("Failed to load vendor catalog")
		return

	vendor_catalog = catalog_result
	populate_vendor_catalog()

	# Update player currency display
	update_currency_display()

	# Show panel
	visible = true

func populate_vendor_catalog():
	"""Display vendor items in catalog grid"""
	# Clear existing vendor slots
	for slot in vendor_slots:
		slot.queue_free()
	vendor_slots.clear()

	# Create ItemSlot for each catalog item
	for item_data in vendor_catalog:
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.custom_minimum_size = Vector2(48, 48)

		# Set item display
		slot.set_item(item_data)

		# Add price label overlay
		var price_label = Label.new()
		price_label.text = str(item_data.get("price", 0)) + "g"
		price_label.position = Vector2(2, 32)
		price_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold color
		price_label.z_index = 10
		slot.add_child(price_label)

		# Check if out of stock
		if item_data.get("stock", 1) <= 0:
			slot.modulate = Color(0.5, 0.5, 0.5, 0.5)  # Gray out
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			# Connect gui_input signal to handle clicks
			if not slot.gui_input.is_connected(_on_vendor_item_gui_input):
				slot.gui_input.connect(_on_vendor_item_gui_input.bind(item_data))

		vendor_grid.add_child(slot)
		vendor_slots.append(slot)

func _on_vendor_item_gui_input(event: InputEvent, item_data: Dictionary):
	"""Handle click on vendor item to purchase"""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			purchase_item(item_data)

func purchase_item(item_data: Dictionary):
	"""Purchase item from vendor via vendor_buy RPC"""
	var item_id = item_data.get("id", "")
	var price = item_data.get("price", 0)

	# Check if player has enough currency (client-side check, server validates)
	if player_currency < price:
		UIManager.show_error("Insufficient funds! Need %d gold." % price)
		return

	# Call vendor_buy RPC
	var success = await NakamaManager.vendor_buy(vendor_id, item_id)

	if success:
		# Success feedback
		UIManager.show_message("Purchased %s for %d gold!" % [item_data.get("name", "item"), price])

		# Refresh vendor catalog (stock may have changed)
		var catalog_result = await NakamaManager.get_vendor_catalog(vendor_id)
		if catalog_result != null:
			vendor_catalog = catalog_result
			populate_vendor_catalog()

		# Update currency (server will send updated value via WorldState)
		update_currency_display()
	else:
		UIManager.show_error("Purchase failed! Item may be out of stock or you lack funds.")

func _on_inventory_item_dropped(from_slot: int, to_slot: int):
	"""Handle item dropped from inventory into sell area"""
	# Find item in player inventory
	if from_slot < 0 or from_slot >= WorldState.player_inventory.size():
		return

	var item_data = WorldState.player_inventory[from_slot]
	if item_data == null or item_data.is_empty():
		return

	# Sell the item
	sell_item(item_data)

func sell_item(item_data: Dictionary):
	"""Sell item to vendor via vendor_sell RPC"""
	var item_id = item_data.get("id", "")

	# Call vendor_sell RPC
	var result = await NakamaManager.vendor_sell(vendor_id, item_id)

	if result != null and result.has("gold"):
		var gold_received = result.get("gold", 0)

		# Success feedback
		UIManager.show_message("Sold %s for %d gold!" % [item_data.get("name", "item"), gold_received])

		# Update currency (server will send updated value via WorldState)
		update_currency_display()

		# Inventory will update via WorldState.inventory_updated signal
	else:
		UIManager.show_error("Sell failed! Item may not be sellable.")

func update_currency_display():
	"""Update player currency display from WorldState"""
	# Get currency from WorldState (assuming it's stored in player_currency property)
	if WorldState.has("player_currency"):
		player_currency = WorldState.player_currency
	else:
		# Fallback: parse from player entity metadata or use default
		player_currency = 0

	currency_value.text = str(player_currency)

func _on_player_currency_updated(new_currency: int):
	"""React to currency updates from WorldState signal"""
	player_currency = new_currency
	currency_value.text = str(player_currency)

func _on_inventory_updated():
	"""React to inventory updates (may affect sell area)"""
	# Inventory changes may affect what items are available to sell
	# No immediate action needed since sell happens via drag-drop from InventoryPanel

func _on_close_button_pressed():
	"""Close vendor panel"""
	close_vendor()

func close_vendor():
	"""Reset vendor state and hide panel"""
	vendor_id = ""
	vendor_name = ""
	vendor_catalog.clear()

	# Clear vendor slots
	for slot in vendor_slots:
		slot.queue_free()
	vendor_slots.clear()

	# Clear sell slots (just clear item display, keep slots)
	for slot in sell_slots:
		slot.clear_slot()

	# Hide panel
	visible = false
