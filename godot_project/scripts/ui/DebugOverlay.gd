extends CanvasLayer

# Debug Overlay - Requirement 13
# Displays diagnostic information for network state, performance, and entities

@onready var fps_label: Label = $Panel/MarginContainer/VBoxContainer/FPSLabel
@onready var latency_label: Label = $Panel/MarginContainer/VBoxContainer/LatencyLabel
@onready var tick_rate_label: Label = $Panel/MarginContainer/VBoxContainer/TickRateLabel
@onready var entity_count_label: Label = $Panel/MarginContainer/VBoxContainer/EntityCountLabel
@onready var delta_stats_label: Label = $Panel/MarginContainer/VBoxContainer/DeltaStatsLabel
@onready var spawn_events_label: Label = $Panel/MarginContainer/VBoxContainer/SpawnEventsLabel
@onready var memory_label: Label = $Panel/MarginContainer/VBoxContainer/MemoryLabel
@onready var performance_label: Label = $Panel/MarginContainer/VBoxContainer/PerformanceLabel
@onready var warning_label: Label = $Panel/MarginContainer/VBoxContainer/WarningLabel
@onready var network_log_text: Label = $Panel/MarginContainer/VBoxContainer/NetworkLogScroll/NetworkLogText

var visible_debug: bool = false
var spawn_count: int = 0
var despawn_count: int = 0
var network_log_lines: Array[String] = []
var last_tick_time: float = 0.0
var tick_count: int = 0
var server_tick_rate: float = 0.0
var performance_warning_time: float = 0.0  # Timer for fading warning messages

func _ready() -> void:
	# Start hidden
	visible = false

	# Connect to WorldState signals for delta and entity events
	if WorldState:
		if WorldState.has_signal("delta_applied"):
			WorldState.delta_applied.connect(_on_delta_applied)
		if WorldState.has_signal("entity_spawned"):
			WorldState.entity_spawned.connect(_on_entity_spawned)
		if WorldState.has_signal("entity_despawned"):
			WorldState.entity_despawned.connect(_on_entity_despawned)

	# Connect to NakamaManager signals for RPC logging
	if NakamaManager:
		if NakamaManager.has_signal("rpc_completed"):
			NakamaManager.rpc_completed.connect(_on_rpc_completed)
		if NakamaManager.has_signal("rpc_failed"):
			NakamaManager.rpc_failed.connect(_on_rpc_failed)
	
	# Connect to performance warning signals (Task 8.3)
	if WorldState:
		if WorldState.has_signal("delta_performance_warning"):
			WorldState.delta_performance_warning.connect(_on_performance_warning)

func _process(_delta: float) -> void:
	# F3 toggle
	if Input.is_action_just_pressed("ui_f3"):
		visible_debug = not visible_debug
		visible = visible_debug
	
	# F5 export snapshot (Task 8.3)
	if Input.is_action_just_pressed("ui_f5"):
		export_profiling_data()

	# Update stats if visible
	if visible_debug:
		update_stats()
	
	# Fade out performance warning (Task 8.3)
	if performance_warning_time > 0.0:
		performance_warning_time -= _delta
		if performance_warning_time <= 0.0:
			warning_label.text = ""

func update_stats() -> void:
	# FPS counter
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	# Network latency (get from NakamaManager if available)
	var latency: int = 0
	if NakamaManager and NakamaManager.has_method("get_latency"):
		latency = NakamaManager.get_latency()
	latency_label.text = "Latency: %d ms" % latency

	# Server tick rate (calculated from delta arrival frequency)
	tick_rate_label.text = "Server Tick Rate: %.1f Hz" % server_tick_rate

	# Entity count
	var entity_count: int = 0
	if WorldState and WorldState.has_method("get_all_entities"):
		entity_count = WorldState.get_all_entities().size()
	entity_count_label.text = "Entities: %d" % entity_count

	# Delta statistics (from WorldState.delta_stats if available)
	var stats_text: String = "Delta: "
	if WorldState and "delta_stats" in WorldState:
		var stats = WorldState.delta_stats
		var delta_size = stats.get("last_size", 0)
		var entity_count_updated = stats.get("last_entity_count", 0)
		var compression_ratio = stats.get("compression_ratio", 0.0)
		stats_text = "Delta: %d bytes, %d entities, %.2fx compression" % [delta_size, entity_count_updated, compression_ratio]
	else:
		stats_text = "Delta: No data"
	delta_stats_label.text = stats_text

	# Spawn/Despawn events
	spawn_events_label.text = "Spawn/Despawn: %d/%d" % [spawn_count, despawn_count]
	
	# Memory usage (Task 8.3)
	var memory_usage_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0
	memory_label.text = "Memory: %.1f MB" % memory_usage_mb
	
	# Performance profiling (Task 8.3)
	if WorldState and "performance_stats" in WorldState:
		var perf_stats = WorldState.performance_stats
		var delta_time = perf_stats.get("last_delta_time_ms", 0.0)
		var entity_time = perf_stats.get("last_entity_update_time_ms", 0.0)
		performance_label.text = "Delta: %.2fms | Entity: %.3fms" % [delta_time, entity_time]
		
		# Check for performance threshold warnings (Task 8.3)
		var max_delta_time = perf_stats.get("max_delta_time_ms", 0.0)
		var max_entity_time = perf_stats.get("max_entity_update_time_ms", 0.0)
		
		if delta_time > 10.0:
			show_performance_warning("Delta processing exceeded 10ms: %.1fms" % delta_time)
		elif max_delta_time > 10.0 and performance_warning_time <= 0.0:
			show_performance_warning("Max delta time: %.1fms" % max_delta_time)
	else:
		performance_label.text = "Performance: No data"

