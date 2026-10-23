
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
const MAX_SPEED: float = 560.0

var state: GameState = GameState.MENU

var obstacles: Array[Dictionary] = []
var coins: Array[Dictionary] = []
var clickable_buttons: Array[Dictionary] = []

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

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
    rng.randomize()
    _load_best_score()
    queue_redraw()


func _process(delta: float) -> void:
    if state == GameState.PLAYING:
        _update_game(delta)

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
    # Pehle check karein ke kisi actual UI button par click hua hai.
    for button in clickable_buttons:
        var rect: Rect2 = button["rect"]

        if rect.has_point(position):
            _activate_button(str(button["action"]))
            return

    # Gameplay ke touch controls.
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

    world_speed = minf(
        START_SPEED + elapsed * 3.0,
        MAX_SPEED
    )

    score = int(elapsed * 10.0) + coin_count * 25

    # Jump physics: pehle frame se gravity aur movement apply honge.
    if player_bottom < FLOOR_Y or vertical_speed < 0.0:
        vertical_speed += GRAVITY * delta
        player_bottom += vertical_speed * delta

        if player_bottom >= FLOOR_Y:
            player_bottom = FLOOR_Y
            vertical_speed = 0.0

    # Slide ki duration.
    if slide_timer > 0.0:
        slide_timer = maxf(0.0, slide_timer - delta)
        is_sliding = slide_timer > 0.0

    # Fair obstacle spacing.
    spawn_timer -= delta

    if spawn_timer <= 0.0:
        _spawn_items()

        spawn_timer = (
            maxf(1.0, 1.5 - elapsed * 0.004)
            + rng.randf_range(0.15, 0.4)
        )

    # Obstacles move aur cleanup.
    for i in range(obstacles.size() - 1, -1, -1):
        var obstacle: Dictionary = obstacles[i]

        obstacle["x"] = float(obstacle["x"]) - world_speed * delta
        obstacles[i] = obstacle

        if float(obstacle["x"]) < -100.0:
            obstacles.remove_at(i)

    # Coins move aur cleanup.
    for i in range(coins.size() - 1, -1, -1):
        var coin: Dictionary = coins[i]

        coin["x"] = float(coin["x"]) - world_speed * delta
        coins[i] = coin

        if float(coin["x"]) < -50.0:
            coins.remove_at(i)

    _check_collisions()


func _spawn_items() -> void:
    var spawn_x: float = get_viewport_rect().size.x + 60.0
    var overhead: bool = rng.randf() < 0.35

    obstacles.append({
        "x": spawn_x,
        "overhead": overhead
    })

    # Coins obstacle se aage rakhein.
    if rng.randf() < 0.65:
        coins.append({
            "x": spawn_x + rng.randf_range(150.0, 240.0),
            "y": rng.randf_range(300.0, 370.0)
        })


func _jump() -> void:
    if player_bottom >= FLOOR_Y and not is_sliding:
        vertical_speed = JUMP_FORCE


func _begin_slide() -> void:
    if player_bottom >= FLOOR_Y and not is_sliding:
        is_sliding = true
        slide_timer = 0.65


func _check_collisions() -> void:
    var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
    var player_top: float = player_bottom - player_height

    var player_rect := Rect2(
        PLAYER_X - PLAYER_WIDTH / 2.0,
        player_top,
        PLAYER_WIDTH,
        player_height
    )

    for obstacle in obstacles:
        var x: float = float(obstacle["x"])
        var hitbox: Rect2

        if bool(obstacle["overhead"]):
            # Neeche slide karne se overhead obstacle se bach sakte hain.
            hitbox = Rect2(
                x - 25.0,
                FLOOR_Y - 65.0,
                50.0,
                28.0
            )
        else:
            # Ground obstacle ko jump karke cross karein.
            hitbox = Rect2(
                x - 24.0,
                FLOOR_Y - 48.0,
                48.0,
                48.0
            )

        if player_rect.intersects(hitbox):
            _end_game()
            return

    # Coins collect karein.
    for i in range(coins.size() - 1, -1, -1):
        var coin: Dictionary = coins[i]

        var coin_rect := Rect2(
            float(coin["x"]) - 14.0,
            float(coin["y"]) - 14.0,
            28.0,
            28.0
        )

        if player_rect.intersects(coin_rect):
            coin_count += 1
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

    var error: Error = config.save(SAVE_PATH)

    if error != OK:
        push_warning("Best score save nahi ho saka.")


