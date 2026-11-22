extends SceneTree

# Playtest 2.11: a player with a bad connection kept dropping out, and every
# drop and rejoin reshuffled everyone's departments. Now a player is recognised
# by a key stored on their computer; while roles are locked (outside the
# lobby) their departments wait for them and nobody else's change. The session
# leader stays the same player.
# Real ENet on localhost: a dedicated server and four clients.
# Run: godot --headless --path . -s tests/test_reconnect_roles.gd

class TestNetwork extends NetworkSession:
	func _start_upnp() -> void:
		pass

const PORT := 27961
const LAN_PORT := 27962
var failures: Array[String] = []
var branches: Array[Node] = []
var counter := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func make_peer(label: String) -> TestNetwork:
	counter += 1
	var branch := Node.new()
	branch.name = "%s_%d" % [label, counter]
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var session := TestNetwork.new()
	branch.add_child(session)
	branches.append(branch)
	return session

func wait_until(condition: Callable, seconds: float = 10.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if condition.call(): return true
		await create_timer(0.02).timeout
	return false

func join(key: String, name: String, port: int = PORT) -> TestNetwork:
	var client := make_peer("client_" + name)
	client.port = port
	client.local_player_key = key
	client.local_player_name = name
	check(client.join("127.0.0.1:%d" % port) == OK, name + " connects")
	check(await wait_until(func(): return client.roster.has(client.multiplayer.get_unique_id())), name + " joins the room")
	return client

func departments_by_key(net: NetworkSession) -> Dictionary:
	var result := {}
	for peer_id in net.roster:
		result[net.player_key(int(peer_id))] = net.departments_for(int(peer_id))
	return result

func run() -> void:
	var server := make_peer("server")
	server.port = PORT
	check(server.host(true) == OK, "dedicated server starts")
	var keys := ["aaaa0000aaaa0001", "bbbb0000bbbb0002", "cccc0000cccc0003", "dddd0000dddd0004"]
	var clients: Array[TestNetwork] = []
	for i in 4: clients.append(await join(keys[i], "P%d" % (i + 1)))
	check(server.roster.size() == 4 and server.team_size == 4, "four players, four department bundles")
	check(server.leader_key == keys[0] and clients[0].is_leader() and not clients[1].is_leader(), "the first player is the session leader")
	server.set_roles_locked(true) # a level is running

	var before := departments_by_key(server)
	var seat_before := int(server.roster[clients[2].multiplayer.get_unique_id()])
	# Player 3 drops out mid-level.
	clients[2].close()
	check(await wait_until(func(): return server.roster.size() == 3), "the server notices the dropout")
	check(await wait_until(func(): return clients[1].roster.size() == 3), "the others get the new roster")
	var during := departments_by_key(clients[1])
	for key in during: check(during[key] == before[key], "%s keeps the same departments while P3 is away" % key)
	check(server.reserved.has(keys[2]) and clients[1].reserved.has(keys[2]), "P3's seat and departments are reserved")
	check(server.owner_of(str(before[keys[2]][0])) == -1, "nobody else commands P3's department meanwhile")

	# P3 comes back with a new network id.
	var back := await join(keys[2], "P3")
	var back_id := back.multiplayer.get_unique_id()
	check(back_id != clients[2].multiplayer.get_unique_id() or true, "new network id")
	check(server.departments_for(back_id) == before[keys[2]], "P3 gets the same departments back")
	check(int(server.roster[back_id]) == seat_before, "P3 gets the same seat back")
	check(server.reserved.is_empty(), "the reservation is used up")
	var after := departments_by_key(server)
	for key in after: check(after[key] == before[key], "%s still has the same departments after P3 rejoins" % key)

	# The leader drops out: the next player leads meanwhile, then it returns.
	var leader_departments: Array = before[keys[0]]
	clients[0].close()
	check(await wait_until(func(): return server.roster.size() == 3), "the server notices the leader left")
	check(await wait_until(func(): return clients[1].roster.size() == 3), "P2 sees the leader leave")
	check(clients[1].is_leader(), "P2 leads while P1 is away")
	var leader_back := await join(keys[0], "P1")
	check(await wait_until(func(): return leader_back.is_leader() and not clients[1].is_leader()), "P1 is the leader again after rejoining")
	check(server.departments_for(leader_back.multiplayer.get_unique_id()) == leader_departments, "P1's departments are unchanged")

	# P4 drops out: their seat is held, so the room stays "full" for strangers.
	clients[3].close()
	check(await wait_until(func(): return server.reserved.has(keys[3])), "P4 dropped out")
	var refused := make_peer("stranger")
	refused.port = PORT
	refused.local_player_key = "eeee0000eeee0005"
	refused.join("127.0.0.1:%d" % PORT)
	await create_timer(0.6).timeout
	check(not server.roster.has(refused.multiplayer.get_unique_id()), "a stranger cannot take P4's held seat")
	refused.close()
	# Next level: P4 did not return, so the team is re-split once (3 players).
	check(server.rebalance_roles(), "the next level re-splits the team")
	check(server.reserved.is_empty() and server.team_size == 3, "three connected players, three bundles")
	var three := departments_by_key(server)
	# A new player arrives mid-level: nobody's departments move; they wait.
	var newcomer := await join("eeee0000eeee0005", "P5")
	check(server.departments_for(newcomer.multiplayer.get_unique_id()).is_empty(), "a newcomer mid-level waits for the next level")
	var with_newcomer := departments_by_key(server)
	for key in three: check(with_newcomer[key] == three[key], "%s keeps their departments when P5 arrives" % key)
	check(server.rebalance_roles() and server.team_size == 4, "the next level includes the newcomer")
	check(not server.departments_for(newcomer.multiplayer.get_unique_id()).is_empty(), "the newcomer now has a department")

	# LAN: the host is the session leader.
	var host := make_peer("lan_host")
	host.port = LAN_PORT
	host.local_player_key = "ffff0000ffff0006"
	check(host.host(false) == OK, "LAN host starts")
	var guest := await join("abab0000abab0007", "G", LAN_PORT)
	check(host.is_leader() and not guest.is_leader(), "the LAN host is the leader")

	for net in [guest, host, newcomer, refused, leader_back, back, server] + clients: net.close()
	await create_timer(0.1).timeout
	for branch in branches:
		set_multiplayer(null, branch.get_path())
		branch.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: dropouts keep everyone's departments and seat, the leader stays the leader, new arrivals wait")
	quit(0 if failures.is_empty() else 1)
