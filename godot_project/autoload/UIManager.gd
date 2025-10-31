## UIManager Singleton
##
## Autoload singleton for managing UI panel visibility, modal dialogs,
## and tooltip display across the entire application.
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: All (1-13) - Used by all UI systems
## Design: UIManager Autoload (lines 292-315)
##
## This singleton provides centralized UI management:
## - Panel show/hide/toggle operations
## - Modal dialog display (error, confirm, loading)
## - Tooltip system for item/entity information
## - Panel visibility state tracking
## - Event signaling for UI state changes
##
## Usage:
##   UIManager.show_panel("inventory")
##   UIManager.show_error("Connection failed!")
##   UIManager.show_tooltip(item_data, mouse_position)
extends Node

## Emitted when a panel is opened
## Parameters:
##   panel_name: String - Name of the panel that was opened
signal panel_opened(panel_name: String)

## Emitted when a panel is closed
## Parameters:
##   panel_name: String - Name of the panel that was closed
signal panel_closed(panel_name: String)

## Dictionary tracking panel visibility states
## Key: panel_name (String), Value: is_visible (bool)
var panel_states: Dictionary = {}

## Reference to current tooltip node (if any)
var current_tooltip: Control = null

## Reference to current loading dialog (if any)
var current_loading_dialog: Control = null

## Reference to active modal dialogs
var active_dialogs: Array = []

## Reference to active context menu (if any)
var current_context_menu: Control = null

## Context menu scene preload
var context_menu_scene = preload("res://scenes/ui/ContextMenu.tscn")


## ============================================================================
## PANEL MANAGEMENT
## ============================================================================

## Show a UI panel
##
## Parameters:
##   panel_name: Name of the panel to show (e.g., "inventory", "chat", "guild")
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: All (panels used across all features)
## Design: UIManager Autoload (lines 297-299)
##
## This function finds the panel node by name and makes it visible.
## Emits panel_opened signal for other systems to respond.
func show_panel(panel_name: String) -> void:
	var panel = get_panel_node(panel_name)

	if panel == null:
		push_warning("[UIManager] Panel not found: %s" % panel_name)
		return

	if panel.visible:
		# Already visible
		return

	panel.visible = true
	panel_states[panel_name] = true

	print("[UIManager] Opened panel: %s" % panel_name)
	panel_opened.emit(panel_name)


## Hide a UI panel
##
## Parameters:
##   panel_name: Name of the panel to hide
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: All
## Design: UIManager Autoload (lines 297-299)
##
## This function finds the panel node by name and hides it.
## Emits panel_closed signal for cleanup operations.
func hide_panel(panel_name: String) -> void:
	var panel = get_panel_node(panel_name)

	if panel == null:
		push_warning("[UIManager] Panel not found: %s" % panel_name)
		return

	if not panel.visible:
		# Already hidden
		return

	panel.visible = false
	panel_states[panel_name] = false

	print("[UIManager] Closed panel: %s" % panel_name)
	panel_closed.emit(panel_name)


## Toggle a UI panel's visibility
##
## Parameters:
##   panel_name: Name of the panel to toggle
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: All
## Design: UIManager Autoload (lines 297-299)
##
## Convenience function to show panel if hidden, hide if visible.
func toggle_panel(panel_name: String) -> void:
	var panel = get_panel_node(panel_name)

	if panel == null:
		push_warning("[UIManager] Panel not found: %s" % panel_name)
		return

	if panel.visible:
		hide_panel(panel_name)
	else:
		show_panel(panel_name)


## Close all open panels
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: All
## Design: UIManager Autoload (lines 297-299)
##
## Useful for cleanup operations or when transitioning between scenes.
func close_all_panels() -> void:
	print("[UIManager] Closing all panels")

	for panel_name in panel_states.keys():
		if panel_states[panel_name]:
			hide_panel(panel_name)


