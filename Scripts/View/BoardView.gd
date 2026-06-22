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

func setup(g: Grid) -> void:
	grid = g
	position = ViewConfig.BOARD_ORIGIN
	_base_pos = position
	queue_redraw()

# Kick the board for a quick screen shake (decays in _process).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * ViewConfig.SHAKE_DECAY)
		position = _base_pos + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	elif position != _base_pos:
		position = _base_pos

func _draw() -> void:
	if grid == null:
		return
	for y in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			var col: Color = ViewConfig.COL_BLOCKED if grid.blocked[y][x] else ViewConfig.COL_OPEN
			var rect := Rect2(x * ViewConfig.TILE, y * ViewConfig.TILE, ViewConfig.TILE, ViewConfig.TILE)
			draw_rect(rect, col)
			draw_rect(rect, ViewConfig.COL_GRID_LINE, false, 1.0)
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
	var total := Grid.SIZE * ViewConfig.TILE
	draw_rect(Rect2(0, 0, total, total), ViewConfig.COL_BOARD_EDGE, false, 2.0)

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
