# StoryController.gd
# Story mode on ONE screen -- the PLAY combat interface, always, in plain screen space
# (no camera): board centered, action menu left, combat log right, exactly like a match.
# The board is a 12x12 WINDOW into a 60x60 world that re-centers on you as you step with
# WASD; the instant any monster is inside that window the WEGO turn loop begins IN PLACE
# (same menu, same resources, same resolver) -- NO scene change. Multi-mob combat is
# handled by StoryCombat (your AoE hits every mob; every mob hits you; mobs avoid each
# other), animated by your existing EventPlayer for the nearest foe and a light pass for
# the rest. Die and you're sent to the menu, minus some gold. Nothing in the combat
# engine is modified; this controller only wires existing systems onto a world.
class_name StoryController
extends Node

const TILE := ViewConfig.TILE
const VIEW_TILES := 12
const VIEW_RADIUS := 6            # window is player.pos +/- 6 -> the visible 12x12
const MENU_SCENE := "res://MainMenu.tscn"
const DEATH_GOLD_PENALTY := 25

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

enum Phase { ROAM, COMBAT }

var omap: OverworldMap
var grid: WorldGrid
var board: WorldBoard
var fx: Fx
var play: EventPlayer
var menu: ActionMenu
var combat_log: CombatLog
var selection: SelectionController

var player: Combatant
var player_uv: UnitView
var mobs: Array = []              # [{combatant, uv, ai, type}]
var _opp_model: OpponentModel
var turn_num: int = 0
var _phase: int = Phase.ROAM
var _roam_cd: float = 0.0

func _ready() -> void:
	omap = OverworldMap.new()
	omap.generate(randi())
	grid = WorldGrid.new()
	grid.build(omap)

	# Board, menu, log: DIRECT children at their default screen positions -- identical
	# layout to GameController/PLAY. The board just renders a moving window of the world.
	board = WorldBoard.new()
	add_child(board)
	board.setup_world(grid)

	var start := omap.nearest_open(Vector2i(OverworldMap.SIZE / 2, OverworldMap.SIZE / 2))
	player = Combatant.new("A", start, Config.Facing.SOUTH)
	player.equip(PlayerProfile.loadout())          # you carry your real equipped gear
	player_uv = UnitView.new()
	board.add_child(player_uv)
	player_uv.init_state(player)
	player_uv.z_index = 1

	_spawn_mobs()

	fx = Fx.new()
	board.add_child(fx)

	menu = ActionMenu.new()
	add_child(menu)
	combat_log = CombatLog.new()
	add_child(combat_log)

	play = EventPlayer.new()
	add_child(play)
	play.setup(board, fx, player_uv, player_uv)    # B is re-pointed to the nearest mob each turn

	selection = SelectionController.new()
	add_child(selection)
	selection.setup(grid, board, menu)
	board.tile_clicked.connect(selection._on_tile_clicked)
	board.selection_cancelled.connect(selection._on_cancel)
	menu.action_chosen.connect(selection._on_action_chosen)

	_opp_model = OpponentModel.new()
	_set_window()                                  # center the window on the player
	menu.set_state(player, player, false, player.spell_ids(), [], false)

func _spawn_mobs() -> void:
	for d in DEFAULT_MOBS:
		var tile: Vector2i = omap.nearest_open(d["tile"])
		var def: Dictionary = MOB_TYPES[d["type"]]
		var c := Combatant.new("B", tile, Config.Facing.SOUTH)
		c.equip(def["gear"])
		var uv := UnitView.new()
		board.add_child(uv)
		uv.init_state(c)
		uv.unit_id = def["name"]
		uv.base_color = def["tint"]
		uv.modulate = def["tint"]
		uv.scale = Vector2(def["scale"], def["scale"])
		var ai := AIOpponent.new(_mob_diff(d["type"]), get_tree())
		mobs.append({"combatant": c, "uv": uv, "ai": ai, "type": d["type"]})

# ── roam (real-time WASD) until a monster is in view, then the loop flips to COMBAT ─
func _process(delta: float) -> void:
	if _phase == Phase.ROAM:
		_roam(delta)

