extends Node
class_name ClientPrediction

## Client-side movement prediction module
## Queues pending inputs and applies them locally for responsive gameplay

# Signal emitted when server correction exceeds acceptable threshold
# Emitted with correction_delta (float) parameter for UI/analytics
signal large_correction_detected(correction_delta: float)

# Queue of pending moves: [{nonce: int, direction: Vector2, timestamp: int}]
var pending_moves: Array = []

# Next nonce to assign to move
var next_nonce: int = 0

# Last nonce acknowledged by server (for move cleanup)
var last_ack_nonce: int = -1

# Server's authoritative position
var server_position: Vector3 = Vector3.ZERO

# Predicted client position
var predicted_position: Vector3 = Vector3.ZERO

# Configuration
const MAX_PENDING_MOVES: int = 60  # ~1 second at 60 FPS
const CORRECTION_WARNING_THRESHOLD: float = 0.033  # 2 frames @ 60 FPS (Requirement 5)


## Queues a move for server acknowledgment
func queue_move(direction: Vector2, timestamp: int) -> int:
	var nonce = next_nonce
	next_nonce += 1

	# Prevent queue overflow
	if pending_moves.size() >= MAX_PENDING_MOVES:
		push_warning("ClientPrediction: Pending queue full, dropping oldest move")
		pending_moves.pop_front()

	pending_moves.append({
		"nonce": nonce,
		"direction": direction,
		"timestamp": timestamp
	})

	return nonce


## Applies move locally for instant client feedback
## Uses server-side physics rules for consistency
func apply_move_locally(direction: Vector2, delta: float) -> void:
	const MAX_SPEED = 10.0  # Must match server config

	# Normalize direction if magnitude > 1
	var movement_dir = direction
	if movement_dir.length() > 1.0:
		movement_dir = movement_dir.normalized()

	# Calculate velocity
	var velocity = Vector3(movement_dir.x, 0, movement_dir.y) * MAX_SPEED

	# Update predicted position
	predicted_position += velocity * delta


## Returns current predicted position
func get_predicted_position() -> Vector3:
	return predicted_position


## Sets server authoritative position (used on initial spawn or teleport)
func set_server_position(position: Vector3) -> void:
	server_position = position
	predicted_position = position
	pending_moves.clear()
	next_nonce = 0
	last_ack_nonce = -1


## Gets pending moves count for debug/metrics
func get_pending_count() -> int:
	return pending_moves.size()


## Handles server move acknowledgment
## Removes all moves with nonce <= ack_nonce from pending queue
func acknowledge_move(ack_nonce: int) -> void:
	# Update last acknowledged nonce
	last_ack_nonce = ack_nonce

	# Remove all acknowledged moves (nonce <= ack_nonce)
	var remaining_moves: Array = []
	for move in pending_moves:
		if move["nonce"] > ack_nonce:
			remaining_moves.append(move)

	# Update pending queue
	var removed_count = pending_moves.size() - remaining_moves.size()
	pending_moves = remaining_moves

	# Log for debugging (can be disabled in production)
	if removed_count > 0:
		print("ClientPrediction: Acknowledged %d move(s), %d pending" % [removed_count, pending_moves.size()])


## Gets last acknowledged nonce for debugging
func get_last_ack_nonce() -> int:
	return last_ack_nonce


## Reconciles client prediction with server correction
## Sets position to server truth and replays unacknowledged moves
func reconcile(correction: Vector3, ack_nonce: int) -> void:
	# Calculate correction delta (distance between predicted and server position)
	var correction_delta = predicted_position.distance_to(correction)

	# Step 1: Accept server's authoritative position as truth
	server_position = correction
	predicted_position = correction

	# Step 2: Replay all unacknowledged moves (nonce > ack_nonce)
	# This ensures client incorporates server correction while maintaining responsiveness
	const MAX_SPEED = 10.0  # Must match server config
	const ASSUMED_DELTA = 0.016  # Assume 60 FPS for replay

	for move in pending_moves:
		if move["nonce"] > ack_nonce:
			# Re-apply this move using same physics as apply_move_locally
			var movement_dir = move["direction"]
			if movement_dir.length() > 1.0:
				movement_dir = movement_dir.normalized()

			var velocity = Vector3(movement_dir.x, 0, movement_dir.y) * MAX_SPEED
			predicted_position += velocity * ASSUMED_DELTA

	# Log reconciliation for debugging
	print("ClientPrediction: Reconciled to server position ", correction, " with ", pending_moves.size(), " pending moves")

	# Emit warning signal if correction exceeds threshold (Requirement 5)
	if correction_delta > CORRECTION_WARNING_THRESHOLD:
		print("ClientPrediction: Large correction detected (%.3f units, threshold: %.3f)" % [correction_delta, CORRECTION_WARNING_THRESHOLD])
		large_correction_detected.emit(correction_delta)
