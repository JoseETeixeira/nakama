extends AcceptDialog

## ItemTemplateDialog
##
## Task: 5.2 - Create Debug Item Creation Tool
## Requirements: 6 (Inventory Management - Debug Item Creation)
## Design: Inventory System
##
## Dialog for selecting item templates to create via debug RPC.
## Filters templates by search text and emits template_selected signal.

signal template_selected(template_id: String)

@onready var search_box: LineEdit = $MarginContainer/VBoxContainer/SearchBox
@onready var template_list: ItemList = $MarginContainer/VBoxContainer/TemplateList

# Item templates available for creation
# In production, these would be loaded from server or data files
const ITEM_TEMPLATES: Array[Dictionary] = [
	{"id": "sword_iron", "name": "Iron Sword", "rarity": "common"},
	{"id": "sword_steel", "name": "Steel Sword", "rarity": "uncommon"},
	{"id": "sword_mithril", "name": "Mithril Sword", "rarity": "rare"},
	{"id": "sword_legendary", "name": "Legendary Blade", "rarity": "legendary"},
	{"id": "potion_health_minor", "name": "Minor Health Potion", "rarity": "common"},
	{"id": "potion_health_major", "name": "Major Health Potion", "rarity": "uncommon"},
	{"id": "potion_mana_minor", "name": "Minor Mana Potion", "rarity": "common"},
	{"id": "potion_mana_major", "name": "Major Mana Potion", "rarity": "uncommon"},
	{"id": "armor_leather_chest", "name": "Leather Chestplate", "rarity": "common"},
	{"id": "armor_chain_chest", "name": "Chain Chestplate", "rarity": "uncommon"},
	{"id": "armor_plate_chest", "name": "Plate Chestplate", "rarity": "rare"},
	{"id": "shield_wooden", "name": "Wooden Shield", "rarity": "common"},
	{"id": "shield_iron", "name": "Iron Shield", "rarity": "uncommon"},
	{"id": "bow_short", "name": "Short Bow", "rarity": "common"},
	{"id": "bow_long", "name": "Long Bow", "rarity": "uncommon"},
	{"id": "staff_oak", "name": "Oak Staff", "rarity": "common"},
	{"id": "staff_arcane", "name": "Arcane Staff", "rarity": "rare"},
	{"id": "ring_strength", "name": "Ring of Strength", "rarity": "rare"},
	{"id": "ring_wisdom", "name": "Ring of Wisdom", "rarity": "rare"},
	{"id": "amulet_protection", "name": "Amulet of Protection", "rarity": "epic"},
]

# Rarity color mapping (matches ItemSlot.gd)
const RARITY_COLORS: Dictionary = {
	"common": Color(0.7, 0.7, 0.7),
	"uncommon": Color(0.2, 0.8, 0.2),
	"rare": Color(0.3, 0.5, 1.0),
	"epic": Color(0.7, 0.3, 1.0),
	"legendary": Color(1.0, 0.6, 0.0)
}

func _ready() -> void:
	# Populate initial list
	populate_template_list("")

	# Focus search box
	search_box.grab_focus()

## Populate template list with optional filter
##
## Parameters:
##   filter: Search text to filter templates (case-insensitive)
func populate_template_list(filter: String) -> void:
	template_list.clear()

	var filter_lower = filter.to_lower()

	for template in ITEM_TEMPLATES:
		var template_id = template.get("id", "")
		var template_name = template.get("name", "")
		var rarity = template.get("rarity", "common")

		# Filter by search text
		if filter_lower != "" and not template_name.to_lower().contains(filter_lower) and not template_id.to_lower().contains(filter_lower):
			continue

		# Add to list with color coding
		var display_text = "%s (%s)" % [template_name, rarity.capitalize()]
		var index = template_list.add_item(display_text)

		# Store template_id in metadata
		template_list.set_item_metadata(index, template_id)

		# Set rarity color
		if RARITY_COLORS.has(rarity):
			template_list.set_item_custom_fg_color(index, RARITY_COLORS[rarity])

## Handle search text changed
##
## Parameters:
##   new_text: New search text
func _on_search_text_changed(new_text: String) -> void:
	populate_template_list(new_text)

## Handle template double-click or Enter key
##
## Parameters:
##   index: Index of selected item in list
func _on_template_selected(index: int) -> void:
	if index < 0 or index >= template_list.item_count:
		return

	var template_id = template_list.get_item_metadata(index)
	if template_id:
		template_selected.emit(template_id)
		hide()

## Get selected template ID (called when OK button clicked)
func get_selected_template_id() -> String:
	var selected = template_list.get_selected_items()
	if selected.is_empty():
		return ""

	return template_list.get_item_metadata(selected[0])
