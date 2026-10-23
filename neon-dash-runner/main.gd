extends Node2D

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }

const FLOOR_Y: float = 440.0
const PLAYER_X: float = 170.0
const PLAYER_WIDTH: float = 42.0
const PLAYER_HEIGHT: float = 62.0
const SAVE_PATH: String = "user://neon_dash.cfg"

const GRAVITY: float = 1500.0
const JUMP_FORCE: float = -650.0
const START_SPEED: float = 360.0
const MAX_SPEED: float = 600.0

var state: GameState = GameState.MENU

var obstacles: Array[Dictionary] = []
var coins: Array[Dictionary] = []
var clickable_buttons: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var player_trails: Array[Dictionary] = []

var player_bottom: float = FLOOR_Y
var vertical_speed: float = 0.0
var slide_timer: float = 0.0
var is_sliding: bool = false

var elapsed: float = 0.0
var score: int = 0
var coin_count: int = 0
var best_score: int = 0

var world_speed: float = START_SPEED
var spawn_timer: float = 1.2
var anim_timer: float = 0.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_load_best_score()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	anim_timer += delta
	if state == GameState.PLAYING:
		_update_game(delta)
	
	_update_particles(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)
	elif event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_tap(event.position)


func _handle_key(key: int) -> void:
	match state:
		GameState.MENU:
			if key == KEY_ENTER or key == KEY_SPACE:
				_start_game()
		GameState.PLAYING:
			if key == KEY_ESCAPE or key == KEY_P:
				state = GameState.PAUSED
			elif key == KEY_SPACE or key == KEY_UP or key == KEY_W:
				_jump()
			elif key == KEY_DOWN or key == KEY_S or key == KEY_SHIFT:
				_begin_slide()
		GameState.PAUSED:
			if key == KEY_ESCAPE or key == KEY_P:
				state = GameState.PLAYING
			elif key == KEY_ENTER:
				_start_game()
			elif key == KEY_M:
				state = GameState.MENU
		GameState.GAME_OVER:
			if key == KEY_ENTER or key == KEY_SPACE:
				_start_game()
			elif key == KEY_M or key == KEY_ESCAPE:
				state = GameState.MENU


func _handle_tap(position: Vector2) -> void:
	for button in clickable_buttons:
		var rect: Rect2 = button["rect"]
		if rect.has_point(position):
			_activate_button(str(button["action"]))
			return

	if state == GameState.PLAYING:
		var screen_width: float = get_viewport_rect().size.x
		if position.x >= screen_width * 0.65:
			_begin_slide()
		else:
			_jump()


func _activate_button(action: String) -> void:
	match action:
		"start", "restart":
			_start_game()
		"resume":
			state = GameState.PLAYING
		"menu":
			state = GameState.MENU


func _start_game() -> void:
	state = GameState.PLAYING
	obstacles.clear()
	coins.clear()
	particles.clear()
	player_trails.clear()

	elapsed = 0.0
	score = 0
	coin_count = 0
	world_speed = START_SPEED
	spawn_timer = 1.2
	player_bottom = FLOOR_Y
	vertical_speed = 0.0
	slide_timer = 0.0
	is_sliding = false


func _update_game(delta: float) -> void:
	elapsed += delta
	world_speed = minf(START_SPEED + elapsed * 4.0, MAX_SPEED)
	score = int(elapsed * 10.0) + coin_count * 25

	if player_bottom < FLOOR_Y or vertical_speed < 0.0:
		vertical_speed += GRAVITY * delta
		player_bottom += vertical_speed * delta

		if player_bottom >= FLOOR_Y:
			player_bottom = FLOOR_Y
			vertical_speed = 0.0
			_spawn_burst(Vector2(PLAYER_X, FLOOR_Y), Color(0.0, 0.95, 1.0), 12)

	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	player_trails.append({
		"pos": Vector2(PLAYER_X, player_bottom - player_height * 0.5),
		"size": Vector2(PLAYER_WIDTH, player_height),
		"alpha": 0.5
	})
	if player_trails.size() > 5:
		player_trails.pop_front()

	for t in player_trails:
		t["alpha"] -= delta * 3.5

	if slide_timer > 0.0:
		slide_timer = maxf(0.0, slide_timer - delta)
		is_sliding = slide_timer > 0.0

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_items()
		spawn_timer = maxf(0.75, 1.3 - elapsed * 0.0035) + rng.randf_range(0.1, 0.3)

	for i in range(obstacles.size() - 1, -1, -1):
		var obstacle: Dictionary = obstacles[i]
		obstacle["x"] = float(obstacle["x"]) - world_speed * delta
		if float(obstacle["x"]) < -100.0:
			obstacles.remove_at(i)

	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		coin["x"] = float(coin["x"]) - world_speed * delta
		if float(coin["x"]) < -50.0:
			coins.remove_at(i)

	_check_collisions()


