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
const VIEW_RADIUS := 6            # initial window is player.pos +/- 6 -> the visible 12x12
const EDGE := 3                   # deadzone: the window only scrolls when you get this close to its edge
const MENU_SCENE := "res://MainMenu.tscn"
const DEATH_GOLD_PENALTY := 25

# Procedural spawning. Mob look/stats/behavior live in MobBrain.PROFILES (single source);
# here we only decide HOW MANY and WHICH TYPES, then scatter them on open ground.
const MOB_COUNT := 28
const TYPE_WEIGHTS := [["bat", 50], ["slime", 38], ["serpent", 12]]

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
var mobs: Array = []              # [{combatant, uv, kind, type}]
var turn_num: int = 0
var _phase: int = Phase.ROAM
var _roam_cd: float = 0.0
var _seed: int = 0                    # world seed; regenerating from it restores the exact map
var _win: Vector2i = Vector2i.ZERO    # current top-left world tile of the visible window

func _ready() -> void:
	var save: Dictionary = StorySave.read() if StorySave.has_save() else {}
	var resuming := not save.is_empty()
	_seed = int(save.get("seed", randi())) if resuming else randi()

	omap = OverworldMap.new()
	omap.generate(_seed)                           # same seed -> same map, so a save restores exactly
	grid = WorldGrid.new()
	grid.build(omap)

	# Board, menu, log: DIRECT children at their default screen positions -- identical
	# layout to GameController/PLAY. The board just renders a moving window of the world.
	board = WorldBoard.new()
	add_child(board)
	board.setup_world(grid)

	var start: Vector2i
	if resuming:
		start = _v2i(save["player"]["pos"])
	else:
		start = omap.nearest_open(Vector2i(OverworldMap.SIZE / 2, OverworldMap.SIZE / 2))
	player = Combatant.new("A", start, Config.Facing.SOUTH)
	player.equip(PlayerProfile.loadout())          # you carry your real equipped gear
	if resuming:
		_restore_player(save["player"])
	player_uv = UnitView.new()
	board.add_child(player_uv)
	player_uv.init_state(player)
	player_uv.z_index = 1

	if resuming:
		_spawn_from_save(save.get("mobs", []))
		turn_num = int(save.get("turn", 0))
	else:
		_spawn_mobs_procedural()

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

	_init_window()                                 # center the window on the player to start
	menu.set_state(player, player, false, player.spell_ids(), [], false)

# Build one mob of `type` at `tile` and register it. Shared by procedural spawn and
# save-restore, so both paths stay in lockstep.
func _add_mob(type: String, tile: Vector2i) -> Dictionary:
	var prof: Dictionary = MobBrain.PROFILES[type]
	var c := Combatant.new("B", tile, Config.Facing.SOUTH)
	c.equip([])                                    # NO gear -> no spells, ever
	c.hp = int(prof.get("hp", 100))
	var uv := UnitView.new()
	board.add_child(uv)
	uv.disc_only = true                            # mobs are colored balls, not your fighter
	uv.disc_color = prof.get("tint", Color.WHITE)
	uv.init_state(c)
	uv.unit_id = String(prof.get("name", "?"))
	var sc: float = float(prof.get("scale", 1.0))
	uv.scale = Vector2(sc, sc)
	var entry := {"combatant": c, "uv": uv, "kind": MobBrain.make_kind(type), "type": type}
	mobs.append(entry)
	return entry

# New game: scatter mobs on open tiles outside the spawn village, types by weight.
func _spawn_mobs_procedural() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed ^ 0x9E3779B9                  # decorrelate placement from map-gen
	var taken: Dictionary = {}
	var placed := 0
	var guard := 0
	while placed < MOB_COUNT and guard < MOB_COUNT * 40:
		guard += 1
		var t := Vector2i(rng.randi_range(1, OverworldMap.SIZE - 2), rng.randi_range(1, OverworldMap.SIZE - 2))
		if omap.is_solid(t) or _in_village(t) or taken.has(t):
			continue
		taken[t] = true
		_add_mob(_roll_type(rng), t)
		placed += 1

# Resume: rebuild each saved mob at its exact type/tile/state.
func _spawn_from_save(mob_data: Array) -> void:
	for md in mob_data:
		var e := _add_mob(String(md["type"]), _v2i(md["pos"]))
		var c: Combatant = e["combatant"]
		c.facing = int(md.get("facing", Config.Facing.SOUTH))
		c.hp = int(md.get("hp", c.hp))
		c.mp = int(md.get("mp", c.mp))
		c.energy = int(md.get("energy", c.energy))
		c.statuses = _int_dict(md.get("statuses", {}))
		e["uv"].init_state(c)
		e["uv"].set_facing(c.facing)

