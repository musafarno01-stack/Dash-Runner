extends Node2D

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }

const FLOOR_Y: float = 440.0
const PLAYER_X: float = 170.0
const PLAYER_WIDTH: float = 42.0
const PLAYER_HEIGHT: float = 62.0
const SAVE_PATH: String = "user://neon_dash.cfg"

const GRAVITY: float = 1600.0
const JUMP_FORCE: float = -680.0
const START_SPEED: float = 380.0
const MAX_SPEED: float = 620.0

var state: GameState = GameState.MENU

var obstacles: Array[Dictionary] = []
var coins: Array[Dictionary] = []
var clickable_buttons: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var player_trails: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []

var player_bottom: float = FLOOR_Y
var vertical_speed: float = 0.0
var slide_timer: float = 0.0
var is_sliding: bool = false
var was_on_floor: bool = true

var elapsed: float = 0.0
var score: int = 0
var coin_count: int = 0
var best_score: int = 0

var world_speed: float = START_SPEED
var spawn_timer: float = 1.0
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
	_update_floating_texts(delta)
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
	floating_texts.clear()

	elapsed = 0.0
	score = 0
	coin_count = 0
	world_speed = START_SPEED
	spawn_timer = 1.0
	player_bottom = FLOOR_Y
	vertical_speed = 0.0
	slide_timer = 0.0
	is_sliding = false


func _update_game(delta: float) -> void:
	elapsed += delta
	world_speed = minf(START_SPEED + elapsed * 4.0, MAX_SPEED)
	score = int(elapsed * 12.0) + coin_count * 30

	var on_floor = player_bottom >= FLOOR_Y and vertical_speed == 0.0
	if not was_on_floor and on_floor:
		_spawn_burst(Vector2(PLAYER_X, FLOOR_Y), Color(0.0, 0.95, 1.0), 10)
	was_on_floor = on_floor

	if player_bottom < FLOOR_Y or vertical_speed < 0.0:
		vertical_speed += GRAVITY * delta
		player_bottom += vertical_speed * delta

		if player_bottom >= FLOOR_Y:
			player_bottom = FLOOR_Y
			vertical_speed = 0.0

	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	player_trails.append({
		"pos": Vector2(PLAYER_X, player_bottom - player_height * 0.5),
		"size": Vector2(PLAYER_WIDTH, player_height),
		"alpha": 0.6
	})
	if player_trails.size() > 6:
		player_trails.pop_front()

	for t in player_trails:
		t["alpha"] -= delta * 4.0

	if slide_timer > 0.0:
		slide_timer = maxf(0.0, slide_timer - delta)
		is_sliding = slide_timer > 0.0

	# Running dust trail
	if on_floor and not is_sliding and rng.randf() < 0.35:
		particles.append({
			"pos": Vector2(PLAYER_X - 12.0, FLOOR_Y),
			"vel": Vector2(-world_speed * 0.25, rng.randf_range(-20.0, 5.0)),
			"color": Color(0.0, 0.95, 1.0, 0.5),
			"life": 0.2,
			"max_life": 0.2
		})

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_items()
		spawn_timer = maxf(0.8, 1.3 - elapsed * 0.003) + rng.randf_range(0.1, 0.35)

	for i in range(obstacles.size() - 1, -1, -1):
		obstacles[i]["x"] = float(obstacles[i]["x"]) - world_speed * delta
		if float(obstacles[i]["x"]) < -120.0:
			obstacles.remove_at(i)

	for i in range(coins.size() - 1, -1, -1):
		coins[i]["x"] = float(coins[i]["x"]) - world_speed * delta
		if float(coins[i]["x"]) < -60.0:
			coins.remove_at(i)

	_check_collisions()


func _update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
		if p["life"] <= 0.0:
			particles.remove_at(i)


func _update_floating_texts(delta: float) -> void:
	for i in range(floating_texts.size() - 1, -1, -1):
		var ft = floating_texts[i]
		ft["pos"].y -= 35.0 * delta
		ft["life"] -= delta
		if ft["life"] <= 0.0:
			floating_texts.remove_at(i)


func _spawn_burst(pos: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		var angle = rng.randf_range(0.0, TAU)
		var speed = rng.randf_range(60.0, 220.0)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": color,
			"life": rng.randf_range(0.3, 0.5),
			"max_life": 0.5
		})


