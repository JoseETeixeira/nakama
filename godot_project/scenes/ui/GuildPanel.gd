extends Panel

# References to UI elements
@onready var title_label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var no_guild_container = $MarginContainer/VBoxContainer/NoGuildContainer
@onready var create_guild_dialog = $MarginContainer/VBoxContainer/NoGuildContainer/CreateGuildDialog
@onready var guild_name_input = $MarginContainer/VBoxContainer/NoGuildContainer/CreateGuildDialog/GuildNameInput
@onready var guild_tag_input = $MarginContainer/VBoxContainer/NoGuildContainer/CreateGuildDialog/GuildTagInput

# Tabbed guild interface
@onready var tab_container = $MarginContainer/VBoxContainer/TabContainer

# Info tab
@onready var guild_name_label = $MarginContainer/VBoxContainer/TabContainer/Info/GuildNameLabel
@onready var guild_tag_label = $MarginContainer/VBoxContainer/TabContainer/Info/GuildTagLabel
@onready var motd_display = $MarginContainer/VBoxContainer/TabContainer/Info/MOTDDisplay
@onready var edit_motd_label = $MarginContainer/VBoxContainer/TabContainer/Info/EditMOTDLabel
@onready var motd_input = $MarginContainer/VBoxContainer/TabContainer/Info/MOTDInput
@onready var save_motd_button = $MarginContainer/VBoxContainer/TabContainer/Info/SaveMOTDButton

# Roster tab
@onready var invite_button = $MarginContainer/VBoxContainer/TabContainer/Roster/HeaderContainer/InviteButton
@onready var invite_dialog = $MarginContainer/VBoxContainer/TabContainer/Roster/InviteDialog
@onready var player_id_input = $MarginContainer/VBoxContainer/TabContainer/Roster/InviteDialog/PlayerIDInput
@onready var roster_list = $MarginContainer/VBoxContainer/TabContainer/Roster/RosterScrollContainer/RosterList

# Storage tab
@onready var storage_grid = $MarginContainer/VBoxContainer/TabContainer/Storage/StorageScrollContainer/StorageGrid

# State
var guild_data: Dictionary = {}
var player_rank: int = 0  # 0 = member, 1 = officer, 2 = leader
var item_slot_scene = preload("res://scenes/ui/components/ItemSlot.tscn")

# Rank names
var RANK_NAMES = {
	0: "Member",
	1: "Officer",
	2: "Leader"
}

func _ready():
	# Connect to WorldState for guild data updates
	if WorldState:
		WorldState.connect("entity_updated", _on_world_state_updated)

	refresh_guild_data()

func refresh_guild_data():
	# Get guild data from WorldState
	if WorldState and WorldState.has("player_guild_data"):
		guild_data = WorldState.player_guild_data
	else:
		guild_data = {}

	# Determine player's rank
	if guild_data.has("member_rank"):
		player_rank = guild_data.get("member_rank", 0)

	update_display()

func update_display():
	if guild_data.is_empty():
		# Show no guild UI
		no_guild_container.visible = true
		tab_container.visible = false
	else:
		# Show guild tabs
		no_guild_container.visible = false
		tab_container.visible = true

		# Update Info tab
		var guild_name = guild_data.get("name", "Unknown Guild")
		var guild_tag = guild_data.get("tag", "TAG")
		var motd = guild_data.get("motd", "Welcome to the guild!")

		title_label.text = "Guild: " + guild_name
		guild_name_label.text = "Guild Name: " + guild_name
		guild_tag_label.text = "Tag: [" + guild_tag + "]"
		motd_display.text = motd
		motd_input.text = motd

		# Show MOTD editing for officers and leaders
		var can_edit_motd = player_rank >= 1
		edit_motd_label.visible = can_edit_motd
		motd_input.visible = can_edit_motd
		save_motd_button.visible = can_edit_motd

		# Update Roster tab
		populate_roster()

		# Show invite button for leaders and officers
		invite_button.visible = player_rank >= 1

		# Update Storage tab
		populate_storage()

func populate_roster():
	# Clear existing roster entries
	for child in roster_list.get_children():
		child.queue_free()

	# Get roster from guild data
	var roster = guild_data.get("roster", [])

	for member in roster:
		var member_entry = create_roster_entry(member)
		roster_list.add_child(member_entry)

