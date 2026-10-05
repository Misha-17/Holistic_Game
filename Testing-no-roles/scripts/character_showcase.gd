extends Node2D


const HEROES: Array[String] = ["nova", "bram", "elio", "tess"]
const CLIPS: Array[String] = ["idle", "walk_down", "walk_side", "walk_up", "work", "celebrate", "walk_left"]
const LABELS: Array[String] = ["IDLE", "WALK DOWN", "WALK RIGHT", "WALK UP", "WORK", "CELEBRATE", "WALK LEFT"]
const ACCENTS: Array[Color] = [Color("75b7c5"), Color("de9a65"), Color("85b6a2"), Color("d1b35e")]
const BACKGROUNDS: Array[Color] = [Color("1b262d"), Color("e5e0d6"), Color("3c4c56")]

var sprites: Array[AnimatedSprite2D] = []
var native_sprites: Array[AnimatedSprite2D] = []
var buttons: Array[Dictionary] = []
var animation: int = 0
var preview_scale: int = 4
var paused: bool = false
var checkerboard: bool = true
var background: int = 0
var font: Font
var status: String = ""
var _capture_path: String = ""
var _capture_exit: bool = false

func _ready() -> void:
	font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for index: int in range(HEROES.size()):
		var frames: SpriteFrames = load("res://assets/characters/sprites/%s_frames.tres" % HEROES[index]) as SpriteFrames
		if frames == null:
			status = "Build the character SpriteFrames resources before opening this scene."
			continue
		var enlarged := AnimatedSprite2D.new()
		enlarged.sprite_frames = frames
		enlarged.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		enlarged.position = Vector2(210 + index * 340, 451)
		enlarged.scale = Vector2.ONE * preview_scale
		add_child(enlarged)
		sprites.append(enlarged)
		var native := AnimatedSprite2D.new()
		native.sprite_frames = frames
		native.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		native.position = Vector2(210 + index * 340, 669)
		add_child(native)
		native_sprites.append(native)
	_set_animation(0)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
		elif argument == "--quit-after-capture":
			_capture_exit = true
		elif argument.begins_with("--animation="):
			var requested: int = CLIPS.find(argument.trim_prefix("--animation="))
			if requested >= 0:
				_set_animation(requested)
	if not _capture_path.is_empty():
		_capture.call_deferred()

func _process(_delta: float) -> void:
	
	for index: int in range(sprites.size()):
		native_sprites[index].set_frame_and_progress(sprites[index].frame, sprites[index].frame_progress)
	queue_redraw()

func _draw() -> void:
	var ink: Color = Color("17252c") if background == 1 else Color("e9e5dc")
	var secondary: Color = Color("52616a") if background == 1 else Color("96a8b0")
	draw_rect(Rect2(0, 0, 1440, 900), BACKGROUNDS[background])
	if font == null:
		return
	_text("BEACON BAY / CHARACTER STUDIO", Vector2(52, 63), 19, secondary)
	_text("Nova, Bram, Elio & Tess", Vector2(50, 114), 39, ink)
	_text("64 px sprites  ·  transparent atlases  ·  nearest-neighbor preview", Vector2(53, 148), 16, secondary)
	buttons.clear()
	for index: int in range(CLIPS.size()):
		var area := Rect2(52 + index * 193, 178, 178, 43)
		var fill: Color = Color("7bc3b0") if animation == index else (Color("c9c9c2") if background == 1 else Color("2b3c45"))
		draw_rect(area, fill)
		_center_text("%d  %s" % [index + 1, LABELS[index]], area, 13, Color("14252b") if animation == index else ink)
		buttons.append({"rect": area, "action": "animation", "value": index})
	for index: int in range(HEROES.size()):
		var x: float = 52 + index * 340
		_text(HEROES[index].capitalize(), Vector2(x + 25, 280), 27, ink)
		draw_rect(Rect2(x + 25, 292, 42, 3), ACCENTS[index])
		_checker(Rect2(x + 30, 323, 256, 256), 16)
		_text("%d×" % preview_scale, Vector2(x + 30, 610), 15, secondary)
		_checker(Rect2(x + 126, 637, 64, 64), 8)
		_text("1× / 64 px", Vector2(x + 116, 730), 14, secondary)
		if index < sprites.size():
			_text("FRAME %02d / 06" % (sprites[index].frame + 1), Vector2(x + 171, 610), 12, secondary)
	var pause_area := Rect2(52, 786, 136, 42)
	var smaller_area := Rect2(207, 786, 42, 42)
	var bigger_area := Rect2(257, 786, 42, 42)
	var fill: Color = Color("c9c9c2") if background == 1 else Color("2b3c45")
	for area: Rect2 in [pause_area, smaller_area, bigger_area]:
		draw_rect(area, fill)
	_center_text("PLAY" if paused else "PAUSE", pause_area, 14, ink)
	_center_text("−", smaller_area, 25, ink)
	_center_text("+", bigger_area, 25, ink)
	buttons.append({"rect": pause_area, "action": "pause", "value": 0})
	buttons.append({"rect": smaller_area, "action": "scale", "value": -1})
	buttons.append({"rect": bigger_area, "action": "scale", "value": 1})
	_text("SPACE pause    ← / → step    + / − scale    G grid    B background    ESC quit", Vector2(328, 813), 15, secondary)
	_text("Walk left mirrors the right-facing frames with flip_h.", Vector2(52, 863), 14, secondary)
	if not status.is_empty():
		_text(status, Vector2(52, 765), 15, Color("e19c80"))