func _spawn_explosion(pos: Vector2) -> void:
	for i in range(32):
		var angle = rng.randf_range(0.0, TAU)
		var speed = rng.randf_range(60.0, 320.0)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": Color(1.0, rng.randf_range(0.1, 0.5), 0.55),
			"life": 0.6,
			"max_life": 0.6
		})


func _spawn_items() -> void:
	var spawn_x: float = get_viewport_rect().size.x + 80.0
	var overhead: bool = rng.randf() < 0.4

	obstacles.append({
		"x": spawn_x,
		"overhead": overhead
	})

	if rng.randf() < 0.7:
		var coin_y = rng.randf_range(270.0, 360.0) if not overhead else FLOOR_Y - 30.0
		coins.append({
			"x": spawn_x + rng.randf_range(160.0, 260.0),
			"y": coin_y,
			"bob": rng.randf_range(0.0, TAU)
		})


func _jump() -> void:
	if player_bottom >= FLOOR_Y and not is_sliding:
		vertical_speed = JUMP_FORCE
		_spawn_burst(Vector2(PLAYER_X, FLOOR_Y), Color(0.0, 0.95, 1.0), 8)


func _begin_slide() -> void:
	if player_bottom >= FLOOR_Y and not is_sliding:
		is_sliding = true
		slide_timer = 0.6
		_spawn_burst(Vector2(PLAYER_X, FLOOR_Y), Color(1.0, 0.15, 0.55), 8)


func _check_collisions() -> void:
	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	var player_rect := Rect2(PLAYER_X - PLAYER_WIDTH / 2.0, player_top, PLAYER_WIDTH, player_height)

	for obstacle in obstacles:
		var x: float = float(obstacle["x"])
		var hitbox: Rect2
		if bool(obstacle["overhead"]):
			hitbox = Rect2(x - 26.0, FLOOR_Y - 68.0, 52.0, 30.0)
		else:
			hitbox = Rect2(x - 24.0, FLOOR_Y - 50.0, 48.0, 50.0)

		if player_rect.intersects(hitbox):
			_end_game()
			return

	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		var coin_rect := Rect2(float(coin["x"]) - 14.0, float(coin["y"]) - 14.0, 28.0, 28.0)
		if player_rect.intersects(coin_rect):
			coin_count += 1
			_spawn_burst(Vector2(coin["x"], coin["y"]), Color(1.0, 0.82, 0.15), 10)
			floating_texts.append({
				"text": "+30",
				"pos": Vector2(float(coin["x"]), float(coin["y"]) - 20.0),
				"life": 0.6,
				"color": Color(1.0, 0.82, 0.15)
			})
			coins.remove_at(i)