func _update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
		if p["life"] <= 0.0:
			particles.remove_at(i)


func _spawn_burst(pos: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		var angle = rng.randf_range(0.0, TAU)
		var speed = rng.randf_range(80.0, 200.0)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": color,
			"life": rng.randf_range(0.3, 0.5),
			"max_life": 0.5
		})


func _spawn_items() -> void:
	var spawn_x: float = get_viewport_rect().size.x + 60.0
	var overhead: bool = rng.randf() < 0.4

	obstacles.append({
		"x": spawn_x,
		"overhead": overhead
	})

	if rng.randf() < 0.7:
		coins.append({
			"x": spawn_x + rng.randf_range(160.0, 250.0),
			"y": rng.randf_range(270.0, 360.0)
		})


func _jump() -> void:
	if player_bottom >= FLOOR_Y and not is_sliding:
		vertical_speed = JUMP_FORCE
		_spawn_burst(Vector2(PLAYER_X, FLOOR_Y), Color(0.0, 0.95, 1.0), 8)


func _begin_slide() -> void:
	if player_bottom >= FLOOR_Y and not is_sliding:
		is_sliding = true
		slide_timer = 0.65
		_spawn_burst(Vector2(PLAYER_X, FLOOR_Y), Color(1.0, 0.15, 0.55), 8)


func _check_collisions() -> void:
	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	var player_rect := Rect2(PLAYER_X - PLAYER_WIDTH / 2.0, player_top, PLAYER_WIDTH, player_height)

	for obstacle in obstacles:
		var x: float = float(obstacle["x"])
		var hitbox: Rect2
		if bool(obstacle["overhead"]):
			hitbox = Rect2(x - 25.0, FLOOR_Y - 65.0, 50.0, 28.0)
		else:
			hitbox = Rect2(x - 24.0, FLOOR_Y - 48.0, 48.0, 48.0)

		if player_rect.intersects(hitbox):
			_end_game()
			return

	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		var coin_rect := Rect2(float(coin["x"]) - 14.0, float(coin["y"]) - 14.0, 28.0, 28.0)
		if player_rect.intersects(coin_rect):
			coin_count += 1
			_spawn_burst(Vector2(coin["x"], coin["y"]), Color(1.0, 0.82, 0.15), 10)
			coins.remove_at(i)


func _end_game() -> void:
	if state != GameState.PLAYING:
		return
	state = GameState.GAME_OVER
	score = int(elapsed * 10.0) + coin_count * 25
	if score > best_score:
		best_score = score
		_save_best_score()


func _load_best_score() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		best_score = int(config.get_value("scores", "best", 0))


func _save_best_score() -> void:
	var config := ConfigFile.new()
	config.set_value("scores", "best", best_score)
	config.save(SAVE_PATH)