func _draw() -> void:
    clickable_buttons.clear()

    var screen_size: Vector2 = get_viewport_rect().size

    # Background.
    draw_rect(
        Rect2(Vector2.ZERO, screen_size),
        Color(0.025, 0.02, 0.08)
    )

    # Neon skyline.
    var scroll: float = fmod(elapsed * world_speed * 0.08, 92.0)

    for i in range(-1, 13):
        var building_x: float = float(i) * 92.0 - scroll
        var building_height: float = 70.0 + float((i * 37 + 200) % 100)

        draw_rect(
            Rect2(
                building_x,
                FLOOR_Y - building_height,
                64.0,
                building_height
            ),
            Color(0.07, 0.045, 0.17)
        )

    # Ground.
    draw_line(
        Vector2(0.0, FLOOR_Y),
        Vector2(screen_size.x, FLOOR_Y),
        Color(0.0, 0.95, 1.0),
        3.0
    )

    # Obstacles.
    for obstacle in obstacles:
        var x: float = float(obstacle["x"])

        if bool(obstacle["overhead"]):
            draw_rect(
                Rect2(x - 25.0, FLOOR_Y - 65.0, 50.0, 28.0),
                Color(1.0, 0.15, 0.55)
            )

            draw_line(
                Vector2(x - 25.0, FLOOR_Y - 35.0),
                Vector2(x - 25.0, FLOOR_Y - 18.0),
                Color(1.0, 0.15, 0.55),
                4.0
            )

            draw_line(
                Vector2(x + 25.0, FLOOR_Y - 35.0),
                Vector2(x + 25.0, FLOOR_Y - 18.0),
                Color(1.0, 0.15, 0.55),
                4.0
            )
        else:
            draw_colored_polygon(
                PackedVector2Array([
                    Vector2(x - 24.0, FLOOR_Y),
                    Vector2(x, FLOOR_Y - 48.0),
                    Vector2(x + 24.0, FLOOR_Y)
                ]),
                Color(1.0, 0.15, 0.55)
            )

    # Coins.
    for coin in coins:
        var center := Vector2(
            float(coin["x"]),
            float(coin["y"])
        )

        draw_circle(center, 13.0, Color(1.0, 0.82, 0.15))
        draw_circle(center, 7.0, Color(0.12, 0.07, 0.2))

    # Player.
    var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
    var player_top: float = player_bottom - player_height

    draw_rect(
        Rect2(
            PLAYER_X - PLAYER_WIDTH / 2.0,
            player_top,
            PLAYER_WIDTH,
            player_height
        ),
        Color(0.0, 0.95, 1.0)
    )

    draw_rect(
        Rect2(
            PLAYER_X - 10.0,
            player_top + 12.0,
            20.0,
            8.0
        ),
        Color(0.03, 0.03, 0.1)
    )

    # Scoreboard.
    draw_string(
        ThemeDB.fallback_font,
        Vector2(24.0, 36.0),
        "Score: %d   Coins: %d   Best: %d" % [
            score,
            coin_count,
            best_score
        ],
        HORIZONTAL_ALIGNMENT_LEFT,
        -1.0,
        22,
        Color.WHITE
    )

    # Actual UI screens and clickable buttons.
    match state:
        GameState.MENU:
            _draw_menu(screen_size)

        GameState.PAUSED:
            _draw_pause_menu(screen_size)

        GameState.GAME_OVER:
            _draw_game_over(screen_size)