func _end_game() -> void:
	if state != GameState.PLAYING:
		return
	state = GameState.GAME_OVER
	score = int(elapsed * 12.0) + coin_count * 30
	_spawn_explosion(Vector2(PLAYER_X, player_bottom - PLAYER_HEIGHT * 0.5))
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

	# 1. Deep Cyber Background Gradient Fill
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.015, 0.01, 0.05))

	# 2. Glowing Perspective Grid Lines (Vaporwave horizon)
	var grid_scroll = fmod(anim_timer * world_speed * 0.1, 70.0)
	for i in range(-2, int(screen_size.x / 70.0) + 3):
		var gx = float(i) * 70.0 - grid_scroll
		draw_line(Vector2(gx, 0.0), Vector2(gx + (gx - screen_size.x * 0.5) * 0.7, FLOOR_Y), Color(0.12, 0.06, 0.25, 0.35), 1.0)

	for j in range(4):
		var gy = FLOOR_Y - float(j * 45)
		draw_line(Vector2(0.0, gy), Vector2(screen_size.x, gy), Color(0.6, 0.1, 0.5, 0.06 * float(4 - j)), 1.5)

	# 3. Parallax Skyline Layer 1 (Distant Silhouette Buildings)
	var scroll_d = fmod(elapsed * world_speed * 0.05, 120.0)
	for i in range(-1, 14):
		var bx = float(i) * 120.0 - scroll_d
		var bh = 90.0 + float((i * 37 + 120) % 110)
		draw_rect(Rect2(bx, FLOOR_Y - bh, 80.0, bh), Color(0.04, 0.02, 0.1))

	# 4. Parallax Skyline Layer 2 (Foreground Neon Buildings)
	var scroll_f = fmod(elapsed * world_speed * 0.12, 95.0)
	for i in range(-1, 13):
		var bx = float(i) * 95.0 - scroll_f
		var bh = 60.0 + float((i * 23 + 70) % 85)
		draw_rect(Rect2(bx, FLOOR_Y - bh, 60.0, bh), Color(0.07, 0.04, 0.17))
		if i % 2 == 0:
			draw_rect(Rect2(bx + 12.0, FLOOR_Y - bh + 14.0, 12.0, 16.0), Color(0.0, 0.95, 1.0, 0.2))

	# 5. Glowing Floor Line
	draw_rect(Rect2(0.0, FLOOR_Y, screen_size.x, screen_size.y - FLOOR_Y), Color(0.02, 0.015, 0.07))
	draw_line(Vector2(0.0, FLOOR_Y), Vector2(screen_size.x, FLOOR_Y), Color(0.0, 0.95, 1.0), 4.0)
	draw_line(Vector2(0.0, FLOOR_Y + 3.0), Vector2(screen_size.x, FLOOR_Y + 3.0), Color(0.0, 0.4, 0.6), 2.0)

	# 6. Obstacles
	for obstacle in obstacles:
		var x: float = float(obstacle["x"])
		if bool(obstacle["overhead"]):
			draw_rect(Rect2(x - 26.0, FLOOR_Y - 68.0, 52.0, 30.0), Color(0.05, 0.03, 0.12))
			draw_rect(Rect2(x - 26.0, FLOOR_Y - 68.0, 52.0, 30.0), Color(1.0, 0.15, 0.55), false, 2.5)
			draw_line(Vector2(x - 26.0, FLOOR_Y - 38.0), Vector2(x - 26.0, FLOOR_Y), Color(1.0, 0.15, 0.55), 4.0)
			draw_line(Vector2(x + 26.0, FLOOR_Y - 38.0), Vector2(x + 26.0, FLOOR_Y), Color(1.0, 0.15, 0.55), 4.0)
		else:
			var points = PackedVector2Array([
				Vector2(x - 24.0, FLOOR_Y),
				Vector2(x, FLOOR_Y - 50.0),
				Vector2(x + 24.0, FLOOR_Y)
			])
			draw_colored_polygon(points, Color(0.12, 0.02, 0.08))
			draw_polyline(points + PackedVector2Array([points[0]]), Color(1.0, 0.15, 0.55), 3.0, true)

	# 7. Coins with Bobbing Animation
	for coin in coins:
		var bob = sin(anim_timer * 6.0 + float(coin["bob"])) * 4.0
		var center := Vector2(float(coin["x"]), float(coin["y"]) + bob)
		draw_circle(center, 14.0, Color(1.0, 0.82, 0.15, 0.3))
		draw_circle(center, 12.0, Color(1.0, 0.82, 0.15))
		draw_circle(center, 6.0, Color(0.08, 0.05, 0.15))

	# 8. Player Trails
	for t in player_trails:
		var a = t["alpha"]
		if a > 0.0:
			draw_rect(Rect2(t["pos"] - t["size"] * 0.5, t["size"]), Color(0.0, 0.95, 1.0, a * 0.4))

	# 9. Particles
	for p in particles:
		var alpha = p["life"] / p["max_life"]
		var c = p["color"]
		c.a = alpha
		draw_circle(p["pos"], 3.0 * alpha + 1.5, c)

	# 10. Floating Score Popups
	for ft in floating_texts:
		var alpha = ft["life"] / 0.6
		var col = ft["color"]
		col.a = alpha
		var font = ThemeDB.fallback_font
		if font:
			draw_string(font, ft["pos"], ft["text"], HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16, col)

	# 11. Player (With Squish and Stretch Juice)
	if state == GameState.PLAYING or state == GameState.PAUSED:
		var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
		var player_top: float = player_bottom - player_height
		var current_width = PLAYER_WIDTH
		if vertical_speed < 0.0:
			player_height += 6.0
			current_width -= 6.0
			player_top -= 6.0
		elif vertical_speed > 200.0:
			player_height -= 6.0
			current_width += 6.0
			player_top += 6.0

		var player_rect = Rect2(PLAYER_X - current_width / 2.0, player_top, current_width, player_height)
		draw_rect(player_rect.grow(3.0), Color(0.0, 0.95, 1.0, 0.25))
		draw_rect(player_rect, Color(0.03, 0.03, 0.1))
		draw_rect(player_rect, Color(0.0, 0.95, 1.0), false, 2.5)
		draw_rect(Rect2(PLAYER_X - 8.0, player_top + 12.0, 16.0, 8.0), Color(0.0, 0.95, 1.0))

	# 12. Top HUD Scoreboard Bar
	draw_rect(Rect2(12.0, 12.0, 360.0, 42.0), Color(0.03, 0.02, 0.09, 0.85))
	draw_rect(Rect2(12.0, 12.0, 360.0, 42.0), Color(0.0, 0.95, 1.0), false, 1.5)
	var font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(24.0, 39.0), "SCORE: %d    COINS: %d    BEST: %d" % [score, coin_count, best_score], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color.WHITE)

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
	_draw_panel(screen_size, Vector2(400.0, 340.0))
	_draw_centered_text(screen_size, 185.0, "NEON DASH RUNNER", 36, Color(0.0, 0.95, 1.0))
	_draw_centered_text(screen_size, 230.0, "Jump over obstacles & slide under barriers!", 16, Color(0.8, 0.8, 0.95))
	_draw_centered_text(screen_size, 265.0, "Best Score: %d" % best_score, 18, Color(1.0, 0.82, 0.15))
	_draw_button("TAP TO PLAY", Vector2(screen_size.x * 0.5, 335.0), Vector2(240.0, 52.0), "start", Color(0.0, 0.95, 1.0))
	_draw_centered_text(screen_size, 415.0, "SPACE / UP: Jump   |   DOWN / SHIFT: Slide", 15, Color(0.65, 0.65, 0.85))


