extends Node2D

const PORT := 27771
const SPEED := 180.0
var players := {}
var controls := {}
var enemies: Array[Vector2] = []
var flashes: Array = []
var spawn_time := 1.0
var network_tick := 0.0
var score := 0
var menu := HBoxContainer.new()
var address := LineEdit.new()
var status := Label.new()

func _ready() -> void:
	add_child(menu)
	menu.position = Vector2(14, 12)
	address.text = "127.0.0.1"
	address.custom_minimum_size.x = 138
	for label in ["Solo", "Host co-op", "Join"]:
		var button := Button.new()
		button.text = label
		button.focus_mode = Control.FOCUS_NONE
		menu.add_child(button)
		button.pressed.connect(start.bind(label))
	menu.add_child(address)
	add_child(status)
	status.position = Vector2(14, 494)
	status.text = "BRASSFALL   /   WASD + mouse   /   Join via host IP"
	multiplayer.peer_connected.connect(peer_joined)
	multiplayer.peer_disconnected.connect(remove_player)
	multiplayer.connected_to_server.connect(func(): status.text = "Connected")
	multiplayer.connection_failed.connect(reset.bind("Connection failed"))
	multiplayer.server_disconnected.connect(reset.bind("Host disconnected"))

func start(mode: String) -> void:
	if mode != "Solo":
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(PORT, 3) if mode == "Host co-op" else peer.create_client(address.text.strip_edges(), PORT)
		if err != OK:
			status.text = error_string(err)
			return
		multiplayer.multiplayer_peer = peer
	menu.hide()
	if multiplayer.is_server():
		add_player(1)
	status.text = mode + "   /   WASD + mouse"

func reset(message: String) -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	controls.clear()
	enemies.clear()
	flashes.clear()
	score = 0
	status.text = message
	menu.show()
	queue_redraw()

func peer_joined(id: int) -> void:
	if multiplayer.is_server():
		add_player(id)

func add_player(id: int) -> void:
	players[id] = {"pos": Vector2(380 + 32 * players.size(),270), "aim": Vector2.RIGHT, "cooldown": 0.0}
	controls[id] = [Vector2.ZERO, Vector2.RIGHT, false]

func remove_player(id: int) -> void:
	players.erase(id)
	controls.erase(id)

@rpc("any_peer","call_remote","unreliable_ordered")
func submit(move: Vector2, aim: Vector2, shoot: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and players.has(id) and move.is_finite() and aim.is_finite():
		controls[id] = [move.limit_length(), aim.normalized(), shoot]

@rpc("authority","call_remote","unreliable_ordered")
func snapshot(p: Dictionary, e: Array[Vector2], f: Array, points: int) -> void:
	players = p
	enemies = e
	flashes = f
	score = points
	queue_redraw()

func _physics_process(dt: float) -> void:
	if menu.visible or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var id := multiplayer.get_unique_id()
	var move := Vector2(int(Input.is_physical_key_pressed(KEY_D))-int(Input.is_physical_key_pressed(KEY_A)), int(Input.is_physical_key_pressed(KEY_S))-int(Input.is_physical_key_pressed(KEY_W))).normalized()
	if players.has(id):
		var aim := (get_local_mouse_position() - Vector2(players[id].pos)).normalized()
		var shoot := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if multiplayer.is_server():
			controls[id] = [move, aim, shoot]
		else:
			submit.rpc_id(1, move, aim, shoot)
	if not multiplayer.is_server():
		return
	for key in players:
		var p: Dictionary = players[key]
		var input: Array = controls[key]
		p.pos = (Vector2(p.pos) + Vector2(input[0]) * SPEED * dt).clamp(Vector2(12,12), Vector2(948,528))
		p.aim = input[1]
		p.cooldown -= dt
		if input[2] and p.cooldown <= 0 and Vector2(p.aim) != Vector2.ZERO:
			flashes.append([p.pos, p.pos + p.aim * 220, 0.13])
			for i in range(enemies.size()-1,-1,-1):
				var delta := enemies[i] - Vector2(p.pos)
				if delta.length() <= 220 and absf(delta.angle_to(p.aim)) < 0.16:
					enemies.remove_at(i)
					score += 1
			p.cooldown = 0.48
	spawn_time -= dt
	if spawn_time <= 0 and enemies.size() < 40:
		enemies.append(Vector2(950 if randf() < 0.5 else 10, randf_range(12,528)))
		spawn_time = 1
	for i in range(enemies.size()):
		var nearest := Vector2(players.values()[0].pos)
		for p in players.values():
			if enemies[i].distance_squared_to(p.pos) < enemies[i].distance_squared_to(nearest):
				nearest = p.pos
		enemies[i] = enemies[i].move_toward(nearest, 48 * dt)
	for i in range(flashes.size()-1,-1,-1):
		flashes[i][2] -= dt
		if flashes[i][2] <= 0:
			flashes.remove_at(i)
	network_tick += dt
	if network_tick >= 0.05 and not multiplayer.get_peers().is_empty():
		snapshot.rpc(players, enemies, flashes, score)
		network_tick = 0
	queue_redraw()

func _draw() -> void:
	for e in enemies:
		draw_circle(e, 9, Color("99ae70"))
		draw_line(e - Vector2(8,5), e + Vector2(9,6), Color("526d4d"), 3)
	for id in players:
		var p: Dictionary = players[id]
		draw_circle(p.pos, 11, Color("ed923e") if id == multiplayer.get_unique_id() else Color("79c3cf"))
		draw_line(p.pos, p.pos + p.aim * 21, Color("ded4b7"), 4)
	for f in flashes:
		draw_line(f[0], f[1], Color("fed38c"), 2)
	if not menu.visible:
		draw_string(ThemeDB.fallback_font, Vector2(18,30), "BRASSFALL   /   %03d" % score)
