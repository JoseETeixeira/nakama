## CharacterSelect
##
## Character selection and creation screen.
##
## Task: 1.4.4 - Implement character selection screen
## Task: 1.4.5 - Implement character creation flow
## Requirements: 2 (Character List and Selection), 3 (Character Creation)
##
## This screen handles:
## - Listing characters for the authenticated account
## - Character selection for world entry
## - Character creation UI
extends Control

@onready var character_list: ItemList = $VBoxContainer/CharacterList
@onready var create_button: Button = $VBoxContainer/ButtonContainer/CreateButton
@onready var select_button: Button = $VBoxContainer/ButtonContainer/SelectButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var create_dialog: Window = $CharacterCreateDialog

## Array of character data dictionaries
var characters: Array = []

## Currently selected character index
var selected_index: int = -1


func _ready() -> void:
	# Connect create dialog signal
	create_dialog.character_created.connect(_on_character_created)

	# Load character list on scene load
	load_characters()


## Load characters from server
##
## Task: 1.4.4 - Implement character selection screen
func load_characters() -> void:
	status_label.text = "Loading characters..."
	character_list.clear()

	characters = await NakamaManager.list_characters()

	if characters.size() == 0:
		status_label.text = "No characters found. Create one to start!"
	else:
		status_label.text = "%d character(s) found" % characters.size()

		# Populate character list
		for character in characters:
			var char_name = character.get("name", "Unknown")
			var char_level = character.get("level", 1)
			var display_text = "%s (Level %d)" % [char_name, char_level]
			character_list.add_item(display_text)


## Handle character list item selection
func _on_character_list_item_selected(index: int) -> void:
	selected_index = index
	select_button.disabled = false
	status_label.text = "Character selected: %s" % characters[index].get("name", "Unknown")


## Handle create character button press
##
## Task: 1.4.5 - Implement character creation flow
func _on_create_button_pressed() -> void:
	# Show character creation dialog
	create_dialog.show_dialog()


## Handle character created signal from dialog
##
## Task: 1.4.5 - Reload character list after creation
func _on_character_created() -> void:
	status_label.text = "Character created successfully!"

	# Reload character list to show new character
	await get_tree().create_timer(0.5).timeout
	load_characters()


## Handle select character button press
##
## Task: 1.4.6 - Implement character selection flow
func _on_select_button_pressed() -> void:
	if selected_index < 0 or selected_index >= characters.size():
		push_error("[CharacterSelect] Invalid character index")
		return

	var character = characters[selected_index]
	var character_id = character.get("characterId", "")

	if character_id.is_empty():
		push_error("[CharacterSelect] Character ID is empty")
		return

	status_label.text = "Loading character..."
	select_button.disabled = true

	# Select character on server
	var character_state = await NakamaManager.select_character(character_id)

	if character_state.is_empty():
		status_label.text = "Failed to load character"
		select_button.disabled = false
		return

	status_label.text = "Entering world..."

	# Enter world with selected character
	# TODO: Phase 2, Task 2.1.2 - Implement world_enter RPC
	# For now, just transition to placeholder world scene
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/world/Zone.tscn")
