extends Panel

# References to UI elements
@onready var tab_container = $MarginContainer/VBoxContainer/TabContainer
@onready var message_input = $MarginContainer/VBoxContainer/InputContainer/MessageInput
@onready var send_button = $MarginContainer/VBoxContainer/InputContainer/SendButton
@onready var toggle_button = $MarginContainer/VBoxContainer/Header/ToggleButton

# Message list containers for each tab
@onready var zone_message_list = $MarginContainer/VBoxContainer/TabContainer/Zone/ZoneScrollContainer/ZoneMessageList
@onready var guild_message_list = $MarginContainer/VBoxContainer/TabContainer/Guild/GuildScrollContainer/GuildMessageList
@onready var whisper_message_list = $MarginContainer/VBoxContainer/TabContainer/Whisper/WhisperScrollContainer/WhisperMessageList
@onready var system_message_list = $MarginContainer/VBoxContainer/TabContainer/System/SystemScrollContainer/SystemMessageList

# Scroll containers for auto-scroll
@onready var zone_scroll = $MarginContainer/VBoxContainer/TabContainer/Zone/ZoneScrollContainer
@onready var guild_scroll = $MarginContainer/VBoxContainer/TabContainer/Guild/GuildScrollContainer
@onready var whisper_scroll = $MarginContainer/VBoxContainer/TabContainer/Whisper/WhisperScrollContainer
@onready var system_scroll = $MarginContainer/VBoxContainer/TabContainer/System/SystemScrollContainer

# Nakama channel IDs (set when subscribing)
var zone_channel_id: String = ""
var guild_channel_id: String = ""

# Chat message component scene
var chat_message_scene = preload("res://scenes/ui/components/ChatMessage.tscn")

func _ready():
	# Subscribe to Nakama channel messages
	if NakamaManager.socket:
		NakamaManager.socket.received_channel_message.connect(_on_channel_message)

	# Connect to WorldState for zone/guild info
	if WorldState:
		WorldState.connect("snapshot_loaded", _on_snapshot_loaded)

func _on_snapshot_loaded():
	# Subscribe to zone chat channel
	subscribe_to_channels()

func subscribe_to_channels():
	# Subscribe to zone channel
	if WorldState.current_zone_id:
		zone_channel_id = "zone_" + WorldState.current_zone_id
		_subscribe_to_channel(zone_channel_id)
		add_system_message("Joined zone chat")

	# Subscribe to guild channel if player is in a guild
	if WorldState.player_guild_data and not WorldState.player_guild_data.is_empty():
		var guild_id = WorldState.player_guild_data.get("guild_id", "")
		if guild_id:
			guild_channel_id = "guild_" + guild_id
			_subscribe_to_channel(guild_channel_id)
			add_system_message("Joined guild chat")

func _subscribe_to_channel(channel_id: String):
	if not NakamaManager.socket:
		return

	# Join Nakama channel
	var result = await NakamaManager.socket.join_chat_async(channel_id, 2, true, false)
	if result.is_exception():
		print("Failed to join channel: ", channel_id)
		add_system_message("Failed to join channel: " + channel_id)

# Handle incoming channel messages
func _on_channel_message(message):
	var channel_id = message.channel_id
	var sender = message.username
	var content = message.content
	var timestamp = int(message.create_time)

	# Route to appropriate tab
	if channel_id == zone_channel_id:
		add_message_to_tab("zone", sender, content, timestamp)
	elif channel_id == guild_channel_id:
		add_message_to_tab("guild", sender, content, timestamp)
	else:
		# Unknown channel, add to system
		add_system_message("Message from %s: %s" % [sender, content])

func add_message_to_tab(tab_name: String, sender: String, content: String, timestamp: int):
	var message_list = get_message_list_for_tab(tab_name)
	var scroll_container = get_scroll_container_for_tab(tab_name)

	if not message_list:
		return

	# Create message node
	var msg_node = chat_message_scene.instantiate()
	message_list.add_child(msg_node)
	msg_node.set_message(sender, content, timestamp)

	# Auto-scroll to bottom
	await get_tree().process_frame
	if scroll_container:
		scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func add_system_message(content: String):
	var msg_node = chat_message_scene.instantiate()
	system_message_list.add_child(msg_node)
	msg_node.set_system_message(content)

	# Auto-scroll system tab
	await get_tree().process_frame
	system_scroll.scroll_vertical = int(system_scroll.get_v_scroll_bar().max_value)

