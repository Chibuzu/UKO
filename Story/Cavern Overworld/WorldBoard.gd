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
var mushroom_set: Dictionary = {} # Vector2i mushroom nodes -> true (rare gatherables)
var portal_set: Dictionary = {}   # Vector2i boss-portal pads -> true (drawn glowing purple)
var building_set: Dictionary = {} # Vector2i village building footprints -> floor here + sprite on top
const GEM_PATH := "res://Assets/Sprites/Gemstone_sprite.png"
var gem_tex: Texture2D = null     # gemstone node art; falls back to the purple tile if absent
var mush_tex: Texture2D = null    # mushroom node art; falls back to the drawn cap+stem
const MUSH_PATH := "res://Assets/Sprites/Mushroom_1.png"
# Village art (houses/market/player home static; well + belt are 4-frame animations at 4 FPS).
const VILLAGE_DIR := "res://Assets/Sprites/Village/"
const HOUSE_FILES := ["Double_home_1.png", "Double_home_2.png", "Double_home_3.png"]
const WELL_FILES := ["Water_well_1.png", "Water_Well_2.png", "Water_Well_3.png", "Water_well_4.png"]
const TRANSPORT_FILES := ["Transport_1.png", "Transport_2.png", "Transport_3.png", "Transport_4.png"]
var _houses: Array = []
var _well: Array = []
var _transport: Array = []
var _market: Texture2D = null
var _player_home: Texture2D = null
var _anim_t: float = 0.0
# BORDER_BLOCKER_PATH / border_tex are inherited from BoardView (shared with the duel's shrink ring).

