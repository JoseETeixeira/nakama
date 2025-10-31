extends HBoxContainer

@onready var timestamp_label = $TimestampLabel
@onready var sender_label = $SenderLabel
@onready var message_label = $MessageLabel

var message_data: Dictionary = {}

func set_message(sender: String, content: String, unix_time: int) -> void:
	message_data = {
		"sender": sender,
		"content": content,
		"timestamp": unix_time
	}

	# Format timestamp
	var time_dict = Time.get_datetime_dict_from_unix_time(unix_time)
	timestamp_label.text = "%02d:%02d" % [time_dict.hour, time_dict.minute]

	# Set sender
	sender_label.text = sender + ":"

	# Set message content
	message_label.text = content

func set_system_message(content: String) -> void:
	# System messages have no sender, gray timestamp
	var time_dict = Time.get_datetime_dict_from_system()
	timestamp_label.text = "%02d:%02d" % [time_dict.hour, time_dict.minute]
	timestamp_label.modulate = Color(0.5, 0.5, 0.5, 1.0)

	sender_label.text = "[System]"
	sender_label.modulate = Color(1.0, 0.8, 0.0, 1.0)

	message_label.text = content
	message_label.modulate = Color(0.9, 0.9, 0.9, 1.0)