func _checker(area: Rect2, tile: int) -> void:
	var light: Color = Color("d8d5cb") if background == 1 else Color("293941")
	var dark: Color = Color("ccc9c1") if background == 1 else Color("233239")
	draw_rect(area, dark)
	if not checkerboard:
		return
	for y: int in range(int(area.size.y) / tile):
		for x: int in range(int(area.size.x) / tile):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(area.position + Vector2(x * tile, y * tile), Vector2(tile, tile)), light)

func _text(value: String, position: Vector2, size: int, color: Color) -> void:
	draw_string(font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _center_text(value: String, area: Rect2, size: int, color: Color) -> void:
	var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, area.position + Vector2((area.size.x - width) * 0.5, (area.size.y + size * 0.7) * 0.5), size, color)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over: bool = false
		for button: Dictionary in buttons:
			if button.rect.has_point(event.position):
				over = true
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for button: Dictionary in buttons:
			if button.rect.has_point(event.position):
				match str(button.action):
					"animation": _set_animation(int(button.value))
					"pause": _set_paused(not paused)
					"scale": _set_scale(preview_scale + int(button.value))
				return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_7:
			_set_animation(int(event.keycode - KEY_1))
		match event.keycode:
			KEY_SPACE: _set_paused(not paused)
			KEY_LEFT: _step_frame(-1)
			KEY_RIGHT: _step_frame(1)
			KEY_G: checkerboard = not checkerboard
			KEY_B: background = (background + 1) % BACKGROUNDS.size()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _set_scale(preview_scale + 1)
			KEY_MINUS, KEY_KP_SUBTRACT: _set_scale(preview_scale - 1)
			KEY_ESCAPE: get_tree().quit()

func _set_animation(index: int) -> void:
	animation = clampi(index, 0, CLIPS.size() - 1)
	for sprite: AnimatedSprite2D in sprites + native_sprites:
		sprite.flip_h = CLIPS[animation] == "walk_left"
		sprite.play(CLIPS[animation])
		sprite.set_frame_and_progress(0, 0.0)
		if paused or sprite in native_sprites:
			sprite.pause()

func _set_paused(value: bool) -> void:
	paused = value
	for sprite: AnimatedSprite2D in sprites:
		if paused:
			sprite.pause()
		else:
			sprite.play()

func _set_scale(value: int) -> void:
	preview_scale = clampi(value, 2, 4)
	for sprite: AnimatedSprite2D in sprites:
		sprite.scale = Vector2.ONE * preview_scale

func _step_frame(direction: int) -> void:
	_set_paused(true)
	for sprite: AnimatedSprite2D in sprites:
		sprite.set_frame_and_progress(posmod(sprite.frame + direction, 6), 0.0)

func _capture() -> void:
	await get_tree().create_timer(0.5).timeout
	_set_animation(animation)
	_set_paused(true)
	for sprite: AnimatedSprite2D in sprites:
		sprite.frame = 2
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var result: Error = screenshot.save_png(_capture_path)
	print("Character showcase capture: ", _capture_path, " result=", result)
	if _capture_exit:
		get_tree().quit(0 if result == OK else 1)