func _roam(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	if _roam_cd > 0.0:
		_roam_cd -= delta
		return
	var dir := _input_dir()
	if dir == Vector2i.ZERO:
		return
	_face(player, player_uv, dir)
	var target := player.pos + dir
	if grid.is_blocked(target):
		_roam_cd = 0.12
		return
	player.pos = target
	player_uv.tween_to(target)
	_set_window()                      # shift the world so you stay centered
	_roam_cd = ViewConfig.MOVE_DUR
	if not _engaged().is_empty():
		_phase = Phase.COMBAT
		_combat_loop()                 # async; flips back to ROAM when the area is clear

# ── combat: turn after turn while any mob is in your 12x12 ───────────────────
func _combat_loop() -> void:
	while true:
		var engaged := _engaged()
		if engaged.is_empty():
			break
		await _combat_turn(engaged)
		if player.is_dead():
			_die()
			return
	_phase = Phase.ROAM

func _combat_turn(engaged: Array) -> void:
	turn_num += 1
	var nearest: Dictionary = engaged[0]
	play.units["B"] = nearest["uv"]    # animate the nearest foe as B

	# Your action -- the normal menu/targeting flow (begin_turn activates the menu).
	selection.begin_turn(player, nearest["combatant"])
	var player_seq: Array = await selection.player_sequence_ready
	menu.set_state(player, nearest["combatant"], false, player.spell_ids(), [], false, true)
	board.clear_highlights()

	# Each mob plans via its own AI, handed a grid with the OTHER mobs as walls.
	var mob_cs: Array = []
	for e in engaged:
		mob_cs.append(e["combatant"])
	var mob_seqs: Array = []
	for i in engaged.size():
		var g := StoryCombat._grid_blocking_others(grid, mob_cs, {}, i)
		var seq: Array = await engaged[i]["ai"].opponent_sequence(engaged[i]["combatant"], player, g, turn_num, player_seq, _opp_model)
		mob_seqs.append(seq)

	var res := StoryCombat.resolve_turn(grid, player, mob_cs, player_seq, mob_seqs)

	# Animate the nearest fight fully via your EventPlayer.
	await play.play(res["primary_events"], res["player"], res["mobs"][0])
	# Light pass for the other mobs: move, swing, and land their hit on you.
	for ex in res["extra"]:
		var e: Dictionary = engaged[ex["index"]]
		var m_after: Combatant = ex["mob"]
		e["uv"].tween_to(m_after.pos)
		if ex["dmg"] > 0:
			e["uv"].play_anim("attack", Vector2(player.pos - m_after.pos))
			player_uv.flash(ViewConfig.FLASH_HIT)
			board.spawn_number(player_uv.position, "-%d" % int(ex["dmg"]), ViewConfig.COL_DMG)
		e["uv"].set_display_hp(m_after.hp)

	# Commit state (resources persist across turns and back into roaming).
	player = res["player"]
	player_uv.set_display_hp(player.hp)
	for i in engaged.size():
		engaged[i]["combatant"] = res["mobs"][i]
	_opp_model.observe(player_seq)
	_clear_dead()
	combat_log.add_turn(turn_num, res["primary_events"])
	_set_window()                      # recenter on the player; refresh mob visibility

func _die() -> void:
	PlayerProfile.spend_gold(mini(DEATH_GOLD_PENALTY, PlayerProfile.gold()))
	get_tree().change_scene_to_file(MENU_SCENE)

# ── windowing ────────────────────────────────────────────────────────────────
# The visible 12x12 starts here (player centered, clamped at the world edges).
func _window_origin() -> Vector2i:
	var lim := OverworldMap.SIZE - VIEW_TILES
	return Vector2i(
		clampi(player.pos.x - VIEW_RADIUS, 0, lim),
		clampi(player.pos.y - VIEW_RADIUS, 0, lim))

func _set_window() -> void:
	var o := _window_origin()
	board.set_window(o)
	player_uv.visible = true
	for m in mobs:
		m["uv"].visible = _in_window(m["combatant"].pos, o)

func _in_window(p: Vector2i, o: Vector2i) -> bool:
	return p.x >= o.x and p.x < o.x + VIEW_TILES and p.y >= o.y and p.y < o.y + VIEW_TILES

# ── helpers ──────────────────────────────────────────────────────────────────
# Engaged == visible in your window: exactly "fight what enters your view".
func _engaged() -> Array:
	var o := _window_origin()
	var out: Array = []
	for m in mobs:
		if _in_window(m["combatant"].pos, o):
			out.append(m)
	out.sort_custom(func(x, y):
		return _cheb(x["combatant"].pos) < _cheb(y["combatant"].pos))
	return out

func _cheb(p: Vector2i) -> int:
	return maxi(abs(p.x - player.pos.x), abs(p.y - player.pos.y))

func _clear_dead() -> void:
	var keep: Array = []
	for m in mobs:
		if m["combatant"].is_dead():
			m["uv"].queue_free()
		else:
			keep.append(m)
	mobs = keep

func _input_dir() -> Vector2i:
	if Input.is_action_pressed("ui_up")    or Input.is_key_pressed(KEY_W): return Vector2i(0, -1)
	if Input.is_action_pressed("ui_down")  or Input.is_key_pressed(KEY_S): return Vector2i(0, 1)
	if Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A): return Vector2i(-1, 0)
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): return Vector2i(1, 0)
	return Vector2i.ZERO

func _face(c: Combatant, uv: UnitView, dir: Vector2i) -> void:
	var f := _facing_for(dir)
	if f != c.facing:
		c.facing = f
		uv.set_facing(f)

func _facing_for(dir: Vector2i) -> int:
	for fc in Config.FACING_VEC:
		if Config.FACING_VEC[fc] == dir:
			return fc
	return Config.Facing.SOUTH

func _mob_diff(type: String) -> int:
	match type:
		"grunt": return AI.Difficulty.EASY
		"brute": return AI.Difficulty.CHALLENGING
		"boss":  return AI.Difficulty.EXTREME
	return AI.Difficulty.CHALLENGING