func get_message_list_for_tab(tab_name: String) -> VBoxContainer:
	match tab_name:
		"zone":
			return zone_message_list
		"guild":
			return guild_message_list
		"whisper":
			return whisper_message_list
		"system":
			return system_message_list
		_:
			return null

func get_scroll_container_for_tab(tab_name: String) -> ScrollContainer:
	match tab_name:
		"zone":
			return zone_scroll
		"guild":
			return guild_scroll
		"whisper":
			return whisper_scroll
		"system":
			return system_scroll
		_:
			return null

func get_current_channel() -> String:
	var current_tab = tab_container.current_tab
	match current_tab:
		0: # Zone
			return zone_channel_id
		1: # Guild
			return guild_channel_id
		_:
			return zone_channel_id

# Send button pressed
func _on_send_button_pressed():
	send_message()

# Enter key pressed in input field
func _on_message_input_text_submitted(text: String):
	send_message()

func send_message():
	var message = message_input.text.strip_edges()

	if message.is_empty():
		return

	# Parse slash commands
	if message.begins_with("/"):
		parse_command(message)
	else:
		# Send to current channel
		send_to_channel(message)

	# Clear input
	message_input.text = ""

func parse_command(command: String):
	var parts = command.split(" ", true, 2)
	var cmd = parts[0].to_lower()

	if cmd == "/whisper" or cmd == "/w":
		if parts.size() < 3:
			add_system_message("Usage: /whisper <player> <message>")
			return

		var recipient = parts[1]
		var msg = parts[2]
		send_direct_message(recipient, msg)

	elif cmd == "/guild" or cmd == "/g":
		if parts.size() < 2:
			add_system_message("Usage: /guild <message>")
			return

		var msg = command.substr(cmd.length() + 1).strip_edges()
		send_to_guild_channel(msg)

	elif cmd == "/mute":
		if parts.size() < 2:
			add_system_message("Usage: /mute <player> [duration]")
			return

		var target = parts[1]
		moderate_player(target, "mute")

	elif cmd == "/kick":
		if parts.size() < 2:
			add_system_message("Usage: /kick <player>")
			return

		var target = parts[1]
		moderate_player(target, "kick")

	elif cmd == "/ban":
		if parts.size() < 2:
			add_system_message("Usage: /ban <player>")
			return

		var target = parts[1]
		moderate_player(target, "ban")

	else:
		add_system_message("Unknown command: " + cmd)

func send_to_channel(message: String):
	var channel = get_current_channel()

	if channel.is_empty():
		add_system_message("No channel selected")
		return

	# Call chat_send RPC via Nakama socket
	if NakamaManager.socket:
		var result = await NakamaManager.socket.write_chat_message_async(channel, {"message": message})
		if result.is_exception():
			add_system_message("Failed to send message")
			print("Chat send error: ", result)

func send_to_guild_channel(message: String):
	if guild_channel_id.is_empty():
		add_system_message("You are not in a guild")
		return

	# Switch to guild tab and send
	tab_container.current_tab = 1

	if NakamaManager.socket:
		var result = await NakamaManager.socket.write_chat_message_async(guild_channel_id, {"message": message})
		if result.is_exception():
			add_system_message("Failed to send guild message")
			print("Guild chat send error: ", result)

func send_direct_message(recipient: String, message: String):
	# Use send_direct_message RPC
	var success = await NakamaManager.send_direct_message(recipient, message)

	if success:
		# Add to whisper tab
		add_message_to_tab("whisper", "You → " + recipient, message, Time.get_unix_time_from_system())
		add_system_message("Whisper sent to " + recipient)
	else:
		add_system_message("Failed to send whisper to " + recipient)

func moderate_player(target_id: String, action: String):
	# Call moderate_player RPC
	var success = await NakamaManager.moderate_player(target_id, action)

	if success:
		match action:
			"mute":
				add_system_message("Player %s has been muted" % target_id)
			"kick":
				add_system_message("Player %s has been kicked" % target_id)
			"ban":
				add_system_message("Player %s has been banned" % target_id)
			_:
				add_system_message("Moderation action '%s' applied to %s" % [action, target_id])
	else:
		add_system_message("Failed to moderate player %s. You may not have permission." % target_id)

# Toggle panel visibility
func _on_toggle_button_pressed():
	var is_hidden = tab_container.visible
	tab_container.visible = not is_hidden
	message_input.visible = not is_hidden
	send_button.visible = not is_hidden

	toggle_button.text = "Show" if is_hidden else "Hide"
