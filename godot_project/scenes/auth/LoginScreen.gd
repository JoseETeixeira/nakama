## LoginScreen
##
## Authentication screen for device-based login.
##
## Task: 1.4.3 - Implement authentication screen
## Requirement: 1 (Player Authentication)
##
## This screen handles:
## - Device ID authentication
## - Session token storage
## - Transition to character selection on success
extends Control

@onready var login_button: Button = $VBoxContainer/LoginButton
@onready var status_label: Label = $VBoxContainer/StatusLabel


func _ready() -> void:
	status_label.text = "Ready to authenticate"


## Handle login button press
##
## Task: 1.4.3 - Implement authentication screen
func _on_login_button_pressed() -> void:
	login_button.disabled = true
	status_label.text = "Authenticating..."

	# Call NakamaManager singleton to authenticate
	await NakamaManager.authenticate_device()

	if NakamaManager.session != null:
		status_label.text = "Authentication successful!"
		print("[LoginScreen] Authentication successful. Transitioning to character select...")

		# Wait a moment before transitioning
		await get_tree().create_timer(1.0).timeout

		# Transition to character selection
		# TODO: Task 1.4.4 - Load CharacterSelect scene
		get_tree().change_scene_to_file("res://scenes/auth/CharacterSelect.tscn")
	else:
		status_label.text = "Authentication failed. Please try again."
		login_button.disabled = false
		push_error("[LoginScreen] Authentication failed")
