# Overworld.gd
# The STORY-zone scene controller -- glue only. It owns the map, the player entity,
# and the mob entities, runs the walk loop, and HANDS OFF to a real UKO duel the
# moment you step into a mob's range: it sets up a single-player match (your gear vs
# the mob's kit, at the mob's tier), saves the zone, and switches to Game.tscn. When
# the duel ends the game returns here and the zone restores (same map, your spot, the
# beaten mob gone). All real logic lives in the modules; this just wires them.
class_name Overworld
extends Node2D

const TILE := ViewConfig.TILE
const VIEW_TILES := 12           # camera frames a 12-tile-tall window (battle-board scale)
const GAME_SCENE := "res://Game.tscn"
const STORY_SCENE := "res://Overworld.tscn"
const BG_PATH := "res://assets/sprites/map_bg.png"
const BLOCKER_PATH := "res://Assets/Sprites/Blocker 2.png"
const BORDER_BLOCKER_PATH := "res://Assets/Sprites/blocker.png"   # the ring that contours the world

# Two monster types + a boss, data-driven. They share the one character sprite, told
# apart by tint + scale; per-type art later is a UnitView change, not a change here.
const MOB_TYPES := {
	"grunt": {"name": "Imp",     "gear": ["dark_focus", "", "", ""],                                    "tint": Color(0.70, 1.0, 0.70), "scale": 1.0},
	"brute": {"name": "Brute",   "gear": ["burst_node", "blink_boots", "", ""],                         "tint": Color(1.0, 0.78, 0.45), "scale": 1.18},
	"boss":  {"name": "WARLORD", "gear": ["discount_charm", "burst_node", "dark_focus", "blink_boots"], "tint": Color(0.85, 0.55, 1.0), "scale": 1.5},
}

const DEFAULT_MOBS := [
	{"type": "grunt", "tile": Vector2i(14, 14)},
	{"type": "grunt", "tile": Vector2i(20, 44)},
	{"type": "brute", "tile": Vector2i(46, 18)},
	{"type": "brute", "tile": Vector2i(40, 41)},
	{"type": "boss",  "tile": Vector2i(48, 48)},
]

var _map: OverworldMap
var _player: OverworldEntity
var _mobs: Array = []
var _player_tile: Vector2i
var _cam: Camera2D
var _move_cd: float = 0.0
var _bg: Texture2D = null
var _blocker: Texture2D = null
var _border: Texture2D = null

# Village art. Houses (3 variants) + market + player home are static; the well and the transport
# belt are 4-frame animations played at 4 FPS off a shared clock.
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

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(BG_PATH):
		_bg = load(BG_PATH)
	if ResourceLoader.exists(BLOCKER_PATH):
		_blocker = load(BLOCKER_PATH)
	if ResourceLoader.exists(BORDER_BLOCKER_PATH):
		_border = load(BORDER_BLOCKER_PATH)
	for f in HOUSE_FILES:
		_houses.append(_load_village(f))
	for f in WELL_FILES:
		_well.append(_load_village(f))
	for f in TRANSPORT_FILES:
		_transport.append(_load_village(f))
	_market = _load_village("Market.png")
	_player_home = _load_village("Players_home_.png")
	_map = OverworldMap.new()
	if OverworldState.active:
		_restore()
	else:
		_fresh()
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	_cam.global_position = _player.world_pos()
	_apply_zoom()
	get_viewport().size_changed.connect(_apply_zoom)
	_add_hud()

# ── enter / restore the zone ─────────────────────────────────────────────────
func _fresh() -> void:
	OverworldState.seed_value = randi()
	OverworldState.fighting = -1
	OverworldState.mobs = []
	_map.generate(OverworldState.seed_value)
	_player_tile = _map.nearest_open(OverworldMap.village_center())   # start in the village (bottom-left)
	OverworldState.player_tile = _player_tile
	_spawn_player()
	for d in DEFAULT_MOBS:
		var tile: Vector2i = _map.nearest_open(d["tile"])
		_spawn_mob(d["type"], tile)
		OverworldState.mobs.append({"type": d["type"], "tile": tile})
	OverworldState.active = true

