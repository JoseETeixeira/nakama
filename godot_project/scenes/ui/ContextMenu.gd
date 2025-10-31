extends PopupPanel

## ContextMenu
##
## Displays a context menu with dynamic options for NPC/player interactions
##
## Task: 7.1 - Implement NPC Interaction Menu
## Requirements: 12
## Design: NPC Interaction (lines 412-423)
##
## This popup menu displays interaction options based on entity type:
## - Talk: Opens dialogue (if NPC has quests/dialogue)
## - Trade: Opens vendor panel (if NPC is vendor) or trade panel (if player)
## - Attack: Enables ability targeting (if entity is enemy)

# References to UI nodes
@onready var option_button_container = $MarginContainer/VBoxContainer/OptionButtonContainer

# Menu state
var menu_options: Array[String] = []
var target_entity: Node = null
var callback_object: Object = null
var callback_method: String = ""

## Initialize and show context menu
##
## Parameters:
##   options: Array of option strings (e.g., ["Talk", "Trade", "Attack"])
##   entity: NPCEntity or PlayerEntity that was clicked
##   screen_position: Position to display menu (usually mouse position)
##   callback_obj: Object that will receive selection callbacks
##   callback_func: Method name to call on callback_obj when option selected
##
## Task: 7.1 - Implement NPC Interaction Menu
## Requirements: 12
func show_menu(options: Array[String], entity: Node, screen_position: Vector2, callback_obj: Object = null, callback_func: String = "") -> void:
	menu_options = options
	target_entity = entity
	callback_object = callback_obj if callback_obj != null else entity
	callback_method = callback_func if not callback_func.is_empty() else "_on_menu_item_selected"

	# Clear existing buttons
	clear_options()

	# Create button for each option
	for option in menu_options:
		create_option_button(option)

	# Adjust menu size to fit content
	await get_tree().process_frame
	size = Vector2.ZERO  # Reset size to recalculate

	# Position menu at screen position
	position = screen_position

	# Ensure menu stays on screen
	var viewport_rect = get_viewport().get_visible_rect()
	if position.x + size.x > viewport_rect.size.x:
		position.x = viewport_rect.size.x - size.x
	if position.y + size.y > viewport_rect.size.y:
		position.y = viewport_rect.size.y - size.y

	# Show popup
	popup()


## Create option button for menu
##
## Parameters:
##   option_text: Text to display on button
func create_option_button(option_text: String) -> void:
	var button = Button.new()
	button.text = option_text
	button.custom_minimum_size = Vector2(120, 32)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Connect pressed signal
	button.pressed.connect(_on_option_selected.bind(option_text))

	option_button_container.add_child(button)


## Handle option selection
##
## Parameters:
##   option: The option text that was selected
func _on_option_selected(option: String) -> void:
	# Hide menu
	hide()

	# Call callback on target object
	if callback_object != null and callback_object.has_method(callback_method):
		callback_object.call(callback_method, option)
	else:
		push_warning("[ContextMenu] Callback not found: %s.%s()" % [callback_object, callback_method])


## Clear all option buttons
func clear_options() -> void:
	for child in option_button_container.get_children():
		child.queue_free()


## Close menu when clicked outside
func _on_focus_exited() -> void:
	hide()
