class_name NetworkSession
extends Node

signal command_received(action: String, payload: Dictionary, peer_id: int)
signal snapshot_received(data: Dictionary)
signal event_received(data: Dictionary)
signal roster_changed
signal message_received(text: String)
signal disconnected

const PORT := 24680
# Every player has the same job: command one (or more) emergency departments.
# Departments are split automatically by how many people are in the room.
const DEPARTMENTS: Array[String] = ["fire", "medic", "engineer", "police"]
const DEPARTMENT_NAMES := {"fire": "Fire", "medic": "Medical", "engineer": "Engineering", "police": "Police"}
const SPLITS := {
	1: [["fire", "medic", "engineer", "police"]],
	2: [["fire", "engineer"], ["medic", "police"]],
	3: [["fire", "police"], ["medic"], ["engineer"]],
	4: [["fire"], ["medic"], ["engineer"], ["police"]],
}
const ACTIONS := ["dispatch", "scout", "supply", "special", "ping", "start_shift"]
var active := false
var hosting := false
var dedicated := false
# Seat number in the room (0 = host). Kept under the old name so research logs stay comparable.
var role := 0
var roster: Dictionary = {}
var status := "Offline"
var _last_snapshot: Dictionary = {}
var _command_windows: Dictionary = {}
# Internet play: the host tries to open the port on its router (UPnP) in the background.
var internet_status := ""
var internet_address := ""
var _upnp: UPNP
var _upnp_thread: Thread
var _connect_started_ms := -1
var _join_address := ""
const CONNECT_TIMEOUT_MS := 9000

func _enter_tree() -> void:
	
	name = "NetworkSession"

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_failed)

func host(server_only: bool = false) -> Error:
	close()
	dedicated = server_only
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 4 if dedicated else 3)
	if err != OK:
		status = "Could not open port %d (is another copy of the game already hosting?)" % PORT
		return err
	# Snapshots are large; compression keeps them under one network packet.
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.server_relay = not dedicated
	multiplayer.multiplayer_peer = peer
	if not dedicated: _start_upnp()
	active = true
	hosting = true
	role = -1 if dedicated else 0
	roster = {} if dedicated else {1: 0}
	status = "Room open · port %d" % PORT
	roster_changed.emit()
	return OK

func join(address: String) -> Error:
	close()
	var target := address.strip_edges()
	var port := PORT
	# Accept "1.2.3.4:24680" as well as a bare address.
	if target.count(":") == 1:
		port = int(target.get_slice(":", 1))
		target = target.get_slice(":", 0)
	if target.is_empty():
		status = "Type the host's IP address first"
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(target, port)
	if err != OK:
		status = "Could not connect to %s" % target
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_connect_started_ms = Time.get_ticks_msec()
	_join_address = target
	active = true
	hosting = false
	role = 0
	status = "Connecting…"
	return OK

func _process(_delta: float) -> void:
	# ENet waits ~30 s before giving up; tell the player much sooner.
	if active and not hosting and _connect_started_ms >= 0 and Time.get_ticks_msec() - _connect_started_ms > CONNECT_TIMEOUT_MS:
		var address := _join_address
		close()
		status = "No answer from %s. Check the address, that both computers are on the same network (or VPN), and that the host allowed Beacon Bay through the firewall." % address
		disconnected.emit()

