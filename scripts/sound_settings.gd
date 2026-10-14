extends Control

var sliders: Dictionary = {}
var _director: AudioDirector
var _network: NetworkSession

func build(director: AudioDirector, network: NetworkSession = null) -> void:
	_director = director
	_network = network
	position = Vector2(80, 244)
	size = Vector2(1290, 550)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _network != null: _network.roster_changed.connect(refresh)
	refresh()

func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	sliders.clear()
	_add_slider("game_sound", "Game sound - music and all effects", 0)
	var row := 1
	if _network != null and _network.active:
		var peers: Array = _network.roster.keys()
		peers.sort_custom(func(a, b): return int(_network.roster[a]) < int(_network.roster[b]))
		for peer in peers:
			if int(peer) == multiplayer.get_unique_id(): continue
			var key := "voice_player_%d" % (int(_network.roster[peer]) + 1)
			_add_slider(key, _network.player_label(int(peer)) + " - voice", row)
			row += 1
	if row == 1:
		var hint := Label.new()
		hint.position = Vector2(0, 112)
		hint.text = "Join a team to adjust each teammate's voice."
		hint.add_theme_color_override("font_color", Color("90afb2"))
		add_child(hint)

func _add_slider(key: String, caption: String, index: int) -> void:
	var row := PanelContainer.new()
	row.position = Vector2(0, index * 106)
	row.size = Vector2(900, 86)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("193944")
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", style)
	add_child(row)
	var column := VBoxContainer.new()
	row.add_child(column)
	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", Color("f4e9d2"))
	label.add_theme_font_size_override("font_size", 20)
	column.add_child(label)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 20)
	column.add_child(line)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = _director.sound_level(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 28
	line.add_child(slider)
	var number := Label.new()
	number.custom_minimum_size.x = 40
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	number.text = str(int(slider.value))
	number.add_theme_color_override("font_color", Color("70d2ba"))
	line.add_child(number)
	slider.value_changed.connect(_change_level.bind(key, number))
	sliders[key] = slider

func _change_level(value: float, key: String, number: Label) -> void:
	number.text = str(int(value))
	_director.set_sound_level(key, int(value))
