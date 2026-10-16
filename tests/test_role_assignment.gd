extends SceneTree

class TestNetwork extends NetworkSession:
	func _start_upnp() -> void:
		pass # Loopback tests must never configure the router.

var failures: Array[String] = []
var branches: Array[Node] = []
var commands: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func make_peer(label: String) -> TestNetwork:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var session := TestNetwork.new()
	branch.add_child(session)
	branches.append(branch)
	return session

func wait_for(condition: Callable) -> bool:
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until:
		if condition.call(): return true
		await create_timer(0.02).timeout
	return condition.call()

func synchronized(peers: Array, count: int) -> bool:
	for peer in peers:
		if peer.roster.size() != count or peer.roster != peers[0].roster: return false
		if peer.role_assignments != peers[0].role_assignments: return false
		if not peer._valid_role_assignments(peer.roster, peer.role_assignments): return false
	return true

func check_coverage(session: NetworkSession, label: String) -> void:
	var departments: Array = []
	for peer_id in session.roster:
		departments.append_array(session.departments_for(int(peer_id)))
	departments.sort()
	var expected: Array = NetworkSession.DEPARTMENTS.duplicate()
	expected.sort()
	check(departments == expected, label + " gives every department exactly one owner")

func cleanup(peers: Array) -> void:
	for peer in peers: peer.close()
	await create_timer(0.1).timeout
	for branch in branches:
		set_multiplayer(null, branch.get_path())
		branch.queue_free()
	branches.clear()
	await process_frame