# Round trip to the host in milliseconds (0 when hosting or offline).
func round_trip_ms() -> int:
	if not active or hosting: return 0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null: return 0
	var host_peer: ENetPacketPeer = enet.get_peer(1)
	if host_peer == null: return 0
	return int(host_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

func close() -> void:
	_connect_started_ms = -1
	_close_upnp()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	multiplayer.server_relay = true
	dedicated = false
	active = false
	hosting = false
	roster.clear()
	_last_snapshot.clear()
	_command_windows.clear()
	role = 0
	status = "Offline"

func send_command(action: String, payload: Dictionary = {}) -> void:
	if not can_do(action, -1, payload) or not _valid_payload(action, payload):
		return
	var clean_payload := _clean_payload(action, payload)
	if not active or hosting:
		command_received.emit(action, clean_payload, 1)
	else:
		_command.rpc_id(1, action, clean_payload)

func broadcast(data: Dictionary) -> void:
	if active and hosting:
		_last_snapshot = data.duplicate(true)
		if multiplayer.get_peers().size() > 0:
			# The game state is ~10x smaller compressed, so it fits in a few network packets.
			var raw := var_to_bytes(data)
			_state.rpc(raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size())

static func _unpack(packed: PackedByteArray, size: int) -> Dictionary:
	if size <= 0 or size > 8 * 1024 * 1024:
		return {}
	var raw := packed.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return {}
	var value: Variant = bytes_to_var(raw)
	return value if value is Dictionary else {}

func broadcast_event(data: Dictionary) -> void:
	
	
	if active and hosting and multiplayer.get_peers().size() > 0:
		_event.rpc(data)

func can_do(action: String, peer_id: int = -1, payload: Dictionary = {}) -> bool:
	if action == "start_shift": return can_start_session(peer_id)
	if not ACTIONS.has(action):
		return false
	if not active:
		return peer_id < 0 or peer_id == 1
	var actor := multiplayer.get_unique_id() if peer_id < 0 else peer_id
	if not roster.has(actor):
		return false
	if action == "dispatch":
		return owns(str(payload.get("kind", "")), actor)
	# Scouting, supplies, the team boost and pings are shared by everyone.
	return true

func can_start_session(peer_id: int = -1) -> bool:
	if not active or not dedicated or roster.is_empty(): return false
	var actor := multiplayer.get_unique_id() if peer_id < 0 else peer_id
	# Dictionary insertion order keeps this independent of department/seat assignment.
	return actor == int(roster.keys()[0])

func departments_for(peer_id: int = -1) -> Array:
	if not active:
		return DEPARTMENTS.duplicate()
	var actor := multiplayer.get_unique_id() if peer_id < 0 else peer_id
	if not roster.has(actor):
		return []
	var seats: Array = roster.values()
	seats.sort()
	var split: Array = SPLITS.get(clampi(seats.size(), 1, 4), SPLITS[1])
	var rank: int = seats.find(int(roster[actor]))
	if rank < 0 or rank >= split.size():
		return []
	return split[rank].duplicate()

func owns(kind: String, peer_id: int = -1) -> bool:
	if kind == "medical":
		kind = "medic"
	return departments_for(peer_id).has(kind)

func owner_of(kind: String) -> int:
	for peer_id in roster:
		if owns(kind, int(peer_id)):
			return int(peer_id)
	return -1

func player_label(peer_id: int) -> String:
	if not roster.has(peer_id):
		return "Player"
	return "Player %d" % (int(roster[peer_id]) + 1)

func departments_text(peer_id: int = -1) -> String:
	var names: Array[String] = []
	for kind in departments_for(peer_id):
		names.append(str(DEPARTMENT_NAMES.get(kind, kind)).to_upper())
	return " + ".join(names) if not names.is_empty() else "NO DEPARTMENT"

func assignment_summary() -> String:
	var parts: Array[String] = []
	var peers: Array = roster.keys()
	peers.sort_custom(func(a, b): return int(roster[a]) < int(roster[b]))
	for peer_id in peers:
		parts.append("%s: %s" % [player_label(int(peer_id)), departments_text(int(peer_id))])
	return "  ·  ".join(parts)

func _peer_connected(_id: int) -> void:
	pass

func _peer_disconnected(id: int) -> void:
	var label := player_label(id)
	roster.erase(id)
	_command_windows.erase(id)
	if hosting:
		if dedicated: _broadcast_roster.call_deferred()
		else: _roster.rpc(roster, dedicated)
	roster_changed.emit()
	if hosting:
		var text := "%s left. Departments reshuffled. %s" % [label, assignment_summary()]
		if dedicated: announce.call_deferred(text)
		else: announce(text)

func _broadcast_roster() -> void:
	# Wait until ENet finishes removing disconnected peers before sending.
	if active and hosting and multiplayer.get_peers().size() > 0:
		_roster.rpc(roster, dedicated)

func _connected() -> void:
	_connect_started_ms = -1
	status = "Connected to Beacon Bay"
	_hello.rpc_id(1)

func _failed() -> void:
	close()
	status = "Connection ended. Check the host address and firewall."
	disconnected.emit()

@rpc("any_peer", "call_remote", "reliable")
func _hello() -> void:
	if not active or not hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not multiplayer.get_peers().has(sender):
		return
	
	if roster.has(sender):
		_roster.rpc_id(sender, roster, dedicated)
		return
	var assigned := -1
	for i in range(0 if dedicated else 1, 4):
		if not roster.values().has(i):
			assigned = i
			break
	if assigned < 0:
		return
	roster[sender] = assigned
	_roster.rpc(roster, dedicated)
	if not _last_snapshot.is_empty():
		var raw := var_to_bytes(_last_snapshot)
		_initial_state.rpc_id(sender, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size())
	roster_changed.emit()
	announce("%s joined. %s" % [player_label(sender), assignment_summary()])

@rpc("authority", "call_remote", "reliable")
func _roster(data: Dictionary, server_only: bool = false) -> void:
	if hosting or multiplayer.get_remote_sender_id() != 1 or not _valid_roster(data, server_only):
		return
	dedicated = server_only
	roster = data.duplicate()
	role = int(roster.get(multiplayer.get_unique_id(), 0))
	roster_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _command(action: String, payload: Dictionary) -> void:
	if not active or not hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not roster.has(sender):
		return
	if not _valid_payload(action, payload) or not _within_rate_limit(sender):
		return
	var clean := _clean_payload(action, payload)
	if not can_do(action, sender, clean):
		return
	command_received.emit(action, clean, sender)

@rpc("authority", "call_remote", "unreliable_ordered")
func _state(packed: PackedByteArray, size: int) -> void:
	if active and not hosting and multiplayer.get_remote_sender_id() == 1:
		var data := _unpack(packed, size)
		if not data.is_empty(): snapshot_received.emit(data)

@rpc("authority", "call_remote", "reliable")
func _initial_state(packed: PackedByteArray, size: int) -> void:
	if active and not hosting and multiplayer.get_remote_sender_id() == 1:
		var data := _unpack(packed, size)
		if not data.is_empty(): snapshot_received.emit(data)

@rpc("authority", "call_remote", "reliable")
func _event(data: Dictionary) -> void:
	if active and not hosting and multiplayer.get_remote_sender_id() == 1:
		event_received.emit(data)

func announce(text: String) -> void:
	message_received.emit(text)
	if active and hosting and multiplayer.get_peers().size() > 0:
		_message.rpc(text)

@rpc("authority", "call_remote", "reliable")
func _message(text: String) -> void:
	if active and not hosting and multiplayer.get_remote_sender_id() == 1:
		message_received.emit(text.left(240))

func _valid_roster(data: Dictionary, server_only: bool = false) -> bool:
	if data.size() > 4:
		return false
	if server_only and data.has(1): return false
	if not server_only and (data.is_empty() or data.get(1, -1) != 0): return false
	var assigned: Array[int] = []
	for peer_id in data:
		if not peer_id is int or peer_id <= 0 or not data[peer_id] is int:
			return false
		var peer_role: int = data[peer_id]
		if peer_role < 0 or peer_role > 3 or assigned.has(peer_role):
			return false
		assigned.append(peer_role)
	return true

func _valid_payload(action: String, payload: Dictionary) -> bool:
	if action == "start_shift": return payload.is_empty()
	if payload.size() > 6:
		return false
	
	if action in ["dispatch", "scout", "supply"]:
		if not payload.get("incident_id") is int:
			return false
		if int(payload.incident_id) <= 0 or int(payload.incident_id) > 1000000:
			return false
	if action == "dispatch":
		if payload.has("unit_id") and (not payload.unit_id is int or int(payload.unit_id)<-1 or int(payload.unit_id)>1000):
			return false
		return payload.get("kind") is String and payload.kind in DEPARTMENTS
	if action == "ping":
		return payload.get("text", "Help needed") is String and str(payload.get("text", "Help needed")).length() <= 96
	return ACTIONS.has(action)

func _clean_payload(action: String, payload: Dictionary) -> Dictionary:
	match action:
		"dispatch":
			return {"incident_id": int(payload.incident_id), "kind": str(payload.kind), "unit_id":int(payload.get("unit_id",-1))}
		"scout", "supply":
			return {"incident_id": int(payload.incident_id)}
		"ping":
			return {"text": str(payload.get("text", "Help needed")).replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(96)}
	return {}

func _start_upnp() -> void:
	internet_status = "Checking your router for internet play…"
	internet_address = ""
	if _upnp_thread != null:
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker)

