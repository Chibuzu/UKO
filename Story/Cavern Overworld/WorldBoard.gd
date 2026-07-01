# WorldBoard.gd
# BoardView for story mode. It looks EXACTLY like the PLAY board -- fixed 12x12 at the
# normal board origin, in plain screen space (no camera) -- but it renders a 12x12
# WINDOW into the 60x60 world that the controller re-centers on the player as they
# step. The trick: it draws the window's tiles at their absolute world-local coords and
# offsets its own node position by -window_origin*TILE, so the window maps onto the
# fixed board rect AND the unit figures (children at absolute tile_center) line up with
# no per-unit math. Reuses BoardView's shake / spawn_number / flash_tiles / highlights
# unchanged; nothing in BoardView is modified.
class_name WorldBoard
extends BoardView

const VIEW_TILES := 12
var window_origin: Vector2i = Vector2i.ZERO
var rest_set: Dictionary = {}     # Vector2i sanctuary tiles -> true (set by the controller)
var gem_set: Dictionary = {}      # Vector2i gemstone nodes -> true (set by the controller)

func setup_world(g: Grid) -> void:
	grid = g
	if bg_tex == null and ResourceLoader.exists(BG_PATH):
		bg_tex = load(BG_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if blocker_tex == null and ResourceLoader.exists(BLOCKER_PATH):
		blocker_tex = load(BLOCKER_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_window(Vector2i.ZERO)

# Move the visible window so it starts at world tile `origin`. Offsetting position by
# -origin*TILE places the window onto the fixed board rect at BOARD_ORIGIN; _base_pos
# is updated too so BoardView's shake still works from the right rest position.
func set_window(origin: Vector2i) -> void:
	window_origin = origin
	var p := ViewConfig.BOARD_ORIGIN - Vector2(origin.x * ViewConfig.TILE, origin.y * ViewConfig.TILE)
	position = p
	_base_pos = p
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	var T := ViewConfig.TILE
	var w: int = grid.blocked.size()
	for ly in range(VIEW_TILES):
		for lx in range(VIEW_TILES):
			var wx := window_origin.x + lx
			var wy := window_origin.y + ly
			var rect := Rect2(wx * T, wy * T, T, T)   # absolute world-local; node offset maps it on-screen
			var solid := true                          # out of world -> void/wall
			if wx >= 0 and wy >= 0 and wx < w and wy < w:
				solid = grid.blocked[wy][wx]
			if solid:
				if blocker_tex:
					draw_texture_rect(blocker_tex, rect, false)
				else:
					draw_rect(rect, ViewConfig.COL_BLOCKED)
			else:
				if bg_tex:
					draw_texture_rect(bg_tex, rect, false)
				else:
					draw_rect(rect, ViewConfig.COL_OPEN)
				if rest_set.has(Vector2i(wx, wy)):        # golden sanctuary tile
					draw_rect(rect, ViewConfig.COL_REST_FILL)
					draw_rect(rect, ViewConfig.COL_GOLD, false, 2.0)
				if gem_set.has(Vector2i(wx, wy)):         # purple gemstone node
					draw_rect(rect, ViewConfig.COL_GEM_FILL)
					draw_rect(rect, ViewConfig.COL_GEM, false, 2.0)
			draw_rect(rect, ViewConfig.COL_GRID_LINE, false, 1.0)
	for pos in highlights:
		draw_rect(Rect2(pos.x * T, pos.y * T, T, T), highlight_color)
	for pos in fx_tiles:
		draw_rect(Rect2(pos.x * T, pos.y * T, T, T), fx_color)
	var edge := Rect2(window_origin.x * T, window_origin.y * T, VIEW_TILES * T, VIEW_TILES * T)
	draw_rect(edge, ViewConfig.COL_BOARD_EDGE, false, 2.0)
