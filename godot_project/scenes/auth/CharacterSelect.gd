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

## Array of character data dictionaries
var characters: Array = []

## Currently selected character index
var selected_index: int = -1


func _ready() -> void:
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
	# TODO: Task 1.4.5 - Show character creation dialog
	# For now, create a test character with random name
	var test_name = "Hero%d" % randi_range(1000, 9999)
	var test_archetype = "warrior"

	status_label.text = "Creating character..."
	create_button.disabled = true

	var character_id = await NakamaManager.create_character(test_name, test_archetype)

	if character_id.is_empty():
		status_label.text = "Character creation failed"
		create_button.disabled = false
	else:
		status_label.text = "Character created successfully!"
		create_button.disabled = false

		# Reload character list
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