func _upnp_worker() -> void:
	var upnp := UPNP.new()
	var result := {"ok": false, "text": "Internet: router did not allow automatic setup. Use LAN or a VPN like Tailscale.", "upnp": null, "ip": ""}
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	if err == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() != null and upnp.get_gateway().is_valid_gateway():
		if upnp.add_port_mapping(PORT, PORT, "Beacon Bay", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
			var ip := upnp.query_external_address()
			result = {"ok": true, "text": "", "upnp": upnp, "ip": ip}
		else:
			result.text = "Internet: router refused to open port %d. Use LAN or a VPN like Tailscale." % PORT
	call_deferred("_upnp_done", result)

func _upnp_done(result: Dictionary) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	var upnp: UPNP = result.get("upnp")
	if not hosting:
		if upnp != null: upnp.delete_port_mapping(PORT, "UDP")
		return
	_upnp = upnp
	if bool(result.ok):
		var ip := str(result.ip)
		internet_address = ip
		if ip.begins_with("100.") or ip.begins_with("10.") or ip.begins_with("192.168.") or ip.begins_with("172."):
			internet_status = "Internet: port opened, but your provider shares its public IP (%s). Use a VPN like Tailscale." % ip
		else:
			internet_status = "Internet: friends can join %s" % ip
	else:
		internet_status = str(result.text)

func _close_upnp() -> void:
	internet_status = ""
	internet_address = ""
	if _upnp_thread != null:
		# Let the background check finish; _upnp_done cleans up because we are no longer hosting.
		return
	if _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
		_upnp = null
	internet_status = ""
	internet_address = ""

func _exit_tree() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
		_upnp = null

func _within_rate_limit(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var window: Dictionary = _command_windows.get(peer_id, {"start": now, "count": 0})
	if now - int(window.start) >= 1000:
		window = {"start": now, "count": 0}
	window.count = int(window.count) + 1
	_command_windows[peer_id] = window
	return int(window.count) <= 16