func _restore() -> void:
	# Resolve the duel we just came back from: a win removes that mob for good.
	if OverworldState.fighting >= 0:
		if GameController.last_match_won:
			OverworldState.mobs.remove_at(OverworldState.fighting)
		OverworldState.fighting = -1
	_map.generate(OverworldState.seed_value)
	_player_tile = OverworldState.player_tile
	_spawn_player()
	for entry in OverworldState.mobs:
		_spawn_mob(entry["type"], entry["tile"])
	# Don't instantly re-fight a survivor you're standing next to (after a loss).
	for m in _mobs:
		if m.behavior.in_range(m, _player):
			m.behavior.suppressed = true

# ── spawning ─────────────────────────────────────────────────────────────────
func _spawn_player() -> void:
	# The player carries YOUR equipped gear (PlayerProfile), so it's your real state
	# both on the map and in the duel it hands off to.
	_player = OverworldEntity.make("A", _player_tile, Config.Facing.SOUTH, PlayerProfile.loadout(), "")
	_player.view.z_index = 1
	add_child(_player.view)

func _spawn_mob(type: String, tile: Vector2i) -> void:
	var def: Dictionary = MOB_TYPES[type]
	var e := OverworldEntity.make("B", tile, Config.Facing.SOUTH, def["gear"], def["name"])
	e.tag = type
	e.view.modulate = def["tint"]
	e.view.base_color = def["tint"]
	e.view.scale = Vector2(def["scale"], def["scale"])
	e.behavior = MobBehavior.new()
	add_child(e.view)
	_mobs.append(e)

# ── walk loop ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	_drive_player(delta)
	_cam.global_position = _player.world_pos()
	_anim_t += delta          # drives the well + transport-belt animations
	queue_redraw()

func _drive_player(delta: float) -> void:
	if _move_cd > 0.0:
		_move_cd -= delta
		return
	var dir := _input_dir()
	if dir == Vector2i.ZERO:
		return
	_player.face(_facing_for(dir))
	var target := _player_tile + dir
	if _map.is_solid(target):
		_move_cd = 0.12
		return
	_player_tile = target
	OverworldState.player_tile = target          # keep saved spot current for the hand-off
	_player.step_to(target)
	_move_cd = ViewConfig.MOVE_DUR
	_check_engage()                              # stepped somewhere new -> in any mob's range?

func _check_engage() -> void:
	for i in _mobs.size():
		var m: OverworldEntity = _mobs[i]
		if m.behavior.wants_fight(m, _player):
			_start_duel(i)
			return

# Hand off to a real UKO duel: single-player, your gear vs this mob's kit, at the
# mob's tier. GameController returns here when it ends (see _restore).
func _start_duel(index: int) -> void:
	var m: OverworldEntity = _mobs[index]
	OverworldState.player_tile = _player_tile
	OverworldState.fighting = index
	GameController.pending_b_gear = m.combatant.gear.duplicate()
	GameController.pending_return_scene = STORY_SCENE
	AI.selected_difficulty = _mob_diff(m.tag)
	get_tree().change_scene_to_file(GAME_SCENE)

func _mob_diff(type: String) -> int:
	match type:
		"grunt": return AI.Difficulty.EASY
		"brute": return AI.Difficulty.CHALLENGING
		"boss":  return AI.Difficulty.EXTREME
	return AI.Difficulty.CHALLENGING

# ── camera / input helpers ───────────────────────────────────────────────────
func _apply_zoom() -> void:
	if _cam == null:
		return
	var z := get_viewport_rect().size.y / float(VIEW_TILES * TILE)
	_cam.zoom = Vector2(z, z)

func _input_dir() -> Vector2i:
	if Input.is_action_pressed("ui_up")    or Input.is_key_pressed(KEY_W): return Vector2i(0, -1)
	if Input.is_action_pressed("ui_down")  or Input.is_key_pressed(KEY_S): return Vector2i(0, 1)
	if Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A): return Vector2i(-1, 0)
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): return Vector2i(1, 0)
	return Vector2i.ZERO

func _facing_for(dir: Vector2i) -> int:
	for fc in Config.FACING_VEC:
		if Config.FACING_VEC[fc] == dir:
			return fc
	return Config.Facing.SOUTH