func _on_delta_applied(delta_size: int, entities_updated: int) -> void:
	# Add log entry for delta
	add_log_entry("[DELTA] Size: %d bytes, Updated: %d entities" % [delta_size, entities_updated])

	# Update tick rate calculation
	var current_time = Time.get_ticks_msec() / 1000.0
	if last_tick_time > 0:
		var delta_time = current_time - last_tick_time
		if delta_time > 0:
			# Exponential moving average for smooth tick rate
			var instant_rate = 1.0 / delta_time
			server_tick_rate = lerp(server_tick_rate, instant_rate, 0.2)
	last_tick_time = current_time
	tick_count += 1

func _on_entity_spawned(entity_id: String, _node: Node2D) -> void:
	spawn_count += 1
	add_log_entry("[SPAWN] Entity: %s" % entity_id)

func _on_entity_despawned(entity_id: String) -> void:
	despawn_count += 1
	add_log_entry("[DESPAWN] Entity: %s" % entity_id)

func _on_rpc_completed(rpc_name: String, _result: Variant) -> void:
	add_log_entry("[RPC] ✓ %s" % rpc_name)

func _on_rpc_failed(rpc_name: String, error: String) -> void:
	add_log_entry("[RPC] ✗ %s - Error: %s" % [rpc_name, error])

func add_log_entry(message: String) -> void:
	# Add timestamp
	var timestamp = Time.get_time_string_from_system()
	var log_line = "[%s] %s" % [timestamp, message]

	# Add to log lines array
	network_log_lines.append(log_line)

	# Keep only last 50 lines
	if network_log_lines.size() > 50:
		network_log_lines = network_log_lines.slice(-50)

	# Update display
	network_log_text.text = "\n".join(network_log_lines)

# Reset stats (for testing or when entering new zone)
func reset_stats() -> void:
	spawn_count = 0
	despawn_count = 0
	network_log_lines.clear()
	network_log_text.text = "No network activity yet..."
	last_tick_time = 0.0
	tick_count = 0
	server_tick_rate = 0.0


## Performance warning handler (Task 8.3)
func _on_performance_warning(elapsed_ms: int) -> void:
	show_performance_warning("Performance bottleneck: %dms delta processing" % elapsed_ms)


## Display performance warning message (Task 8.3)
func show_performance_warning(message: String) -> void:
	warning_label.text = "⚠ WARNING: %s" % message
	performance_warning_time = 3.0  # Show warning for 3 seconds
	print("[DebugOverlay] %s" % message)


## Export profiling data to file (Task 8.3 - F5 key)
## Requirement 13: Capture and save zone snapshot for analysis
func export_profiling_data() -> void:
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var filename = "user://profiling_data_%s.json" % timestamp
	
	var profiling_data = {
		"timestamp": Time.get_datetime_string_from_system(),
		"fps": Engine.get_frames_per_second(),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0,
		"entity_count": WorldState.get_entity_count() if WorldState else 0,
		"network_metrics": NakamaManager.get_network_metrics() if NakamaManager else {},
		"delta_stats": WorldState.delta_stats.duplicate() if WorldState and "delta_stats" in WorldState else {},
		"performance_stats": WorldState.performance_stats.duplicate() if WorldState and "performance_stats" in WorldState else {},
		"spawn_count": spawn_count,
		"despawn_count": despawn_count,
		"server_tick_rate": server_tick_rate,
		"network_log": network_log_lines.duplicate()
	}
	
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(profiling_data, "  "))
		file.close()
		print("[DebugOverlay] Profiling data exported to: %s" % filename)
		show_performance_warning("Profiling data exported to: %s" % filename)
	else:
		push_error("[DebugOverlay] Failed to export profiling data to: %s" % filename)
		show_performance_warning("Failed to export profiling data")
