extends PanelContainer

## ItemSlot Component
##
## Task: 5.1 - Create Inventory Panel UI
## Requirements: 6 (Inventory Management)
## Design: ItemSlot.tscn (lines 546-590)
##
## Reusable inventory slot with drag-and-drop functionality.
## Displays item icon, stack count, and rarity border.

@onready var icon: TextureRect = $MarginContainer/Content/Icon
@onready var stack_count_label: Label = $MarginContainer/Content/StackCount
@onready var rarity_border: ColorRect = $RarityBorder

# Slot properties
var slot_index: int = 0
var item_data: Dictionary = {}

# Signals
signal item_dropped(from_slot: int, to_slot: int)

# Rarity colors mapping
const RARITY_COLORS = {
	"common": Color(0.6, 0.6, 0.6),
	"uncommon": Color(0.1, 0.8, 0.1),
	"rare": Color(0.2, 0.5, 1.0),
	"epic": Color(0.6, 0.2, 0.9),
	"legendary": Color(1.0, 0.5, 0.0)
}

func _ready() -> void:
	# Initially hide all elements
	clear_slot()

## Set item data and update display
##
## Parameters:
##   item: Item dictionary with id, icon, stack_count, rarity, etc.
func set_item(item: Dictionary) -> void:
	item_data = item

	if item.is_empty():
		clear_slot()
		return

	# Set icon
	var icon_path = item.get("icon", "")
	if icon_path and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
		icon.visible = true
	else:
		# Placeholder colored rect if no icon
		icon.visible = false

	# Set stack count (only show if > 1)
	var stack_count = item.get("stack_count", 1)
	if stack_count > 1:
		stack_count_label.text = str(stack_count)
		stack_count_label.visible = true
	else:
		stack_count_label.visible = false

	# Set rarity border color
	var rarity = item.get("rarity", "common")
	var rarity_color = RARITY_COLORS.get(rarity, Color.WHITE)
	rarity_border.color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.5)

## Clear slot display
func clear_slot() -> void:
	item_data = {}
	icon.texture = null
	icon.visible = false
	stack_count_label.visible = false
	stack_count_label.text = ""
	rarity_border.color = Color(0, 0, 0, 0)

## Get drag data for drag-and-drop
##
## Called by Godot when user starts dragging
func _get_drag_data(_position: Vector2) -> Variant:
	if item_data.is_empty():
		return null

	# Create drag preview
	var preview = TextureRect.new()
	if icon.texture:
		preview.texture = icon.texture
		preview.custom_minimum_size = Vector2(48, 48)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		# Fallback colored rect
		var color_rect = ColorRect.new()
		color_rect.color = RARITY_COLORS.get(item_data.get("rarity", "common"), Color.WHITE)
		color_rect.custom_minimum_size = Vector2(48, 48)
		preview = color_rect

	set_drag_preview(preview)

	# Return drag data
	return {
		"slot_index": slot_index,
		"item": item_data
	}

## Check if can accept drop data
##
## Called by Godot when user drags over this slot
func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false

	if not "slot_index" in data:
		return false

	# Can't drop on itself
	if data.slot_index == slot_index:
		return false

	return true

## Handle drop data
##
## Called by Godot when user releases drag over this slot
func _drop_data(_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_position, data):
		return

	# Emit signal for parent to handle RPC call
	item_dropped.emit(data.slot_index, slot_index)

## Handle mouse enter for tooltip
func _on_mouse_entered() -> void:
	if item_data.is_empty():
		return

	if UIManager and UIManager.has_method("show_tooltip"):
		UIManager.show_tooltip(item_data, global_position + Vector2(0, -100))

## Handle mouse exit for tooltip
func _on_mouse_exited() -> void:
	if UIManager and UIManager.has_method("hide_tooltip"):
		UIManager.hide_tooltip()

## Handle GUI input (for potential future click interactions)
func _on_gui_input(event: InputEvent) -> void:
	# Right-click could open context menu in future
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not item_data.is_empty():
				print("[ItemSlot] Right-clicked item: ", item_data.get("name", "Unknown"))
				# TODO: Show context menu (use item, drop item, etc.)