# ── draw tiles, culled to the (zoomed) view ─────────────────────────────────
func _draw() -> void:
	var view := _visible_range()
	for y in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			if _map.blocked[y][x]:
				if _map.is_building(Vector2i(x, y)):
					# Building footprint: floor here; the building sprite is drawn over it in _draw_village.
					if _bg:
						draw_texture_rect(_bg, r, false)
					else:
						draw_rect(r, ViewConfig.COL_OPEN)
				else:
					# Contour ring uses blocker.png; interior walls use Blocker 2.png, rotated per-tile
					# for the same purple weave as the duel board (a flat grid reads grey).
					var is_border: bool = x <= 0 or y <= 0 or x >= OverworldMap.SIZE - 1 or y >= OverworldMap.SIZE - 1
					if is_border and _border:
						draw_texture_rect(_border, r, false)
					elif _blocker:
						var c := r.position + r.size * 0.5
						var rot := float((x * 3 + y * 5) % 4) * (PI / 2.0)
						draw_set_transform(c, rot, Vector2.ONE)
						draw_texture_rect(_blocker, Rect2(-TILE * 0.5, -TILE * 0.5, TILE, TILE), false)
						draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					else:
						draw_rect(r, ViewConfig.COL_BLOCKED)
			else:
				if _bg:
					draw_texture_rect(_bg, r, false)
				else:
					draw_rect(r, ViewConfig.COL_OPEN)
			draw_rect(r, ViewConfig.COL_GRID_LINE, false, 1.0)
	_draw_village(view)

func _load_village(fname: String) -> Texture2D:
	var p := VILLAGE_DIR + fname
	return load(p) if ResourceLoader.exists(p) else null

# Draw the transport belt (on the floor, culled to view) and the buildings on top of the tiles.
func _draw_village(view: Rect2i) -> void:
	var frame := int(_anim_t * 4.0) % 4          # well + belt: 4 FPS
	if _transport.size() == 4 and _transport[frame]:
		for t in OverworldMap.transport_tiles():
			if t.x >= view.position.x and t.x < view.end.x and t.y >= view.position.y and t.y < view.end.y:
				draw_texture_rect(_transport[frame], Rect2(t.x * TILE, t.y * TILE, TILE, TILE), false)
	for b in OverworldMap.village_buildings():
		_draw_building(b, frame)

func _draw_building(b: Dictionary, frame: int) -> void:
	var tile: Vector2i = b["tile"]
	var org := Vector2(tile.x * TILE, tile.y * TILE)
	match String(b["kind"]):
		"house":
			if not _houses.is_empty():
				var tex: Texture2D = _houses[int(b["variant"]) % _houses.size()]
				if tex:
					draw_texture_rect(tex, Rect2(org, Vector2(TILE, TILE * 2)), false)   # 1x2
		"well":
			if _well.size() == 4 and _well[frame]:
				draw_texture_rect(_well[frame], Rect2(org, Vector2(TILE * 2, TILE * 2)), false)   # 2x2
		"market":
			# 1x2 sprite rotated 90 degrees to sit horizontal across a 2x1 footprint.
			if _market:
				var center := org + Vector2(int(b["w"]) * TILE, int(b["h"]) * TILE) * 0.5
				draw_set_transform(center, PI / 2.0, Vector2.ONE)
				draw_texture_rect(_market, Rect2(-TILE * 0.5, -TILE, TILE, TILE * 2), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"player_home":
			if _player_home:
				draw_texture_rect(_player_home, Rect2(org, Vector2(TILE, TILE)), false)   # 1x1

func _visible_range() -> Rect2i:
	var z: float = _cam.zoom.x if _cam else 1.0
	var center: Vector2 = _cam.global_position if _cam else _player.world_pos()
	var half := (get_viewport_rect().size / z) * 0.5
	var tl := center - half - Vector2(TILE, TILE)
	var br := center + half + Vector2(TILE, TILE)
	var sz := OverworldMap.SIZE
	var x0 := clampi(int(tl.x / TILE), 0, sz - 1)
	var y0 := clampi(int(tl.y / TILE), 0, sz - 1)
	var x1 := clampi(int(br.x / TILE) + 1, 0, sz)
	var y1 := clampi(int(br.y / TILE) + 1, 0, sz)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)

func _add_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hint := Label.new()
	hint.text = "STORY ZONE   —   WASD / Arrows: move   ·   walk into a monster to fight   ·   ESC: menu"
	hint.position = Vector2(16, 12)
	hint.add_theme_color_override("font_color", ViewConfig.COL_TEXT)
	layer.add_child(hint)