# ── roam (real-time WASD) until a monster is in view, then the loop flips to COMBAT ─
func _process(delta: float) -> void:
	if _phase == Phase.ROAM:
		_roam(delta)

# Manual save (F5) while roaming, with a floating confirmation.
func _input(event: InputEvent) -> void:
	if _phase == Phase.ROAM and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		_save_game()

func _roam(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_save_game()                   # leaving saves your run so STORY resumes here
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
	_follow_window()                   # scroll only near the window edge -> you visibly walk
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
	player.rest_ready = true           # story: rest is always available -- it heals you mid-fight

	# Your action -- the normal menu/targeting flow (begin_turn activates the menu).
	selection.begin_turn(player, nearest["combatant"])
	var player_seq: Array = await selection.player_sequence_ready
	menu.set_state(player, nearest["combatant"], false, player.spell_ids(), [], false, true)
	board.clear_highlights()

	# Each mob plans a MOVE-ONLY sequence via its behavior, handed a grid with the others as walls.
	var mob_cs: Array = []
	var mob_kinds: Array = []
	for e in engaged:
		mob_cs.append(e["combatant"])
		mob_kinds.append(e["kind"])
	var mob_seqs: Array = []
	for i in engaged.size():
		var g := StoryCombat._grid_blocking_others(grid, mob_cs, {}, i)
		mob_seqs.append(engaged[i]["kind"].plan(engaged[i]["combatant"], player, g))

	var res := StoryCombat.resolve_turn(grid, player, mob_cs, player_seq, mob_seqs, mob_kinds)
	var dmg: Array = res["dmg_by_mob"]
	var p_end: Vector2i = res["player"].pos

	# Your action + the nearest mob's movement animate via the engine; mob STRIKES are custom
	# (not resolver events), so every mob's hit is shown manually.
	await play.play(res["primary_events"], res["player"], res["mobs"][0])
	for i in engaged.size():
		var m_after: Combatant = res["mobs"][i]
		if i > 0:
			engaged[i]["uv"].tween_to(m_after.pos)   # nearest already moved via play.play
		if int(dmg[i]) > 0:
			engaged[i]["uv"].play_anim("attack", Vector2(p_end - m_after.pos))
			player_uv.flash(ViewConfig.FLASH_HIT)
			board.spawn_number(player_uv.position, "-%d" % int(dmg[i]), ViewConfig.COL_DMG)
		engaged[i]["uv"].set_display_hp(m_after.hp)

	# Commit state (resources persist), run per-mob post-turn hooks (splits etc.), clear/loot dead.
	player = res["player"]
	player_uv.set_display_hp(player.hp)
	for i in engaged.size():
		engaged[i]["combatant"] = res["mobs"][i]
	for e in engaged:
		e["kind"].on_committed(e, player, self)
	_clear_dead()
	combat_log.add_turn(turn_num, res["primary_events"])
	_follow_window()                   # keep you in view; refresh mob visibility

func _die() -> void:
	PlayerProfile.spend_gold(mini(DEATH_GOLD_PENALTY, PlayerProfile.gold()))
	# Death is a setback, not a wipe: respawn at the village at full resources; the world
	# and any mobs you cleared persist. The resume point becomes that safe restart.
	player.pos = omap.nearest_open(Vector2i(OverworldMap.SIZE / 2, OverworldMap.SIZE / 2))
	player.facing = Config.Facing.SOUTH
	player.hp = Config.MAX_HP
	player.mp = Config.MAX_MP
	player.energy = Config.MAX_ENERGY
	player.statuses = {}
	StorySave.write(_gather_save())
	get_tree().change_scene_to_file(MENU_SCENE)

# ── windowing (edge-scroll follow, not constant re-centering) ─────────────────
# Start centered on the player.
func _init_window() -> void:
	var lim := OverworldMap.SIZE - VIEW_TILES
	_win = Vector2i(
		clampi(player.pos.x - VIEW_RADIUS, 0, lim),
		clampi(player.pos.y - VIEW_RADIUS, 0, lim))
	_apply_window()

# Keep the player inside a centered deadzone; the window slides ONLY when they push
# within EDGE of a border. So on open ground you watch yourself walk across the board,
# and the world scrolls only at the margins -- the standard tile-RPG camera feel.
func _follow_window() -> void:
	var lim := OverworldMap.SIZE - VIEW_TILES
	_win = Vector2i(
		_axis(player.pos.x, _win.x, lim),
		_axis(player.pos.y, _win.y, lim))
	_apply_window()

func _axis(p: int, cur: int, lim: int) -> int:
	var lo := cur + EDGE
	var hi := cur + VIEW_TILES - 1 - EDGE
	var o := cur
	if p < lo:
		o = cur - (lo - p)
	elif p > hi:
		o = cur + (p - hi)
	return clampi(o, 0, lim)

func _apply_window() -> void:
	board.set_window(_win)
	player_uv.visible = true
	for m in mobs:
		m["uv"].visible = _in_window(m["combatant"].pos, _win)

func _in_window(p: Vector2i, o: Vector2i) -> bool:
	return p.x >= o.x and p.x < o.x + VIEW_TILES and p.y >= o.y and p.y < o.y + VIEW_TILES

# ── helpers ──────────────────────────────────────────────────────────────────
# Engaged == visible in your window: exactly "fight what enters your view".
func _engaged() -> Array:
	var out: Array = []
	for m in mobs:
		if _in_window(m["combatant"].pos, _win):
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
			_grant_loot(m)
			m["uv"].queue_free()
		else:
			keep.append(m)
	mobs = keep

# Roll a dead mob's loot into the inventory, with a floating pickup label per item.
func _grant_loot(m: Dictionary) -> void:
	var pos: Vector2 = m["uv"].position
	var yoff := 0.0
	for d in m["kind"].roll_loot():
		var item := String(d["item"])
		PlayerInventory.add(item, int(d["count"]))
		board.spawn_number(pos + Vector2(0.0, yoff), "+" + ItemBook.item_name(item), ItemBook.item_color(item))
		yoff -= 14.0

# Slime split: a same-resource copy on a free tile next to the player, joining the fight.
# Called from SlimeKind.on_committed via the ctx (this controller).
func spawn_split(parent: Dictionary, player_ref: Combatant) -> void:
	var tile := _free_adjacent(player_ref.pos)
	if tile == Vector2i(-1, -1):
		return                                     # nowhere free -> skip the split this time
	var pc: Combatant = parent["combatant"]
	var e := _add_mob(String(parent["type"]), tile)
	var c: Combatant = e["combatant"]
	c.hp = pc.hp                                   # same resources as the parent at split time
	c.mp = pc.mp
	c.energy = pc.energy
	e["no_split"] = true                           # the copy can't split again -> no runaway
	e["uv"].set_display_hp(c.hp)
	_apply_window()                                # reveal it if it's inside the view

func _free_adjacent(p: Vector2i) -> Vector2i:
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
			Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var t := p + d
		if not grid.is_blocked(t) and not _occupied(t):
			return t
	return Vector2i(-1, -1)

func _occupied(t: Vector2i) -> bool:
	if player.pos == t:
		return true
	for m in mobs:
		if m["combatant"].pos == t:
			return true
	return false

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

# ── save / restore ────────────────────────────────────────────────────────────
func _save_game() -> void:
	StorySave.write(_gather_save())
	if is_instance_valid(player_uv):
		board.spawn_number(player_uv.position, "Saved", ViewConfig.COL_A)

func _gather_save() -> Dictionary:
	var mob_data: Array = []
	for m in mobs:
		var c: Combatant = m["combatant"]
		mob_data.append({
			"type": m["type"],
			"pos": [c.pos.x, c.pos.y],
			"facing": c.facing,
			"hp": c.hp, "mp": c.mp, "energy": c.energy,
			"statuses": c.statuses,
		})
	return {
		"version": 1,
		"seed": _seed,
		"turn": turn_num,
		"player": {
			"pos": [player.pos.x, player.pos.y],
			"facing": player.facing,
			"hp": player.hp, "mp": player.mp, "energy": player.energy,
			"statuses": player.statuses,
		},
		"mobs": mob_data,
	}

func _restore_player(pd: Dictionary) -> void:
	player.facing = int(pd.get("facing", Config.Facing.SOUTH))
	player.hp = int(pd.get("hp", player.hp))
	player.mp = int(pd.get("mp", player.mp))
	player.energy = int(pd.get("energy", player.energy))
	player.statuses = _int_dict(pd.get("statuses", {}))

# ── procedural helpers ─────────────────────────────────────────────────────────
func _in_village(t: Vector2i) -> bool:
	var c := OverworldMap.SIZE / 2
	return absi(t.x - c) <= VIEW_RADIUS and absi(t.y - c) <= VIEW_RADIUS

func _roll_type(rng: RandomNumberGenerator) -> String:
	var total := 0
	for w in TYPE_WEIGHTS:
		total += int(w[1])
	var r := rng.randi_range(1, total)
	for w in TYPE_WEIGHTS:
		r -= int(w[1])
		if r <= 0:
			return String(w[0])
	return "bat"

# JSON numbers come back as floats -> coerce.
func _v2i(arr: Array) -> Vector2i:
	return Vector2i(int(arr[0]), int(arr[1]))

func _int_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[k] = int(d[k])
	return out