func create_roster_entry(member: Dictionary) -> HBoxContainer:
	var entry = HBoxContainer.new()

	# Member name
	var name_label = Label.new()
	name_label.text = member.get("name", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(name_label)

	# Rank label
	var rank_id = member.get("rank", 0)
	var rank_label = Label.new()
	rank_label.text = RANK_NAMES.get(rank_id, "Member")
	rank_label.custom_minimum_size = Vector2(80, 0)
	entry.add_child(rank_label)

	# Admin controls (only for leaders)
	if player_rank >= 2:
		# Promote button (if not already leader)
		if rank_id < 2:
			var promote_button = Button.new()
			promote_button.text = "Promote"
			promote_button.custom_minimum_size = Vector2(70, 0)
			promote_button.pressed.connect(_on_promote_pressed.bind(member.get("id", ""), rank_id))
			entry.add_child(promote_button)

		# Demote button (if not member)
		if rank_id > 0:
			var demote_button = Button.new()
			demote_button.text = "Demote"
			demote_button.custom_minimum_size = Vector2(70, 0)
			demote_button.pressed.connect(_on_demote_pressed.bind(member.get("id", ""), rank_id))
			entry.add_child(demote_button)

		# Kick button (can't kick self or other leaders)
		var is_self = member.get("id", "") == WorldState.player_entity_id
		if not is_self and rank_id < 2:
			var kick_button = Button.new()
			kick_button.text = "Kick"
			kick_button.custom_minimum_size = Vector2(60, 0)
			kick_button.pressed.connect(_on_kick_pressed.bind(member.get("id", "")))
			entry.add_child(kick_button)

	return entry

func populate_storage():
	# Clear existing storage slots
	for child in storage_grid.get_children():
		child.queue_free()

	# Get storage items from guild data
	var storage_items = guild_data.get("storage", [])

	# Create item slots for storage
	for item in storage_items:
		var slot = item_slot_scene.instantiate()
		storage_grid.add_child(slot)
		slot.set_item(item)

		# Connect click to withdraw
		slot.gui_input.connect(_on_storage_item_clicked.bind(item))

	# Add empty slots to fill grid (up to 50 total)
	var empty_slots_needed = 50 - storage_items.size()
	for i in range(empty_slots_needed):
		var slot = item_slot_scene.instantiate()
		storage_grid.add_child(slot)

		# Connect drop event for deposits
		if slot.has_signal("item_dropped"):
			slot.item_dropped.connect(_on_storage_item_dropped)

# Guild Creation Flow
func _on_create_guild_button_pressed():
	create_guild_dialog.visible = true

func _on_create_cancel_button_pressed():
	create_guild_dialog.visible = false
	guild_name_input.text = ""
	guild_tag_input.text = ""

func _on_create_confirm_button_pressed():
	var guild_name = guild_name_input.text.strip_edges()
	var guild_tag = guild_tag_input.text.strip_edges().to_upper()

	# Validation
	if guild_name.is_empty():
		UIManager.show_error("Guild name cannot be empty")
		return

	if guild_tag.length() < 3 or guild_tag.length() > 5:
		UIManager.show_error("Guild tag must be 3-5 characters")
		return

	# Call guild_create RPC
	var result = await NakamaManager.guild_create(guild_name, guild_tag)

	if result:
		UIManager.show_message("Guild created successfully!")
		create_guild_dialog.visible = false
		guild_name_input.text = ""
		guild_tag_input.text = ""

		# Refresh guild data
		refresh_guild_data()
	else:
		UIManager.show_error("Failed to create guild. Name or tag may be taken.")

# Invite Flow
func _on_invite_button_pressed():
	invite_dialog.visible = true

func _on_cancel_invite_button_pressed():
	invite_dialog.visible = false
	player_id_input.text = ""

func _on_send_invite_button_pressed():
	var target_id = player_id_input.text.strip_edges()

	if target_id.is_empty():
		UIManager.show_error("Player ID cannot be empty")
		return

	# Call guild_invite RPC
	var success = await NakamaManager.guild_invite(target_id)

	if success:
		UIManager.show_message("Invite sent to " + target_id)
		invite_dialog.visible = false
		player_id_input.text = ""
	else:
		UIManager.show_error("Failed to send invite")

# Rank Management
func _on_promote_pressed(member_id: String, current_rank: int):
	var new_rank = current_rank + 1

	# Call guild_set_rank RPC
	var success = await NakamaManager.guild_set_rank(member_id, new_rank)

	if success:
		UIManager.show_message("Member promoted")
		refresh_guild_data()
	else:
		UIManager.show_error("Failed to promote member")

func _on_demote_pressed(member_id: String, current_rank: int):
	var new_rank = current_rank - 1

	# Call guild_set_rank RPC
	var success = await NakamaManager.guild_set_rank(member_id, new_rank)

	if success:
		UIManager.show_message("Member demoted")
		refresh_guild_data()
	else:
		UIManager.show_error("Failed to demote member")

func _on_kick_pressed(member_id: String):
	# Call guild_kick RPC
	var success = await NakamaManager.guild_kick(member_id)

	if success:
		UIManager.show_message("Member kicked from guild")
		refresh_guild_data()
	else:
		UIManager.show_error("Failed to kick member")

# MOTD Management
func _on_save_motd_button_pressed():
	var new_motd = motd_input.text.strip_edges()

	# Call guild_set_motd RPC
	var success = await NakamaManager.guild_set_motd(new_motd)

	if success:
		UIManager.show_message("MOTD updated")
		motd_display.text = new_motd
		refresh_guild_data()
	else:
		UIManager.show_error("Failed to update MOTD")

# Storage Management
func _on_storage_item_clicked(event: InputEvent, item: Dictionary):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		withdraw_item(item)

func withdraw_item(item: Dictionary):
	var item_id = item.get("id", "")

	if item_id.is_empty():
		return

	# Call guild_storage_withdraw RPC
	var success = await NakamaManager.guild_storage_withdraw(item_id)

	if success:
		UIManager.show_message("Withdrew: " + item.get("name", "item"))
		refresh_guild_data()
	else:
		UIManager.show_error("Failed to withdraw item")

func _on_storage_item_dropped(from_slot: int, to_slot: int):
	# Get item from player inventory
	if not WorldState.player_inventory or from_slot >= WorldState.player_inventory.size():
		return

	var item = WorldState.player_inventory[from_slot]
	if item.is_empty():
		return

	var item_id = item.get("id", "")
	if item_id.is_empty():
		return

	# Call guild_storage_deposit RPC
	var success = await NakamaManager.guild_storage_deposit(item_id)

	if success:
		UIManager.show_message("Deposited: " + item.get("name", "item"))
		refresh_guild_data()
	else:
		UIManager.show_error("Failed to deposit item")

# WorldState updates
func _on_world_state_updated(entity_id: String, data: Dictionary):
	# Refresh guild data when player entity updates
	if entity_id == WorldState.player_entity_id:
		refresh_guild_data()

# Close panel
func _on_close_button_pressed():
	hide()