func _draw_pause_menu(screen_size: Vector2) -> void:
	_draw_overlay(screen_size)
	_draw_panel(screen_size, Vector2(360.0, 300.0))
	_draw_centered_text(screen_size, 210.0, "GAME PAUSED", 32, Color(0.0, 0.95, 1.0))
	_draw_button("RESUME", Vector2(screen_size.x * 0.5, 275.0), Vector2(210.0, 46.0), "resume", Color(0.0, 0.95, 1.0))
	_draw_button("RESTART", Vector2(screen_size.x * 0.5, 335.0), Vector2(210.0, 46.0), "restart", Color(1.0, 0.82, 0.15))
	_draw_button("MAIN MENU", Vector2(screen_size.x * 0.5, 395.0), Vector2(210.0, 46.0), "menu", Color(1.0, 0.15, 0.55))


func _draw_game_over(screen_size: Vector2) -> void:
	_draw_overlay(screen_size)
	_draw_panel(screen_size, Vector2(400.0, 350.0))
	_draw_centered_text(screen_size, 175.0, "SYSTEM FAILURE", 36, Color(1.0, 0.15, 0.55))
	_draw_centered_text(screen_size, 225.0, "Score: %d     Coins Collected: %d" % [score, coin_count], 18, Color.WHITE)
	_draw_centered_text(screen_size, 260.0, "Personal Best: %d" % best_score, 18, Color(1.0, 0.82, 0.15))
	_draw_button("PLAY AGAIN", Vector2(screen_size.x * 0.5, 325.0), Vector2(230.0, 50.0), "restart", Color(0.0, 0.95, 1.0))
	_draw_button("MAIN MENU", Vector2(screen_size.x * 0.5, 390.0), Vector2(230.0, 50.0), "menu", Color(1.0, 0.15, 0.55))


func _draw_overlay(screen_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.01, 0.005, 0.04, 0.85))


func _draw_panel(screen_size: Vector2, size: Vector2) -> void:
	var pos = Vector2((screen_size.x - size.x) * 0.5, (screen_size.y - size.y) * 0.5 - 20.0)
	var rect = Rect2(pos, size)
	draw_rect(rect, Color(0.03, 0.025, 0.09, 0.95))
	draw_rect(rect, Color(0.0, 0.95, 1.0, 0.4), false, 2.0)


func _draw_centered_text(screen_size: Vector2, baseline_y: float, message: String, font_size: int, color: Color) -> void:
	var font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(0.0, baseline_y), message, HORIZONTAL_ALIGNMENT_CENTER, screen_size.x, font_size, color)


func _draw_button(label: String, center: Vector2, size: Vector2, action: String, accent: Color) -> void:
	var rect := Rect2(center - size * 0.5, size)
	draw_rect(rect, Color(0.05, 0.04, 0.15, 0.98), true)
	draw_rect(rect, accent, false, 2.5)
	
	var font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(rect.position.x, center.y + 7.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 19, Color.WHITE)

	clickable_buttons.append({
		"rect": rect,
		"action": action
	})
