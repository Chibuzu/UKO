# BoardView.gd
# Draws the 12x12 arena from a Grid. Pure rendering — it reads grid data and
# paints tiles; it never changes game state. Units and floating numbers are
# added as children so they sit in board-local coordinates.
class_name BoardView
extends Node2D

signal tile_clicked(pos: Vector2i)
signal selection_cancelled()

var grid: Grid
var highlights: Array = []                      # Array[Vector2i]
var highlight_color: Color = ViewConfig.COL_HL_MOVE
var fx_tiles: Array = []                         # transient spell-effect overlay
var fx_color: Color = ViewConfig.COL_FX_AOE
var ghost_tiles: Array = []                     # tiles becoming walls at the next quadrant shift
var _base_pos: Vector2 = ViewConfig.BOARD_ORIGIN # rest position (shake offsets from here)
var _shake := 0.0                                # current shake magnitude
var _quake_t := 0.0                              # earthquake time remaining (seconds)
var _quake_amp := 0.0                            # current per-wall tremble amplitude (for _draw)
const BG_PATH := "res://assets/sprites/map_bg.png"
var bg_tex: Texture2D = null                     # decorative floor; live blockers draw on top
const BLOCKER_PATH := "res://Assets/Sprites/Blocker 2.png"
var blocker_tex: Texture2D = null                # wall tile art; rotated per-tile for variety