## Get panel node by name
##
## Parameters:
##   panel_name: Name of the panel to find
##
## Returns: Panel Control node or null if not found
##
## Helper function that searches the scene tree for a panel by name.
## Panels are typically located in /root/World/UI/ or similar paths.
func get_panel_node(panel_name: String) -> Control:
	# Try common panel locations
	var possible_paths = [
		"/root/World/UI/%sPanel" % panel_name.capitalize(),
		"/root/World/CanvasLayer/%sPanel" % panel_name.capitalize(),
		"/root/UI/%sPanel" % panel_name.capitalize(),
		"/root/%sPanel" % panel_name.capitalize()
	]

	for path in possible_paths:
		var node = get_node_or_null(path)
		if node != null and node is Control:
			return node

	# Try searching by name in scene tree
	var world = get_node_or_null("/root/World")
	if world != null:
		var panel = find_child_by_name(world, panel_name.capitalize() + "Panel")
		if panel != null:
			return panel

	return null


## Recursively find child node by name
##
## Parameters:
##   parent: Parent node to search
##   node_name: Name of the node to find
##
## Returns: Found node or null
func find_child_by_name(parent: Node, node_name: String) -> Node:
	for child in parent.get_children():
		if child.name == node_name:
			return child

		var found = find_child_by_name(child, node_name)
		if found != null:
			return found

	return null


## ============================================================================
## DIALOG MANAGEMENT
## ============================================================================

## Show error dialog with message
##
## Parameters:
##   message: Error message to display
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: All (error handling across all features)
## Design: UIManager Autoload (lines 301-305)
##
## Displays a modal error dialog with the provided message.
## User must acknowledge the error to close the dialog.
func show_error(message: String) -> void:
	print("[UIManager] Error: %s" % message)

	# Create simple error dialog using AcceptDialog
	var dialog = AcceptDialog.new()
	dialog.title = "Error"
	dialog.dialog_text = message
	dialog.ok_button_text = "OK"

	# Add to scene tree
	add_child(dialog)
	active_dialogs.append(dialog)

	# Show dialog
	dialog.popup_centered()

	# Connect close signal to cleanup
	dialog.confirmed.connect(func(): _cleanup_dialog(dialog))
	dialog.canceled.connect(func(): _cleanup_dialog(dialog))


## Show confirmation dialog with callback
##
## Parameters:
##   message: Confirmation message/question to display
##   callback: Callable to invoke if user confirms (clicks "Yes")
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: 1 (character deletion), 7 (trade commit)
## Design: UIManager Autoload (lines 301-305)
##
## Displays a modal confirmation dialog with Yes/No buttons.
## Callback is only invoked if user clicks "Yes".
func show_confirm(message: String, callback: Callable) -> void:
	print("[UIManager] Confirm: %s" % message)

	# Create confirmation dialog
	var dialog = ConfirmationDialog.new()
	dialog.title = "Confirm"
	dialog.dialog_text = message
	dialog.ok_button_text = "Yes"
	dialog.cancel_button_text = "No"

	# Add to scene tree
	add_child(dialog)
	active_dialogs.append(dialog)

	# Show dialog
	dialog.popup_centered()

	# Connect signals
	dialog.confirmed.connect(func():
		callback.call()
		_cleanup_dialog(dialog)
	)
	dialog.canceled.connect(func(): _cleanup_dialog(dialog))


## Show loading dialog with message
##
## Parameters:
##   message: Loading message to display (e.g., "Authenticating...")
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: 1 (authentication), 2 (world entry)
## Design: UIManager Autoload (lines 301-305)
##
## Displays a modal loading spinner with message.
## Dialog blocks user input until hide_loading() is called.
func show_loading(message: String) -> void:
	print("[UIManager] Loading: %s" % message)

	# Hide existing loading dialog if any
	if current_loading_dialog != null:
		hide_loading()

	# Create loading dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Loading"
	dialog.dialog_text = message
	dialog.get_ok_button().visible = false  # Hide OK button for loading state
	dialog.unresizable = true

	# Add to scene tree
	add_child(dialog)
	current_loading_dialog = dialog

	# Show dialog
	dialog.popup_centered()


