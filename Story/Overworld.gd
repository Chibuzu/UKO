# Overworld.gd
# A small explorable STORY zone (60x60) that reuses the combat game's real art:
# the floor/wall tiles (map_bg.png / blocker.png) and the character renderer
# (UnitView) for the player and every monster. Movement is TILE-BASED: each press
# steps one tile, the figure slides + plays its walk animation, and the camera
# follows. Falls back to discs/flat tiles when the art isn't loaded (e.g. an
# export that didn't pack resources), so it always runs.
#
# Monsters are proper ENTITIES (the Mob inner class): each owns a Combatant, so it
# already carries pos/facing/hp/mp/energy/gear -- the "resources" a future step
# turns into roaming behaviour (move/attack/pivot) and into the duel you drop into.
class_name Overworld
extends Node2D

const SIZE := 60
const TILE := ViewConfig.TILE          # 32 -- identical tiles to the combat grid
const BG_PATH := "res://assets/sprites/map_bg.png"
const BLOCKER_PATH := "res://assets/sprites/blocker.png"

# Two monster TYPES + a boss, data-driven so adding a type is one row here.
# tint distinguishes them while they share the one character sprite; per-monster
# art later is just a different sprite prefix (a UnitView change, not here).
const MOB_TYPES := {
	"grunt": {"name": "Imp",     "gear": ["dark_focus", "", "", ""],                                   "tint": Color(0.70, 1.0, 0.70), "scale": 1.0},
	"brute": {"name": "Brute",   "gear": ["burst_node", "blink_boots", "", ""],                        "tint": Color(1.0, 0.78, 0.45), "scale": 1.18},
	"boss":  {"name": "WARLORD", "gear": ["discount_charm", "burst_node", "dark_focus", "blink_boots"], "tint": Color(0.85, 0.55, 1.0), "scale": 1.5},
}

class Mob extends RefCounted:
	var type: String = ""
	var name: String = ""
	var tile: Vector2i = Vector2i.ZERO
	var combatant: Combatant = null     # the rules-side entity (gear/resources, future actions)
	var view: UnitView = null           # the on-map figure

var _blocked: Array = []
var _player_tile: Vector2i = Vector2i.ZERO
var _player_combatant: Combatant = null
var _player_view: UnitView = null
var _mobs: Array = []
var _cam: Camera2D
var _move_cd: float = 0.0
var _bg: Texture2D = null
var _blocker: Texture2D = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel tiles
	if ResourceLoader.exists(BG_PATH):
		_bg = load(BG_PATH)
	if ResourceLoader.exists(BLOCKER_PATH):
		_blocker = load(BLOCKER_PATH)
	_generate()
	_spawn_player()
	_spawn_mobs()
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	_cam.global_position = _player_view.position
	_add_hud()

# ── generation ───────────────────────────────────────────────────────────────
func _generate() -> void:
	_blocked = []
	for y in SIZE:
		var row: Array = []
		for x in SIZE:
			row.append(false)
		_blocked.append(row)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for x in SIZE:
		_blocked[0][x] = true
		_blocked[SIZE - 1][x] = true
	for y in SIZE:
		_blocked[y][0] = true
		_blocked[y][SIZE - 1] = true
	var village := Rect2i(SIZE / 2 - 6, SIZE / 2 - 6, 12, 12)   # clear spawn area
	for i in 80:
		var cx := rng.randi_range(2, SIZE - 3)
		var cy := rng.randi_range(2, SIZE - 3)
		if village.has_point(Vector2i(cx, cy)):
			continue
		for j in rng.randi_range(1, 4):
			var bx := clampi(cx + rng.randi_range(-1, 1), 1, SIZE - 2)
			var by := clampi(cy + rng.randi_range(-1, 1), 1, SIZE - 2)
			if not village.has_point(Vector2i(bx, by)):
				_blocked[by][bx] = true

# ── spawning ─────────────────────────────────────────────────────────────────
func _spawn_player() -> void:
	_player_tile = Vector2i(SIZE / 2, SIZE / 2)
	_player_combatant = Combatant.new("A", _player_tile, Config.Facing.SOUTH)
	_player_combatant.equip(PlayerProfile.loadout())     # carry the player's real gear
	_player_view = UnitView.new()
	_player_view.init_state(_player_combatant)
	_player_view.unit_id = ""                            # no label on the player
	add_child(_player_view)

