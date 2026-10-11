extends SceneTree

const Net = preload("res://scripts/network_session.gd")
var received: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)


func deliver(network: NetworkSession, sequence: int, state: Dictionary) -> void:
	var raw := var_to_bytes(state)
	network._accept_snapshot(sequence, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size())


func _run() -> void:
	var network = Net.new()
	root.add_child(network)
	network.snapshot_received.connect(func(state: Dictionary): received.append(state))
	var large := {"elapsed": 12, "payload": Crypto.new().generate_random_bytes(4096)}
	var small := {"elapsed": 13}
	check(var_to_bytes(large).compress(FileAccess.COMPRESSION_ZSTD).size() > Net.UNRELIABLE_SNAPSHOT_LIMIT, "large fixture uses reliable transport")
	check(var_to_bytes(small).compress(FileAccess.COMPRESSION_ZSTD).size() <= Net.UNRELIABLE_SNAPSHOT_LIMIT, "small fixture fits unreliable transport")
	deliver(network, 10, {"elapsed": 10}) # Initial state.
	deliver(network, 13, small) # A newer small snapshot wins the race.
	deliver(network, 12, large) # Older reliable fragment finishes late.
	deliver(network, 11, {"elapsed": 11}) # Stale initial state is harmless too.
	deliver(network, 13, small) # Duplicate.
	check(received.size() == 2 and received.back().elapsed == 13, "cross-channel late and duplicate packets cannot rewind state")
	network._accept_snapshot(15, PackedByteArray(), 0)
	deliver(network, 14, {"elapsed": 14})
	check(received.size() == 3 and received.back().elapsed == 14, "invalid data cannot advance the sequence gate")
	deliver(network, 15, large)
	check(received.size() == 4 and network._received_snapshot_sequence == 15, "newer large snapshot is accepted")
	network.close()
	deliver(network, 1, {"elapsed": 0})
	check(received.size() == 5 and received.back().elapsed == 0, "new connection resets snapshot sequence")
	network.queue_free()
	await process_frame
	print("SNAPSHOT TRANSPORT TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
