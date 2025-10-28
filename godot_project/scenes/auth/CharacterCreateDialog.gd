## CharacterCreateDialog
##
## Dialog for character creation with name input and archetype selection.
##
## Task: 1.4.5 - Implement character creation flow
## Requirement: 3 (Character Creation)
##
## This dialog handles:
## - Character name input with client-side validation
## - Archetype selection via dropdown
## - Error handling for server-side validation failures
extends Window

signal character_created

@onready var name_input: LineEdit = $MarginContainer/VBoxContainer/NameInput
@onready var archetype_dropdown: OptionButton = $MarginContainer/VBoxContainer/ArchetypeDropdown
@onready var error_label: Label = $MarginContainer/VBoxContainer/ErrorLabel
@onready var create_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/CreateButton

## Available archetypes
## Note: In production, this would be loaded from server configuration
const ARCHETYPES = [
	{"id": "warrior", "name": "Warrior"},
	{"id": "mage", "name": "Mage"},
	{"id": "rogue", "name": "Rogue"},
	{"id": "cleric", "name": "Cleric"}
]


func _ready() -> void:
	# Populate archetype dropdown
	for archetype in ARCHETYPES:
		archetype_dropdown.add_item(archetype.name)

	# Select first archetype by default
	if archetype_dropdown.item_count > 0:
		archetype_dropdown.select(0)

	# Clear error label
	error_label.text = ""

	# Focus name input when dialog opens
	name_input.grab_focus()


## Show the dialog
func show_dialog() -> void:
	visible = true
	name_input.clear()
	error_label.text = ""
	create_button.disabled = false
	name_input.grab_focus()


## Validate character name client-side
##
## Task: 1.4.5 - Client-side pre-validation
## Requirement 3: Name length 3-20 chars, alphanumeric + spaces
func validate_name(character_name: String) -> String:
	# Check length
	if character_name.length() < 3:
		return "Name must be at least 3 characters"

	if character_name.length() > 20:
		return "Name must be at most 20 characters"

	# Check for valid characters (alphanumeric + spaces)
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9 ]+$")

	if not regex.search(character_name):
		return "Name can only contain letters, numbers, and spaces"

	# Check for leading/trailing spaces
	if character_name.strip_edges() != character_name:
		return "Name cannot start or end with spaces"

	# Check for multiple consecutive spaces
	if "  " in character_name:
		return "Name cannot contain multiple consecutive spaces"

	return ""


## Handle name input text changed
func _on_name_input_text_changed(new_text: String) -> void:
	# Clear error on input change
	error_label.text = ""


## Handle create button press
##
## Task: 1.4.5 - Implement character creation flow
func _on_create_button_pressed() -> void:
	var character_name = name_input.text.strip_edges()

	# Client-side validation
	var validation_error = validate_name(character_name)
	if validation_error != "":
		error_label.text = validation_error
		return

	# Get selected archetype
	var selected_index = archetype_dropdown.selected
	if selected_index < 0 or selected_index >= ARCHETYPES.size():
		error_label.text = "Please select an archetype"
		return

	var archetype_id = ARCHETYPES[selected_index].id

	# Disable create button during RPC
	create_button.disabled = true
	error_label.text = "Creating character..."

	# Call server to create character
	var character_id = await NakamaManager.create_character(character_name, archetype_id)

	if character_id.is_empty():
		# Handle server errors
		# Task: 1.4.5 - Handle server errors (name taken, slot limit)
		error_label.text = "Failed to create character. Name may be taken or character limit reached."
		create_button.disabled = false
	else:
		# Success!
		error_label.text = "Character created successfully!"

		# Wait a moment before closing
		await get_tree().create_timer(0.5).timeout

		# Emit signal to notify parent
		character_created.emit()

		# Close dialog
		visible = false


## Handle cancel button press
func _on_cancel_button_pressed() -> void:
	visible = false


## Handle window close request
func _on_close_requested() -> void:
	visible = false