func _spawn_mobs() -> void:
	var placements := [
		["grunt", Vector2i(14, 14)],
		["grunt", Vector2i(20, 44)],
		["brute", Vector2i(46, 18)],
		["brute", Vector2i(40, 41)],
		["boss",  Vector2i(48, 48)],
	]
	for p in placements:
		_spawn_mob(p[0], _nearest_open(p[1]))

func _spawn_mob(type: String, tile: Vector2i) -> void:
	var def: Dictionary = MOB_TYPES[type]
	var c := Combatant.new("B", tile, Config.Facing.SOUTH)
	c.equip(def["gear"])
	var v := UnitView.new()
	v.init_state(c)
	v.unit_id = def["name"]               # label under the figure
	v.base_color = def["tint"]            # tints the fallback disc
	v.modulate = def["tint"]              # tints the real sprite to tell types apart
	v.scale = Vector2(def["scale"], def["scale"])
	add_child(v)
	var m := Mob.new()
	m.type = type
	m.name = def["name"]
	m.tile = tile
	m.combatant = c
	m.view = v
	_mobs.append(m)

# ── tile-based movement ──────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	_cam.global_position = _player_view.position   # follow the sliding figure
	queue_redraw()
	if _move_cd > 0.0:
		_move_cd -= delta
		return
	var dir := _input_dir()
	if dir == Vector2i.ZERO:
		return
	var f := _facing_for(dir)
	if f != _player_combatant.facing:
		_player_combatant.facing = f
		_player_view.set_facing(f)                 # turn to face where we walk
	var target := _player_tile + dir
	if _solid_tile(target):
		_move_cd = 0.12                            # bumped a wall: debounce, don't move
		return
	_player_tile = target
	_player_combatant.pos = target
	_player_view.tween_to(target)                  # slide + walk animation
	_move_cd = ViewConfig.MOVE_DUR                 # one step at a time

func _input_dir() -> Vector2i:
	if Input.is_action_pressed("ui_up")    or Input.is_key_pressed(KEY_W): return Vector2i(0, -1)
	if Input.is_action_pressed("ui_down")  or Input.is_key_pressed(KEY_S): return Vector2i(0, 1)
	if Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A): return Vector2i(-1, 0)
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): return Vector2i(1, 0)
	return Vector2i.ZERO

func _facing_for(dir: Vector2i) -> int:
	for fc in Config.FACING_VEC:                   # invert the shared facing table
		if Config.FACING_VEC[fc] == dir:
			return fc
	return Config.Facing.SOUTH

func _solid_tile(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= SIZE or t.y >= SIZE:
		return true
	return _blocked[t.y][t.x]

# ── draw the real tiles, culled to what's on screen ─────────────────────────
func _draw() -> void:
	var view := _visible_range()
	for y in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			if _blocked[y][x]:
				if _blocker:
					draw_texture_rect(_blocker, r, false)
				else:
					draw_rect(r, ViewConfig.COL_BLOCKED)
			else:
				if _bg:
					draw_texture_rect(_bg, r, false)
				else:
					draw_rect(r, ViewConfig.COL_OPEN)
			draw_rect(r, ViewConfig.COL_GRID_LINE, false, 1.0)

func _visible_range() -> Rect2i:
	var center: Vector2 = _cam.global_position if _cam else _player_view.position
	var half := get_viewport_rect().size * 0.5
	var tl := center - half - Vector2(TILE, TILE)
	var br := center + half + Vector2(TILE, TILE)
	var x0 := clampi(int(tl.x / TILE), 0, SIZE - 1)
	var y0 := clampi(int(tl.y / TILE), 0, SIZE - 1)
	var x1 := clampi(int(br.x / TILE) + 1, 0, SIZE)
	var y1 := clampi(int(br.y / TILE) + 1, 0, SIZE)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)

# ── helpers ──────────────────────────────────────────────────────────────────
func _nearest_open(t: Vector2i) -> Vector2i:
	if not _blocked[t.y][t.x]:
		return t
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := Vector2i(clampi(t.x + dx, 1, SIZE - 2), clampi(t.y + dy, 1, SIZE - 2))
				if not _blocked[n.y][n.x]:
					return n
	return Vector2i(SIZE / 2, SIZE / 2)

func _add_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hint := Label.new()
	hint.text = "STORY ZONE   —   WASD / Arrows: move (tile by tile)    ·    ESC: menu"
	hint.position = Vector2(16, 12)
	hint.add_theme_color_override("font_color", ViewConfig.COL_TEXT)
	layer.add_child(hint)
