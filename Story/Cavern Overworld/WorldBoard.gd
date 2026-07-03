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

var window_origin: Vector2i = Vector2i.ZERO
var rest_set: Dictionary = {}     # Vector2i sanctuary tiles -> true (set by the controller)
var gem_set: Dictionary = {}      # Vector2i gemstone nodes -> true (set by the controller)
const GEM_PATH := "res://Assets/Sprites/Gemstone_sprite.png"
var gem_tex: Texture2D = null     # gemstone node art; falls back to the purple tile if absent
const BORDER_BLOCKER_PATH := "res://Assets/Sprites/blocker.png"   # the ring that contours the world
var border_tex: Texture2D = null

func setup_world(g: Grid) -> void:
	grid = g
	scale = Vector2(ViewConfig.BOARD_SCALE, ViewConfig.BOARD_SCALE)   # match the duel board's scale
	if bg_tex == null and ResourceLoader.exists(BG_PATH):
		bg_tex = load(BG_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if blocker_tex == null and ResourceLoader.exists(BLOCKER_PATH):
		blocker_tex = load(BLOCKER_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if gem_tex == null and ResourceLoader.exists(GEM_PATH):
		gem_tex = load(GEM_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if border_tex == null and ResourceLoader.exists(BORDER_BLOCKER_PATH):
		border_tex = load(BORDER_BLOCKER_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_window(Vector2i.ZERO)

# Move the visible window so it starts at world tile `origin`. Offsetting position by
# -origin*TILE places the window onto the fixed board rect at BOARD_ORIGIN; _base_pos
# is updated too so BoardView's shake still works from the right rest position.
func set_window(origin: Vector2i) -> void:
	window_origin = origin
	var p := ViewConfig.BOARD_ORIGIN - Vector2(origin.x * ViewConfig.TILE, origin.y * ViewConfig.TILE) * ViewConfig.BOARD_SCALE
	position = p
	_base_pos = p
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	var T := ViewConfig.TILE
	var w: int = grid.blocked.size()
	for ly in range(ViewConfig.VIEW_TILES):
		for lx in range(ViewConfig.VIEW_TILES):
			var wx := window_origin.x + lx
			var wy := window_origin.y + ly
			var rect := Rect2(wx * T, wy * T, T, T)   # absolute world-local; node offset maps it on-screen
			var solid := true                          # out of world -> void/wall
			if wx >= 0 and wy >= 0 and wx < w and wy < w:
				solid = grid.blocked[wy][wx]
			if solid:
				# The ring that contours the world uses blocker.png; interior walls use Blocker 2.png,
				# rotated per-tile for the same purple weave as the duel board (a flat grid reads grey).
				var is_border: bool = wx <= 0 or wy <= 0 or wx >= w - 1 or wy >= w - 1
				if is_border and border_tex:
					draw_texture_rect(border_tex, rect, false)
				elif blocker_tex:
					var c := rect.position + rect.size * 0.5
					var rot := float((wx * 3 + wy * 5) % 4) * (PI / 2.0)
					draw_set_transform(c, rot, Vector2.ONE)
					draw_texture_rect(blocker_tex, Rect2(-T * 0.5, -T * 0.5, T, T), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
				if gem_set.has(Vector2i(wx, wy)):         # gemstone node
					if gem_tex:
						draw_texture_rect(gem_tex, rect, false)
					else:
						draw_rect(rect, ViewConfig.COL_GEM_FILL)
						draw_rect(rect, ViewConfig.COL_GEM, false, 2.0)
			draw_rect(rect, ViewConfig.COL_GRID_LINE, false, 1.0)
	for pos in highlights:
		draw_rect(Rect2(pos.x * T, pos.y * T, T, T), highlight_color)
	for pos in fx_tiles:
		draw_rect(Rect2(pos.x * T, pos.y * T, T, T), fx_color)
	# window frame is drawn by UIFrame (crisp purple, screen-fixed) -- no per-board edge here