func _draw_menu(screen_size: Vector2) -> void:
    _draw_overlay(screen_size)

    _draw_centered_text(
        screen_size,
        190.0,
        "NEON DASH RUNNER",
        38,
        Color(0.0, 0.95, 1.0)
    )

    _draw_centered_text(
        screen_size,
        235.0,
        "Jump over spikes. Slide under neon barriers. Collect coins!",
        17,
        Color.WHITE
    )

    _draw_centered_text(
        screen_size,
        270.0,
        "Best Score: %d" % best_score,
        19,
        Color(1.0, 0.82, 0.15)
    )

    _draw_button(
        "PLAY GAME",
        Vector2(screen_size.x * 0.5, 335.0),
        Vector2(220.0, 54.0),
        "start",
        Color(0.0, 0.95, 1.0)
    )

    _draw_centered_text(
        screen_size,
        425.0,
        "Keyboard: SPACE jump | DOWN slide | P pause",
        16,
        Color(0.75, 0.75, 0.9)
    )

    _draw_centered_text(
        screen_size,
        455.0,
        "Mobile: tap left to jump, right to slide",
        16,
        Color(0.75, 0.75, 0.9)
    )


func _draw_pause_menu(screen_size: Vector2) -> void:
    _draw_overlay(screen_size)

    _draw_centered_text(
        screen_size,
        195.0,
        "GAME PAUSED",
        38,
        Color(0.0, 0.95, 1.0)
    )

    _draw_button(
        "RESUME",
        Vector2(screen_size.x * 0.5, 275.0),
        Vector2(220.0, 50.0),
        "resume",
        Color(0.0, 0.95, 1.0)
    )

    _draw_button(
        "RESTART",
        Vector2(screen_size.x * 0.5, 340.0),
        Vector2(220.0, 50.0),
        "restart",
        Color(1.0, 0.82, 0.15)
    )

    _draw_button(
        "MAIN MENU",
        Vector2(screen_size.x * 0.5, 405.0),
        Vector2(220.0, 50.0),
        "menu",
        Color(1.0, 0.15, 0.55)
    )


func _draw_game_over(screen_size: Vector2) -> void:
    _draw_overlay(screen_size)

    _draw_centered_text(
        screen_size,
        175.0,
        "GAME OVER",
        40,
        Color(1.0, 0.15, 0.55)
    )

    _draw_centered_text(
        screen_size,
        225.0,
        "Score: %d     Coins: %d" % [score, coin_count],
        23,
        Color.WHITE
    )

    _draw_centered_text(
        screen_size,
        263.0,
        "Best Score: %d" % best_score,
        20,
        Color(1.0, 0.82, 0.15)
    )

    _draw_button(
        "PLAY AGAIN",
        Vector2(screen_size.x * 0.5, 325.0),
        Vector2(230.0, 52.0),
        "restart",
        Color(0.0, 0.95, 1.0)
    )

    _draw_button(
        "MAIN MENU",
        Vector2(screen_size.x * 0.5, 393.0),
        Vector2(230.0, 52.0),
        "menu",
        Color(1.0, 0.15, 0.55)
    )


func _draw_overlay(screen_size: Vector2) -> void:
    draw_rect(
        Rect2(Vector2.ZERO, screen_size),
        Color(0.015, 0.01, 0.06, 0.88)
    )


func _draw_centered_text(
    screen_size: Vector2,
    baseline_y: float,
    message: String,
    font_size: int,
    color: Color
) -> void:
    draw_string(
        ThemeDB.fallback_font,
        Vector2(0.0, baseline_y),
        message,
        HORIZONTAL_ALIGNMENT_CENTER,
        screen_size.x,
        font_size,
        color
    )


func _draw_button(
    label: String,
    center: Vector2,
    size: Vector2,
    action: String,
    accent: Color
) -> void:
    var rect := Rect2(center - size * 0.5, size)

    # Button background aur neon border.
    draw_rect(
        rect,
        Color(0.045, 0.035, 0.12, 0.98),
        true
    )

    draw_rect(
        rect,
        accent,
        false,
        2.5
    )

    # Button label.
    draw_string(
        ThemeDB.fallback_font,
        Vector2(rect.position.x, center.y + 7.0),
        label,
        HORIZONTAL_ALIGNMENT_CENTER,
        rect.size.x,
        21,
        Color.WHITE
    )

    # Is rectangle ko mouse aur touch input use karega.
    clickable_buttons.append({
        "rect": rect,
        "action": action
    })