## Hide loading dialog
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: 1, 2
## Design: UIManager Autoload (lines 301-305)
##
## Closes the currently displayed loading dialog.
func hide_loading() -> void:
	if current_loading_dialog == null:
		return

	print("[UIManager] Hiding loading dialog")

	current_loading_dialog.queue_free()
	current_loading_dialog = null


## Cleanup dialog after close
##
## Parameters:
##   dialog: Dialog node to cleanup
##
## Internal helper to remove dialog from active list and free it.
func _cleanup_dialog(dialog: Control) -> void:
	active_dialogs.erase(dialog)
	dialog.queue_free()


## ============================================================================
## TOOLTIP SYSTEM
## ============================================================================

## Show tooltip with item/entity data
##
## Parameters:
##   item_data: Dictionary with tooltip information (name, description, stats, etc.)
##   position: Screen position to display tooltip (Vector2)
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: 6 (Inventory Management - item tooltips)
## Design: UIManager Autoload (lines 307-309)
##
## Displays a tooltip panel with formatted item/entity information.
## Tooltip follows mouse cursor or appears at specified position.
func show_tooltip(item_data: Dictionary, position: Vector2) -> void:
	# Hide existing tooltip if any
	if current_tooltip != null:
		hide_tooltip()

	# Create tooltip panel
	var tooltip = Panel.new()
	tooltip.name = "Tooltip"

	# Add label for tooltip content
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false

	# Format tooltip text
	var tooltip_text = _format_tooltip_text(item_data)
	label.text = tooltip_text

	tooltip.add_child(label)

	# Position tooltip
	tooltip.position = position
	tooltip.z_index = 1000  # Ensure tooltip is on top

	# Add to scene tree
	add_child(tooltip)
	current_tooltip = tooltip

	# Adjust size to fit content
	await get_tree().process_frame
	tooltip.size = label.size + Vector2(16, 16)  # Add padding


## Hide tooltip
##
## Task: 1.4 - Create UIManager Autoload
## Requirements: 6
## Design: UIManager Autoload (lines 307-309)
##
## Removes the currently displayed tooltip.
func hide_tooltip() -> void:
	if current_tooltip == null:
		return

	current_tooltip.queue_free()
	current_tooltip = null


## Format tooltip text from item data
##
## Parameters:
##   item_data: Dictionary with item information
##
## Returns: BBCode-formatted string for RichTextLabel
##
## Internal helper to format item data into readable tooltip text.
func _format_tooltip_text(item_data: Dictionary) -> String:
	var text = ""

	# Item name (with rarity color)
	var name = item_data.get("name", "Unknown Item")
	var rarity = item_data.get("rarity", "common")
	var rarity_color = _get_rarity_color(rarity)
	text += "[color=%s][b]%s[/b][/color]\n" % [rarity_color, name]

	# Item type
	if item_data.has("type"):
		text += "[color=gray]%s[/color]\n" % item_data.type

	text += "\n"

	# Description
	if item_data.has("description"):
		text += "%s\n\n" % item_data.description

	# Stats
	if item_data.has("stats"):
		var stats = item_data.stats
		for stat_name in stats.keys():
			var stat_value = stats[stat_name]
			text += "[color=green]%s: +%s[/color]\n" % [stat_name.capitalize(), stat_value]

	# Stack count
	if item_data.has("stack_count") and item_data.stack_count > 1:
		text += "\n[color=gray]Stack: %d[/color]" % item_data.stack_count

	return text


## Get rarity color for tooltip formatting
##
## Parameters:
##   rarity: Rarity string (common, uncommon, rare, epic, legendary)
##
## Returns: Color code string for BBCode
func _get_rarity_color(rarity: String) -> String:
	match rarity.to_lower():
		"common":
			return "white"
		"uncommon":
			return "lime"
		"rare":
			return "dodgerblue"
		"epic":
			return "purple"
		"legendary":
			return "orange"
		_:
			return "white"