func setup_world(g: Grid) -> void:
	grid = g
	scale = Vector2(ViewConfig.VIEW_SCALE, ViewConfig.VIEW_SCALE)   # match the duel board's scale
	if bg_tex == null and ResourceLoader.exists(BG_PATH):
		bg_tex = load(BG_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if blocker_tex == null and ResourceLoader.exists(BLOCKER_PATH):
		blocker_tex = load(BLOCKER_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if gem_tex == null and ResourceLoader.exists(GEM_PATH):
		gem_tex = load(GEM_PATH)
	if mush_tex == null and ResourceLoader.exists(MUSH_PATH):
		mush_tex = load(MUSH_PATH)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if border_tex == null and ResourceLoader.exists(BORDER_BLOCKER_PATH):
		border_tex = load(BORDER_BLOCKER_PATH)
	if _houses.is_empty():
		for f in HOUSE_FILES:
			_houses.append(_load_village(f))
		for f in WELL_FILES:
			_well.append(_load_village(f))
		for f in TRANSPORT_FILES:
			_transport.append(_load_village(f))
		_market = _load_village("Market.png")
		_player_home = _load_village("Players_home_.png")
		set_process(true)   # drive the well + belt animation
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_window(Vector2i.ZERO)

func _load_village(fname: String) -> Texture2D:
	var p := VILLAGE_DIR + fname
	return load(p) if ResourceLoader.exists(p) else null

func _process(delta: float) -> void:
	_anim_t += delta
	queue_redraw()

# Move the visible window so it starts at world tile `origin`. Offsetting position by
# -origin*TILE places the window onto the fixed board rect at BOARD_ORIGIN; _base_pos
# is updated too so BoardView's shake still works from the right rest position.
func set_window(origin: Vector2i) -> void:
	window_origin = origin
	var p := Vector2.ZERO - Vector2(origin.x * ViewConfig.TILE, origin.y * ViewConfig.TILE) * ViewConfig.VIEW_SCALE
	position = p
	_base_pos = p
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	var T := ViewConfig.TILE
	var w: int = grid.blocked.size()
	# Floor: draw the 384x384 map_bg ONCE over the whole 12x12 window -- exactly like the duel board.
	# (Drawing it per open tile squished the full image into every tile, so it read differently.)
	if bg_tex:
		var floor_rect := Rect2(window_origin.x * T, window_origin.y * T,
			ViewConfig.VIEW_TILES * T, ViewConfig.VIEW_TILES * T)
		draw_texture_rect(bg_tex, floor_rect, false)
	for ly in range(ViewConfig.VIEW_TILES):
		for lx in range(ViewConfig.VIEW_TILES):
			var wx := window_origin.x + lx
			var wy := window_origin.y + ly
			var rect := Rect2(wx * T, wy * T, T, T)   # absolute world-local; node offset maps it on-screen
			var solid := true                          # out of world -> void/wall
			if wx >= 0 and wy >= 0 and wx < w and wy < w:
				solid = grid.blocked[wy][wx]
			if solid:
				if building_set.has(Vector2i(wx, wy)):
					pass   # village building footprint: keep the floor; the sprite is drawn after the loop
				else:
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
				if bg_tex == null:
					draw_rect(rect, ViewConfig.COL_OPEN)      # fallback floor only when art missing
				if rest_set.has(Vector2i(wx, wy)):        # golden sanctuary tile
					draw_rect(rect, ViewConfig.COL_REST_FILL)
					draw_rect(rect, ViewConfig.COL_GOLD, false, 2.0)
				if gem_set.has(Vector2i(wx, wy)):         # gemstone node
					if gem_tex:
						draw_texture_rect(gem_tex, rect, false)
					else:
						draw_rect(rect, ViewConfig.COL_GEM_FILL)
						draw_rect(rect, ViewConfig.COL_GEM, false, 2.0)
				elif portal_set.has(Vector2i(wx, wy)):    # boss portal pad: glowing purple
					draw_rect(rect, Color(0.42, 0.18, 0.66))
					draw_rect(Rect2(rect.position + Vector2(T * 0.18, T * 0.18), Vector2(T * 0.64, T * 0.64)), Color(0.72, 0.42, 1.0))
					draw_rect(rect, Color(0.90, 0.62, 1.0), false, 2.0)
				elif mushroom_set.has(Vector2i(wx, wy)):  # mushroom node (rare)
					if mush_tex:
						draw_texture_rect(mush_tex, rect, false)
					else:
						var stem := Rect2(rect.position + Vector2(T * 0.40, T * 0.52), Vector2(T * 0.20, T * 0.30))
						var cap := Rect2(rect.position + Vector2(T * 0.20, T * 0.22), Vector2(T * 0.60, T * 0.34))
						draw_rect(stem, ViewConfig.COL_MUSH_STEM)
						draw_rect(cap, ViewConfig.COL_MUSH)
			draw_rect(rect, ViewConfig.COL_GRID_LINE, false, 1.0)
	_draw_village(T)
	for pos in highlights:
		draw_rect(Rect2(pos.x * T, pos.y * T, T, T), highlight_color)
	for pos in fx_tiles:
		draw_rect(Rect2(pos.x * T, pos.y * T, T, T), fx_color)
	# window frame is drawn by UIFrame (crisp purple, screen-fixed) -- no per-board edge here

# ── village buildings ─────────────────────────────────────────────────────────
func _in_window(t: Vector2i) -> bool:
	var vt: int = ViewConfig.VIEW_TILES
	return t.x >= window_origin.x and t.x < window_origin.x + vt and t.y >= window_origin.y and t.y < window_origin.y + vt

# Buildings + transport belt, in world coords (the node offset maps them into the window).
func _draw_village(T: float) -> void:
	var frame := int(_anim_t * 4.0) % 4          # well + belt: 4 FPS
	if _transport.size() == 4 and _transport[frame]:
		for t in OverworldMap.transport_tiles():
			if _in_window(t):
				draw_texture_rect(_transport[frame], Rect2(t.x * T, t.y * T, T, T), false)
	for b in OverworldMap.village_buildings():
		_draw_building(b, T, frame)

func _draw_building(b: Dictionary, T: float, frame: int) -> void:
	var org := Vector2(int(b["tile"].x) * T, int(b["tile"].y) * T)
	match String(b["kind"]):
		"house":
			if not _houses.is_empty():
				var tex: Texture2D = _houses[int(b["variant"]) % _houses.size()]
				if tex:
					draw_texture_rect(tex, Rect2(org, Vector2(T, T * 2)), false)   # 1x2
		"well":
			if _well.size() == 4 and _well[frame]:
				draw_texture_rect(_well[frame], Rect2(org, Vector2(T * 2, T * 2)), false)   # 2x2
		"market":
			if _market:
				var center := org + Vector2(int(b["w"]) * T, int(b["h"]) * T) * 0.5
				draw_set_transform(center, PI / 2.0, Vector2.ONE)                 # 1x2 sprite -> horizontal 2x1
				draw_texture_rect(_market, Rect2(-T * 0.5, -T, T, T * 2), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"player_home":
			if _player_home:
				draw_texture_rect(_player_home, Rect2(org, Vector2(T, T)), false)   # 1x1
