class_name NetworkSession
extends Node

signal command_received(action: String, payload: Dictionary, peer_id: int)
signal snapshot_received(data: Dictionary)
signal event_received(data: Dictionary)
signal roster_changed
signal message_received(text: String)
signal disconnected

const PORT := 24680
const ROLES := ["Dispatcher", "Resource manager", "Field coordinator", "Support lead"]
const ACTIONS := ["dispatch", "order", "scout", "supply", "special", "ping"]
const PRIMARY_ROLES := {
	"dispatch": [1], "order": [0], "scout": [2, 3],
	"supply": [1, 2], "special": [0, 3], "ping": [0, 1, 2, 3],
}
var active := false
var hosting := false
var role := 0
var roster: Dictionary = {}
var status := "Offline"
var _last_snapshot: Dictionary = {}
var _command_windows: Dictionary = {}

func _enter_tree() -> void:
	
	name = "NetworkSession"

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_failed)

func host() -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 3)
	if err != OK:
		status = "Could not open port %d" % PORT
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = true
	role = 0
	roster = {1: 0}
	status = "Room open · port %d" % PORT
	roster_changed.emit()
	return OK

func join(address: String) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), PORT)
	if err != OK:
		status = "Could not connect"
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = false
	role = 0
	status = "Connecting…"
	return OK

func close() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	hosting = false
	roster.clear()
	_last_snapshot.clear()
	_command_windows.clear()
	role = 0
	status = "Offline"

func send_command(action: String, payload: Dictionary = {}) -> void:
	if not can_do(action) or not _valid_payload(action, payload):
		return
	var clean_payload := _clean_payload(action, payload)
	if not active or hosting:
		command_received.emit(action, clean_payload, 1)
	else:
		_command.rpc_id(1, action, clean_payload)

func broadcast(data: Dictionary) -> void:
	if active and hosting:
		_last_snapshot = data.duplicate(true)
		if roster.size() > 1:
			_state.rpc(data)

func broadcast_event(data: Dictionary) -> void:
	
	
	if active and hosting and roster.size() > 1:
		_event.rpc(data)

func can_do(action: String, peer_id: int = -1) -> bool:
	if not ACTIONS.has(action):
		return false
	if not active:
		return peer_id < 0 or peer_id == 1
	var actor := multiplayer.get_unique_id() if peer_id < 0 else peer_id
	if not roster.has(actor):
		return false
	var assigned := int(roster[actor])
	if assigned < 0 or assigned >= ROLES.size():
		return false
	var primary: Array = PRIMARY_ROLES[action]
	if primary.has(assigned):
		return true
	
	
	if actor == 1:
		for occupied_role in roster.values():
			if primary.has(int(occupied_role)):
				return false
		return true
	return false

func _peer_connected(_id: int) -> void:
	pass

func _peer_disconnected(id: int) -> void:
	roster.erase(id)
	_command_windows.erase(id)
	if hosting:
		_roster.rpc(roster)
	roster_changed.emit()
	message_received.emit("A teammate left the room.")

func _connected() -> void:
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
		_roster.rpc_id(sender, roster)
		return
	var assigned := -1
	for i in range(1, 4):
		if not roster.values().has(i):
			assigned = i
			break
	if assigned < 0:
		return
	roster[sender] = assigned
	_roster.rpc(roster)
	if not _last_snapshot.is_empty():
		_initial_state.rpc_id(sender, _last_snapshot)
	roster_changed.emit()
	message_received.emit("%s joined the team." % ROLES[assigned])

@rpc("authority", "call_remote", "reliable")
func _roster(data: Dictionary) -> void:
	if hosting or multiplayer.get_remote_sender_id() != 1 or not _valid_roster(data):
		return
	roster = data.duplicate()
	role = int(roster.get(multiplayer.get_unique_id(), 0))
	roster_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _command(action: String, payload: Dictionary) -> void:
	if not active or not hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not roster.has(sender) or not can_do(action, sender):
		return
	if not _valid_payload(action, payload) or not _within_rate_limit(sender):
		return
	command_received.emit(action, _clean_payload(action, payload), sender)

@rpc("authority", "call_remote", "unreliable_ordered")
func _state(data: Dictionary) -> void:
	if active and not hosting and multiplayer.get_remote_sender_id() == 1:
		snapshot_received.emit(data)

@rpc("authority", "call_remote", "reliable")
func _initial_state(data: Dictionary) -> void:
	if active and not hosting and multiplayer.get_remote_sender_id() == 1:
		snapshot_received.emit(data)

@rpc("authority", "call_remote", "reliable")
func _event(data: Dictionary) -> void:
	if active and not hosting and multiplayer.get_remote_sender_id() == 1:
		event_received.emit(data)

func announce(text: String) -> void:
	message_received.emit(text)
	if active and hosting:
		_message.rpc(text)

@rpc("authority", "call_remote", "reliable")
func _message(text: String) -> void:
	if active and not hosting and multiplayer.get_remote_sender_id() == 1:
		message_received.emit(text.left(240))

func _valid_roster(data: Dictionary) -> bool:
	if data.size() < 1 or data.size() > 4 or data.get(1, -1) != 0:
		return false
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
	if payload.size() > 6:
		return false
	
	if action in ["dispatch", "order", "scout", "supply"]:
		if not payload.get("incident_id") is int:
			return false
		if int(payload.incident_id) <= 0 or int(payload.incident_id) > 1000000:
			return false
	if action == "dispatch":
		if payload.has("unit_id") and (not payload.unit_id is int or int(payload.unit_id)<-1 or int(payload.unit_id)>1000):
			return false
		return payload.get("kind") is String and payload.kind in ["fire", "medic", "engineer"]
	if action == "ping":
		return payload.get("text", "Help needed") is String and str(payload.get("text", "Help needed")).length() <= 96
	return ACTIONS.has(action)

func _clean_payload(action: String, payload: Dictionary) -> Dictionary:
	match action:
		"dispatch":
			return {"incident_id": int(payload.incident_id), "kind": str(payload.kind), "unit_id":int(payload.get("unit_id",-1))}
		"order", "scout", "supply":
			return {"incident_id": int(payload.incident_id)}
		"ping":
			return {"text": str(payload.get("text", "Help needed")).replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(96)}
	return {}

func _within_rate_limit(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var window: Dictionary = _command_windows.get(peer_id, {"start": now, "count": 0})
	if now - int(window.start) >= 1000:
		window = {"start": now, "count": 0}
	window.count = int(window.count) + 1
	_command_windows[peer_id] = window
	return int(window.count) <= 16