func _draw() -> void:
	clickable_buttons.clear()
	var screen_size: Vector2 = get_viewport_rect().size
	if screen_size.x <= 0:
		return

	# Background fill
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.02, 0.015, 0.05))

	# Stars
	for i in range(25):
		var st_x = fmod(float(i) * 71.0 - anim_timer * 15.0, screen_size.x)
		var st_y = float((i * 31) % int(FLOOR_Y - 50))
		draw_circle(Vector2(st_x, st_y), 1.5, Color(1.0, 1.0, 1.0, 0.3))

	# Floor line
	draw_line(Vector2(0.0, FLOOR_Y), Vector2(screen_size.x, FLOOR_Y), Color(0.0, 0.95, 1.0), 3.0)

	# Obstacles
	for obstacle in obstacles:
		var x: float = float(obstacle["x"])
		if bool(obstacle["overhead"]):
			draw_rect(Rect2(x - 25.0, FLOOR_Y - 65.0, 50.0, 28.0), Color(1.0, 0.15, 0.55))
		else:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 24.0, FLOOR_Y),
				Vector2(x, FLOOR_Y - 48.0),
				Vector2(x + 24.0, FLOOR_Y)
			]), Color(1.0, 0.15, 0.55))

	# Coins
	for coin in coins:
		var center := Vector2(float(coin["x"]), float(coin["y"]))
		draw_circle(center, 12.0, Color(1.0, 0.82, 0.15))

	# Player Trails
	for t in player_trails:
		var a = t["alpha"]
		if a > 0.0:
			draw_rect(Rect2(t["pos"] - t["size"] * 0.5, t["size"]), Color(0.0, 0.95, 1.0, a * 0.4))

	# Player
	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	draw_rect(Rect2(PLAYER_X - PLAYER_WIDTH / 2.0, player_top, PLAYER_WIDTH, player_height), Color(0.0, 0.95, 1.0))

	# Scoreboard Text
	var font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(24.0, 36.0), "SCORE: %d    COINS: %d    BEST: %d" % [score, coin_count, best_score], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color.WHITE)

	# Menus
	match state:
		GameState.MENU:
			_draw_menu(screen_size)
		GameState.PAUSED:
			_draw_pause_menu(screen_size)
		GameState.GAME_OVER:
			_draw_game_over(screen_size)


func _draw_menu(screen_size: Vector2) -> void:
	_draw_overlay(screen_size)
	_draw_centered_text(screen_size, 180.0, "NEON DASH RUNNER", 38, Color(0.0, 0.95, 1.0))
	_draw_centered_text(screen_size, 230.0, "Jump over obstacles & slide under barriers!", 16, Color.WHITE)
	_draw_button("PLAY GAME", Vector2(screen_size.x * 0.5, 320.0), Vector2(220.0, 50.0), "start", Color(0.0, 0.95, 1.0))


func _draw_pause_menu(screen_size: Vector2) -> void:
	_draw_overlay(screen_size)
	_draw_centered_text(screen_size, 190.0, "GAME PAUSED", 38, Color(0.0, 0.95, 1.0))
	_draw_button("RESUME", Vector2(screen_size.x * 0.5, 270.0), Vector2(220.0, 48.0), "resume", Color(0.0, 0.95, 1.0))
	_draw_button("RESTART", Vector2(screen_size.x * 0.5, 335.0), Vector2(220.0, 48.0), "restart", Color(1.0, 0.82, 0.15))
	_draw_button("MAIN MENU", Vector2(screen_size.x * 0.5, 400.0), Vector2(220.0, 48.0), "menu", Color(1.0, 0.15, 0.55))


func _draw_game_over(screen_size: Vector2) -> void:
	_draw_overlay(screen_size)
	_draw_centered_text(screen_size, 170.0, "GAME OVER", 40, Color(1.0, 0.15, 0.55))
	_draw_centered_text(screen_size, 220.0, "Score: %d     Coins: %d" % [score, coin_count], 20, Color.WHITE)
	_draw_button("PLAY AGAIN", Vector2(screen_size.x * 0.5, 310.0), Vector2(220.0, 48.0), "restart", Color(0.0, 0.95, 1.0))
	_draw_button("MAIN MENU", Vector2(screen_size.x * 0.5, 375.0), Vector2(220.0, 48.0), "menu", Color(1.0, 0.15, 0.55))


func _draw_overlay(screen_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.01, 0.005, 0.04, 0.85))


func _draw_centered_text(screen_size: Vector2, baseline_y: float, message: String, font_size: int, color: Color) -> void:
	var font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(0.0, baseline_y), message, HORIZONTAL_ALIGNMENT_CENTER, screen_size.x, font_size, color)


func _draw_button(label: String, center: Vector2, size: Vector2, action: String, accent: Color) -> void:
	var rect := Rect2(center - size * 0.5, size)
	draw_rect(rect, Color(0.045, 0.035, 0.12, 0.95), true)
	draw_rect(rect, accent, false, 2.0)
	
	var font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(rect.position.x, center.y + 7.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, Color.WHITE)

	clickable_buttons.append({
		"rect": rect,
		"action": action
	})