func run() -> void:
	var server := make_peer("Server")
	check(not server.can_do("change_role", 1, {"target_peer_id": 2}), "offline sessions cannot change roles")
	check(server._valid_payload("withdraw", {"unit_id": 0, "kind": "fire"}), "withdraw accepts a unit and department")
	for payload in [{}, {"unit_id": -1, "kind": "fire"}, {"unit_id": 1001, "kind": "fire"}, {"unit_id": 1.0, "kind": "fire"}, {"unit_id": 1, "kind": "unknown"}]:
		check(not server._valid_payload("withdraw", payload), "malformed withdrawal is rejected: " + str(payload))
	for payload in [{}, {"target_peer_id": 0}, {"target_peer_id": -1}, {"target_peer_id": 2147483648}, {"target_peer_id": "2"}]:
		check(not server._valid_payload("change_role", payload), "malformed role change is rejected: " + str(payload))
	check(server._clean_payload("withdraw", {"unit_id": 3, "kind": "fire", "extra": true}) == {"unit_id": 3, "kind": "fire"}, "withdraw strips unrelated fields")
	check(server._clean_payload("change_role", {"target_peer_id": 44, "extra": true}) == {"target_peer_id": 44}, "role changes strip unrelated fields")
	var fixture := {44: 0, 55: 1}
	check(server._valid_role_assignments(fixture, {44: 1, 55: 0}), "swapped assignment is valid")
	for assignments in [{44: 0}, {44: 0, 55: 0}, {44: 0, 55: 2}, {44: 0, 66: 1}, {44: 0, 55: "1"}]:
		check(not server._valid_role_assignments(fixture, assignments), "incomplete or invalid assignments are rejected: " + str(assignments))
	server.port = 27946
	check(server.host(true) == OK, "dedicated server starts")
	if not failures.is_empty():
		await cleanup([server])
		quit(1)
		return
	server.command_received.connect(func(action: String, payload: Dictionary, peer_id: int):
		commands.append({"action": action, "payload": payload, "peer_id": peer_id})
		if action == "change_role": server.swap_role(peer_id, int(payload.target_peer_id)))
	var first := make_peer("First")
	first.local_player_name = "Robin"
	check(first.join("127.0.0.1:27946") == OK, "first player connects")
	check(await wait_for(func(): return synchronized([server, first], 1)), "first player's departments synchronize")
	var second := make_peer("Second")
	check(second.join("127.0.0.1:27946") == OK, "second player connects")
	check(await wait_for(func(): return synchronized([server, first, second], 2)), "two-player departments synchronize")
	if not failures.is_empty():
		await cleanup([first, second, server])
		quit(1)
		return
	var first_id := first.multiplayer.get_unique_id()
	var second_id := second.multiplayer.get_unique_id()
	var seats := server.roster.duplicate()
	var names := server.player_names.duplicate()
	check(server.can_start_session(first_id) and not server.can_start_session(second_id), "first player leads the dedicated lobby")
	check(not first.swap_role(first_id, second_id), "clients cannot directly mutate authoritative assignments")
	check(not server.swap_role(first_id, first_id), "self swap is rejected")
	check(not server.swap_role(first_id, 999) and not server.swap_role(999, first_id), "unknown player swaps are rejected")
	first.send_command("change_role", {"target_peer_id": second_id})
	check(await wait_for(func(): return server.departments_for(first_id) == ["medic", "police"] and synchronized([server, first, second], 2)), "client command swaps and synchronizes department bundles")
	check(commands.size() == 1 and int(commands[0].peer_id) == first_id, "role command uses authenticated player identity")
	check(server.roster == seats and server.player_names == names, "swaps preserve seats and names")
	check(first.role == 0 and second.role == 1, "swaps preserve local seat identity")
	check(server.can_start_session(first_id) and not server.can_start_session(second_id), "swaps preserve dedicated lobby leader")
	check(server.departments_for(second_id) == ["fire", "engineer"], "target receives the actor's previous department bundle")
	check_coverage(server, "Two-player swap")
	check(server.can_do("withdraw", first_id, {"unit_id": 0, "kind": "medic"}), "new owner can withdraw their department's unit")
	check(not server.can_do("withdraw", first_id, {"unit_id": 0, "kind": "fire"}), "old owner cannot withdraw another department's unit")
	first.send_command("withdraw", {"unit_id": 3, "kind": "medic"})
	check(await wait_for(func(): return commands.size() == 2), "withdraw reaches the authoritative command handler")
	# Bypass client checks to verify that the host rejects forged ownership and
	# malformed commands before they reach the simulation.
	first._command.rpc_id(1, "withdraw", {"unit_id": 3, "kind": "fire"})
	first._command.rpc_id(1, "withdraw", {"unit_id": -1, "kind": "medic"})
	first._command.rpc_id(1, "change_role", {"target_peer_id": 999})
	await create_timer(0.15).timeout
	check(commands.size() == 2, "host rejects unauthorized withdrawal and unknown role target")
	var third := make_peer("Third")
	check(third.join("127.0.0.1:27946") == OK, "third player connects")
	check(await wait_for(func(): return synchronized([server, first, second, third], 3)), "late join receives reconciled assignments")
	check(server.role_assignments.get(first_id) == 1 and server.role_assignments.get(second_id) == 0, "late join preserves chosen assignment order")
	check_coverage(server, "Three-player join")
	var fourth := make_peer("Fourth")
	check(fourth.join("127.0.0.1:27946") == OK, "fourth player connects")
	check(await wait_for(func(): return synchronized([server, first, second, third, fourth], 4)), "four-player assignments synchronize")
	check_coverage(server, "Four-player join")
	second.close()
	check(await wait_for(func(): return synchronized([server, first, third, fourth], 3)), "departure synchronizes remaining assignments")
	check(not server.role_assignments.has(second_id), "departed player assignment is removed")
	check(server.roster.get(first_id) == seats[first_id] and server.can_start_session(first_id), "departure keeps remaining seats and leader stable")
	check_coverage(server, "Three-player departure")
	await cleanup([first, second, third, fourth, server])
	# LAN hosts remain seat zero while changing to a different department.
	var host_peer := make_peer("DesktopHost")
	host_peer.port = 27947
	check(host_peer.host() == OK, "desktop host starts")
	var guest := make_peer("DesktopGuest")
	check(guest.join("127.0.0.1:27947") == OK, "desktop guest connects")
	check(await wait_for(func(): return synchronized([host_peer, guest], 2)), "desktop roster synchronizes")
	var guest_id := guest.multiplayer.get_unique_id()
	check(host_peer.swap_role(1, guest_id), "LAN host can swap away from Fire")
	check(await wait_for(func(): return guest.departments_for(1) == ["medic", "police"] and synchronized([host_peer, guest], 2)), "LAN host role change reaches guest")
	check(host_peer.roster.get(1) == 0 and host_peer.role == 0 and host_peer.player_label(1) == "Player 1", "LAN host seat and label remain stable")
	check(host_peer.voice_participants.has(1), "LAN host voice identity remains assigned to peer one")
	check_coverage(host_peer, "LAN host swap")
	host_peer.close()
	check(host_peer.role_assignments.is_empty(), "closing the session clears role assignments")
	check(not host_peer.swap_role(1, guest_id), "closed sessions reject swaps")
	await cleanup([guest, host_peer])
	print("ROLE ASSIGNMENT TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