func setup(g: Grid) -> void:
	grid = g
	scale = Vector2(ViewConfig.BOARD_SCALE, ViewConfig.BOARD_SCALE)   # board is the scaled-up centrepiece
	position = ViewConfig.BOARD_ORIGIN
	_base_pos = position
	if bg_tex == null and ResourceLoader.exists(BG_PATH):
		bg_tex = load(BG_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel floor
	if blocker_tex == null and ResourceLoader.exists(BLOCKER_PATH):
		blocker_tex = load(BLOCKER_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel walls
	queue_redraw()

# Kick the board for a quick screen shake (decays in _process).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

# Start an earthquake: a sustained rolling rumble used when the arena quadrants
# shift. Bigger and far longer than a hit-shake, and the walls tremble too (_draw).
func earthquake() -> void:
	_quake_t = ViewConfig.QUAKE_DUR

func _process(delta: float) -> void:
	var off := Vector2.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * ViewConfig.SHAKE_DECAY)
		off += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	if _quake_t > 0.0:
		_quake_t = maxf(0.0, _quake_t - delta)
		var env := _quake_t / ViewConfig.QUAKE_DUR        # 1 -> 0
		env *= env                                        # ease-out: violent, then settling
		var amp := ViewConfig.QUAKE_AMP * env
		var tt := ViewConfig.QUAKE_DUR - _quake_t
		# Rolling ground (low-freq sway, stronger on X) plus a little fine jitter.
		off += Vector2(sin(tt * 46.0), sin(tt * 39.0 + 1.7) * 0.6) * amp
		off += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amp * 0.35
		_quake_amp = ViewConfig.QUAKE_TILE * env
		queue_redraw()                                    # walls tremble per-frame during the quake
	elif _quake_amp != 0.0:
		_quake_amp = 0.0
		queue_redraw()
	if _shake > 0.0 or _quake_t > 0.0:
		position = _base_pos + off
	elif position != _base_pos:
		position = _base_pos

func _draw() -> void:
	if grid == null:
		return
	var total := Grid.SIZE * ViewConfig.TILE
	var qtime := Time.get_ticks_msec() / 1000.0   # phase clock for the wall tremble
	if bg_tex:
		draw_texture_rect(bg_tex, Rect2(0, 0, total, total), false)   # decorative floor
	for y in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			var rect := Rect2(x * ViewConfig.TILE, y * ViewConfig.TILE, ViewConfig.TILE, ViewConfig.TILE)
			if grid.blocked[y][x]:
				if blocker_tex:
					# Wall art, rotated 0/90/180/270 by a stable per-tile hash so the
					# weave varies across the arena (square tile stays aligned).
					var c := rect.position + rect.size * 0.5
					if _quake_amp > 0.0:
						# Each wall trembles on its own phase, settling as the quake fades.
						var ph := float(x * 7 + y * 13)
						c += Vector2(sin(qtime * 55.0 + ph), cos(qtime * 48.0 + ph * 1.3)) * _quake_amp
					var rot := float((x * 3 + y * 5) % 4) * (PI / 2.0)
					draw_set_transform(c, rot, Vector2.ONE)
					draw_texture_rect(blocker_tex,
						Rect2(-ViewConfig.TILE * 0.5, -ViewConfig.TILE * 0.5, ViewConfig.TILE, ViewConfig.TILE), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)   # reset for later draws
				else:
					draw_rect(rect, ViewConfig.COL_BLOCKED)              # fallback wall when art missing
			elif bg_tex == null:
				draw_rect(rect, ViewConfig.COL_OPEN)                 # fallback floor when art missing
			draw_rect(rect, ViewConfig.COL_GRID_LINE, false, 1.0)   # visible grid overlay, on top of the floor
	# Highlight overlays for tiles the player can target this step.
	for pos in highlights:
		var hr := Rect2(pos.x * ViewConfig.TILE, pos.y * ViewConfig.TILE, ViewConfig.TILE, ViewConfig.TILE)
		draw_rect(hr, highlight_color)
	# Transient spell-effect overlay.
	for pos in fx_tiles:
		var fr := Rect2(pos.x * ViewConfig.TILE, pos.y * ViewConfig.TILE, ViewConfig.TILE, ViewConfig.TILE)
		draw_rect(fr, fx_color)
	# Telegraph overlay: tiles about to become walls at the next quadrant shift.
	for pos in ghost_tiles:
		var gr := Rect2(pos.x * ViewConfig.TILE, pos.y * ViewConfig.TILE, ViewConfig.TILE, ViewConfig.TILE)
		draw_rect(gr, ViewConfig.COL_GHOST_WALL)
		draw_rect(gr, ViewConfig.COL_GHOST_EDGE, false, 2.0)
	# board frame is drawn by UIFrame (crisp purple, screen-fixed) -- no per-board edge here

# Briefly paint a set of tiles (a spell's footprint), then clear them.
func flash_tiles(tiles: Array, color: Color) -> void:
	fx_tiles = tiles
	fx_color = color
	queue_redraw()
	var timer := get_tree().create_timer(ViewConfig.FX_DUR)
	timer.timeout.connect(func():
		fx_tiles = []
		queue_redraw()
	)

func set_highlights(tiles: Array, color: Color) -> void:
	highlights = tiles
	highlight_color = color
	queue_redraw()

func clear_highlights() -> void:
	highlights = []
	queue_redraw()

func set_ghost(tiles: Array) -> void:
	ghost_tiles = tiles
	queue_redraw()

func clear_ghost() -> void:
	ghost_tiles = []
	queue_redraw()

# Translate a click into a grid tile and emit it. Right-click cancels. Clicks
# outside the board are ignored so the action menu can handle its own.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		selection_cancelled.emit()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var local := get_local_mouse_position()
	var tile := Vector2i(int(floor(local.x / ViewConfig.TILE)), int(floor(local.y / ViewConfig.TILE)))
	if grid != null and grid.in_bounds(tile):
		tile_clicked.emit(tile)

# Spawn a number (damage, healing) that floats up and fades. local_pos is in
# board-local space — pass a unit's `position` directly, since units are
# children of the board.
func spawn_number(local_pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	add_child(lbl)
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	lbl.position = local_pos + Vector2(-8, -ViewConfig.TILE * 0.55)
	var t := create_tween().set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y - 30.0, ViewConfig.LABEL_DUR)
	t.tween_property(lbl, "modulate:a", 0.0, ViewConfig.LABEL_DUR)
	t.finished.connect(lbl.queue_free)