## ============================================================================
## FLOATING TEXT SYSTEM (Damage Numbers, Messages)
## ============================================================================

## Show floating text at a world position
##
## Parameters:
##   text: Text to display
##   world_position: Position in world space (Vector2 or Vector3)
##   color: Color of the text
##
## Task: Combat feedback
## Requirements: 5 (Combat System)
##
## Displays floating text that animates upward and fades out.
func show_floating_text(text: String, world_position: Variant, color: Color = Color.WHITE) -> void:
	# Get the VFX container from the current zone scene
	var zone = get_tree().current_scene
	if zone == null:
		push_warning("[UIManager] Cannot show floating text: no current scene")
		return
	
	var vfx_container = zone.get_node_or_null("VFXContainer")
	if vfx_container == null:
		push_warning("[UIManager] Cannot show floating text: VFXContainer not found")
		return
	
	# Create floating text label
	var label = Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", 20)
	
	# Set position
	if world_position is Vector2:
		label.position = world_position
	elif world_position is Vector3:
		label.position = Vector2(world_position.x, world_position.y)
	else:
		push_warning("[UIManager] Invalid world_position type for floating text")
		label.queue_free()
		return
	
	# Add to VFX container
	vfx_container.add_child(label)
	
	# Animate upward and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 50, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.finished.connect(func(): label.queue_free())


## ============================================================================
## CONTEXT MENU SYSTEM
## ============================================================================

## Show context menu with options
##
## Parameters:
##   options: Array of option strings (e.g., ["Talk", "Trade", "Attack"])
##   entity: NPCEntity or PlayerEntity that was clicked
##   screen_position: Position to display menu (usually mouse position)
##   callback_obj: Object that will receive selection callbacks (defaults to entity)
##   callback_func: Method name to call on callback_obj when option selected
##
## Task: 7.1 - Implement NPC Interaction Menu
## Requirements: 12
## Design: NPC Interaction (lines 412-423)
##
## Spawns a context menu at the specified screen position with the given options.
## When an option is selected, calls callback_func on callback_obj with the option text.
func show_context_menu(options: Array[String], entity: Node, screen_position: Vector2, callback_obj: Object = null, callback_func: String = "") -> void:
	# Hide existing context menu if any
	if current_context_menu != null:
		hide_context_menu()

	# Create context menu instance
	var menu = context_menu_scene.instantiate()

	# Add to UIManager (makes it a top-level UI element)
	add_child(menu)
	current_context_menu = menu

	# Show menu with options
	menu.show_menu(options, entity, screen_position, callback_obj, callback_func)

	# Connect popup_hide signal to cleanup
	menu.popup_hide.connect(_on_context_menu_hidden)


## Hide context menu
##
## Task: 7.1 - Implement NPC Interaction Menu
## Requirements: 12
##
## Closes the currently displayed context menu.
func hide_context_menu() -> void:
	if current_context_menu == null:
		return

	current_context_menu.queue_free()
	current_context_menu = null


## Handle context menu hidden event
func _on_context_menu_hidden() -> void:
	# Cleanup when menu closes
	if current_context_menu != null:
		current_context_menu.queue_free()
		current_context_menu = null


## ============================================================================
## UTILITY FUNCTIONS
## ============================================================================

## Check if a panel is currently visible
##
## Parameters:
##   panel_name: Name of the panel to check
##
## Returns: true if panel is visible, false otherwise
func is_panel_visible(panel_name: String) -> bool:
	return panel_states.get(panel_name, false)


## Get all currently visible panels
##
## Returns: Array of panel names that are currently visible
func get_visible_panels() -> Array:
	var visible = []
	for panel_name in panel_states.keys():
		if panel_states[panel_name]:
			visible.append(panel_name)
	return visible
