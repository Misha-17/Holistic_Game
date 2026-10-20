extends "res://tests/test_player_names.gd"

func run() -> void:
	for server_only in [true, false]:
		var server := make_peer("RushServer")
		server.port = 27945
		check(server.host(server_only) == OK, "server starts")
		var robin := make_peer("RemainingClient")
		var leaving := make_peer("LeavingClient")
		robin.local_player_name = "Robin"
		leaving.local_player_name = "Andrei"
		check(robin.join("127.0.0.1:27945") == OK, "remaining client connects")
		check(leaving.join("127.0.0.1:27945") == OK, "departing client connects")
		check(await wait_roster([server, robin, leaving], 2 if server_only else 3), "rosters synchronize")
		if not failures.is_empty():
			await cleanup([robin, leaving, server])
			quit(1)
			return
		var received: Array[int] = []
		var events: Array[int] = []
		var messages: Array[String] = []
		robin.snapshot_received.connect(func(data: Dictionary): received.append(int(data.tick)))
		robin.event_received.connect(func(data: Dictionary): events.append(int(data.tick)))
		server.message_received.connect(func(message: String): messages.append(message))
		var noise := PackedByteArray()
		noise.resize(12000)
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		for i in noise.size(): noise[i] = rng.randi_range(0, 255)
		check(var_to_bytes({"noise": noise}).compress(FileAccess.COMPRESSION_ZSTD).size() > NetworkSession.UNRELIABLE_SNAPSHOT_LIMIT, "fixture uses large reliable snapshots")
		var leaving_id := leaving.multiplayer.get_unique_id()
		for tick in 40:
			if tick == 10:
				# Close channels before the scene roster processes the departure.
				var transport := server.multiplayer.multiplayer_peer as ENetMultiplayerPeer
				transport.get_peer(leaving_id).peer_disconnect_now()
				check(not server._connected_recipients().has(leaving_id), "dead transport excluded before roster cleanup")
				server._peer_disconnected(leaving_id)
				server._peer_disconnected(leaving_id)
				server._peer_disconnected(999999)
			server.broadcast({"tick": tick, "noise": noise})
			server.broadcast_event({"tick": tick})
			await create_timer(0.02).timeout
		var until := Time.get_ticks_msec() + 3000
		while (not received.has(39) or not events.has(39)) and Time.get_ticks_msec() < until:
			await create_timer(0.02).timeout
		check(received.has(39) and events.has(39), "remaining client receives updates after departure")
		check(await wait_roster([server, robin], 1 if server_only else 2), "remaining roster synchronizes")
		var departures := 0
		for message in messages:
			if "left. Departments reshuffled." in message: departures += 1
		check(departures == 1, "only one departure announcement")
		await cleanup([leaving, robin, server])
		if not failures.is_empty():
			quit(1)
			return
	print("RUSH DISCONNECT TEST: PASS")
	quit(0)
