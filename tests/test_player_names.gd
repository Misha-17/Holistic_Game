extends SceneTree

class TestNetwork extends NetworkSession:
	func _start_upnp() -> void:
		pass # Local test only; never configure the router.

var failures: Array[String] = []
var branches: Array[Node] = []

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

func wait_roster(peers: Array, count: int) -> bool:
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until:
		var ready := true
		for peer in peers:
			if peer.roster.size() != count: ready = false
		if ready: return true
		await create_timer(0.02).timeout
	for peer in peers:
		print("HANDSHAKE DIAGNOSTIC ", peer.get_path(), " status=", peer.status, " peers=", peer.multiplayer.get_peers(), " roster=", peer.roster)
	return false

func cleanup(peers: Array) -> void:
	for peer in peers:
		peer.close()
	await create_timer(0.1).timeout
	for branch in branches:
		set_multiplayer(null, branch.get_path())
		branch.queue_free()
	branches.clear()
	await process_frame

func run() -> void:
	check(NetworkSession.clean_player_name("  Robin   Smith  ") == "Robin Smith", "names normalize spaces")
	check(NetworkSession.clean_player_name("Robin\n\t[admin]") == "Robinadmin", "names cannot inject log lines or markup")
	check(NetworkSession.clean_player_name("Олена") == "", "non-Latin names are excluded")
	check(NetworkSession.clean_player_name("Anne-Marie O'Neil 2") == "Anne-Marie O'Neil 2", "supported Latin name characters survive")
	check(NetworkSession.clean_player_name("a".repeat(80)).length() == 20, "names have bounded length")
	var server := make_peer("Server")
	server.port = 27943
	check(server.host(true) == OK, "dedicated server starts")
	if not failures.is_empty():
		await cleanup([server])
		quit(1)
		return
	var robin := make_peer("RobinClient")
	robin.local_player_name = "Robin"
	check(robin.join("127.0.0.1:27943") == OK, "Robin connects")
	check(await wait_roster([server, robin], 1), "first handshake completes")
	if not failures.is_empty():
		await cleanup([robin, server])
		quit(1)
		return
	var robin_id := int(robin.multiplayer.get_unique_id())
	check(server.player_log_label(robin_id) == "Player 1 - Robin", "server retains slot plus name")
	check(robin.player_label(robin_id) == "Robin", "UI shows name without slot prefix")
	var elio := make_peer("ElioClient")
	elio.local_player_name = "Elio"
	check(elio.join("127.0.0.1:27943") == OK, "Elio connects")
	check(await wait_roster([server, robin, elio], 2), "late join synchronizes roster")
	var elio_id := int(elio.multiplayer.get_unique_id())
	check(elio.player_label(robin_id) == "Robin" and robin.player_label(elio_id) == "Elio", "names synchronize both ways")
	check(robin.player_names == server.player_names and elio.player_names == server.player_names, "authoritative name maps match")
	check(server.departments_for(robin_id) == ["fire", "engineer"], "department ownership is unchanged")
	check(not server._valid_player_names(server.roster, {robin_id: "Robin"}), "incomplete names are rejected")
	elio.close()
	check(await wait_roster([server, robin], 1), "departure updates roster")
	check(not server.player_names.has(elio_id) and not robin.player_names.has(elio_id), "departed names are removed")
	await cleanup([robin, elio, server])
	if not failures.is_empty():
		quit(1)
		return
	# Desktop hosts also publish their own selected name.
	var host_peer := make_peer("DesktopHost")
	host_peer.port = 27944
	host_peer.local_player_name = "Nova"
	check(host_peer.host() == OK, "desktop host starts")
	check(host_peer.player_label(1) == "Nova" and host_peer.player_log_label(1) == "Player 1 - Nova", "desktop host name is assigned")
	await cleanup([host_peer])
	print("PLAYER NAMES TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
