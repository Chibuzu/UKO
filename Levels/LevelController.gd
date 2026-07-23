# LevelController.gd
# The LEVELS runner (Fra spec, round 20): ten hand-authored rooms that teach the
# duel piece by piece, with the shop's gear as the prize ladder.
#
# ARCHITECTURE: extends StoryController and keeps its hardest-won machinery --
# the multi-mob combat turn, the pairwise resolves, earned facing, loot, the
# gather minigames, the boss-pair wiring -- ALL inherited untouched. This class
# only replaces the WORLD: _ready builds a small fixed room from LevelBook ASCII
# instead of the 60x60 overworld, and a handful of overrides retire the story's
# systems that make no sense in a room (day/night wall reshuffles, story saves,
# NPCs, the cavern door) and add the level frame (objective, victory, retry).
#
# ROUND 25 (Fra): levels play on THE duel board -- BoardView, the same 8x8
# arena, art and layout as PLAY mode. No camera, no window: the board edge is
# the boundary and everyone is always on screen.
class_name LevelController
extends StoryController

const LEVELS_SCENE := "res://Levels.tscn"

var level_num: int = 1
var _gems_got := 0
var _mushrooms_got := 0
var _completed := false
var _fallen := false
var _target := Vector2i(-1, -1)     # 'T' glyph: the reach-objective tile
var _reached := false
var foe_hud: ResourceHUD = null     # ROUND 24: mob resources, top-right over the log
var _inspect: Dictionary = {}       # the mob ENTRY the foe HUD is watching (click to switch)

# Foe-less tutorial turns resolve against an invisible dummy parked OFF-BOARD
# (an engine-legal state -- blink transit uses the same trick). Nobody meets it,
# nothing draws it, no board tile is spent on it.
const DUMMY_POCKET := Vector2i(-4, -4)

# Per-level starting facing ("facing" field; default south).
const FACINGS := {"north": Config.Facing.NORTH, "south": Config.Facing.SOUTH,
	"east": Config.Facing.EAST, "west": Config.Facing.WEST}

# ── the world, rebuilt from LevelBook ASCII (replaces StoryController._ready) ──
func _ready() -> void:
	level_num = clampi(LevelBook.current, 1, LevelBook.count())
	var def: Dictionary = LevelBook.level(level_num)
	var rows: Array = def["map"]

	# ROUND 25: maps are PURE 8x8 board coordinates (no wall ring -- the arena
	# edge is the wall, exactly like PLAY). '#' = an interior blocker drawn with
	# the duel's own blocker art. omap stays an EMPTY shell: inherited helpers
	# read its (empty) rest/gem sets; nothing ever walks the overworld here.
	omap = OverworldMap.new()
	grid = WorldGrid.new()
	grid.build_arena(Grid.SIZE, Rect2i(0, 0, Grid.SIZE, Grid.SIZE))
	var spawn := Vector2i.ZERO
	var mob_spawns: Array = []     # [{type, tile}] in map order; serpents pair up
	for my in rows.size():
		var line := String(rows[my])
		for mx in line.length():
			var t := Vector2i(mx, my)
			match line[mx]:
				"#":
					grid.blocked[t.y][t.x] = true
					grid.base_blocked[t.y][t.x] = true
				"@": spawn = t
				"T": _target = t
				"b": mob_spawns.append({"type": "bat", "tile": t})
				"s": mob_spawns.append({"type": "slime", "tile": t})
				"x": mob_spawns.append({"type": "serpent", "tile": t})
				"G":
					omap.gem_set[t] = true
					omap.gem_tiles.append(t)
				"m":
					omap.mushroom_set[t] = true
					omap.mushroom_tiles.append(t)
				"R":
					omap.rest_set[t] = true
					omap.rest_tiles.append(t)

	# THE duel board, verbatim: same art, same origin, same scale as PLAY.
	board = BoardView.new()
	add_child(board)
	board.setup(grid)

	player = Combatant.new("A", spawn, int(FACINGS.get(String(def.get("facing", "south")), Config.Facing.SOUTH)))
	player.hp = clampi(int(def.get("player_hp", Config.MAX_HP)), 1, Config.MAX_HP)
	player.equip(PlayerProfile.loadout())          # earned gear works the moment you earn it
	if not LevelProgress.grenade_unlocked():
		# The ladder's grenade gate: mark it already spent and the ENGINE itself
		# refuses the throw (once_per_match bookkeeping) -- no new UI, no new rule.
		player.spent_once["grenade"] = true
	player_uv = UnitView.new()
	board.add_child(player_uv)
	player_uv.init_state(player)
	player_uv.z_index = 1

	res_hud = ResourceHUD.new()
	add_child(res_hud)
	res_hud.position = Vector2(ViewConfig.PANEL_LEFT.position.x + 40, ViewConfig.PANEL_LEFT.position.y + 28)
	res_hud.bind(player)

	# Mobs from the map glyphs. Serpents get the BOSS pair wiring (labels, seat
	# picks, bruiser/flanker roles) -- level 10 IS the cavern fight, relocated.
	var serpent_idx := 0
	for ms in mob_spawns:
		var e := _add_mob(String(ms["type"]), Vector2i(ms["tile"]))
		# ROUND 24 (Fra): every level mob shows its facing bar and SPAWNS FACING
		# the player -- what you see at turn one is what will punish you.
		# ROUND 28: aim is written FIRST (its setter re-poses the art instantly),
		# then the mechanical facing follows -- bar, sprite and rules agree at
		# frame one.
		e["uv"].show_facing = true
		var fd := Resolver.dir_from(e["combatant"].pos, spawn)
		if fd != Vector2i.ZERO:
			e["uv"].aim = Vector2(fd)
			_face(e["combatant"], e["uv"], fd)
			e["uv"].set_facing(e["combatant"].facing)   # unconditional refresh
		if String(ms["type"]) == "serpent":
			e["boss"] = true
			e["label"] = "Serpent %s" % ["A", "B"][mini(serpent_idx, 1)]
			e["kind"].seat_pick = serpent_idx
			e["kind"].role = CharacterTwin.Role.BRUISER if serpent_idx == 0 else CharacterTwin.Role.FLANKER
			serpent_idx += 1
	_boss_awake = true                 # no door to cross: a boss room is awake from turn one
	mob_energy_refill = false          # ROUND 24 (Fra): mobs pay costs + pulse every 6, like you

	fx = Fx.new()
	board.add_child(fx)
	menu = ActionMenu.new()
	add_child(menu)
	combat_log = CombatLog.new()
	add_child(combat_log)
	# ROUND 24 (Fra): mobs show HP/MP/EP like a player, top right OVER the log
	# (the log slides down to make room). Click any mob to inspect it.
	if not mobs.is_empty():
		combat_log.position = ViewConfig.LOG_ORIGIN + Vector2(0, 84)
		foe_hud = ResourceHUD.new()
		add_child(foe_hud)
		foe_hud.position = Vector2(ViewConfig.PANEL_RIGHT.position.x + 40, ViewConfig.PANEL_RIGHT.position.y + 28)
		_inspect = mobs[0]
		foe_hud.bind(_inspect["combatant"])
	play = EventPlayer.new()
	add_child(play)
	play.setup(board, fx, player_uv, player_uv)
	selection = SelectionController.new()
	add_child(selection)
	selection.setup(grid, board, menu)
	board.tile_clicked.connect(selection._on_tile_clicked)
	board.selection_cancelled.connect(selection._on_cancel)
	board.tile_clicked.connect(_on_inspect_click)   # round 24: click a mob -> its HUD
	menu.action_chosen.connect(_on_menu_action)
	# Tutor dial: a level may offer only SOME buttons. Duels never touch it.
	menu.allowed = Array(def.get("actions", []))
	if _target != Vector2i(-1, -1):
		var marker := Combatant.new("N", _target, Config.Facing.SOUTH)   # position carrier only
		var tv := UnitView.new()
		board.add_child(tv)
		tv.disc_only = true
		tv.disc_color = ViewConfig.COL_GOLD
		tv.prop = true
		tv.init_state(marker)
		tv.unit_id = "REACH"

	_init_window()
	menu.set_state(player, player, false, player.spell_ids(), [], false)

	var pause_layer := CanvasLayer.new()
	pause_layer.layer = 20
	add_child(pause_layer)
	pause_menu = StoryPauseMenu.new()
	pause_layer.add_child(pause_menu)
	pause_menu.visible = false
	pause_menu.resume.connect(_close_pause)
	pause_menu.save.connect(_pause_save)
	pause_menu.exit_to_menu.connect(_exit_to_menu)

	_gather_layer = CanvasLayer.new()
	_gather_layer.layer = 22
	add_child(_gather_layer)

	# The intro card: name, lesson, objective, prize -- the log carries it so it
	# stays readable after the floating lines fade.
	combat_log.add_note("LEVEL %d -- %s" % [level_num, String(def["name"])], ViewConfig.COL_GOLD)
	combat_log.add_note(String(def["teach"]), ViewConfig.COL_TEXT)
	combat_log.add_note("Objective: %s" % LevelBook.objective_label(level_num), ViewConfig.COL_TEXT)
	combat_log.add_note("Reward: %s" % LevelBook.reward_label(level_num), ViewConfig.COL_GOLD)
	board.spawn_number(player_uv.position + Vector2(0, -24), String(def["name"]), ViewConfig.COL_GOLD)
	_refresh_rest_prompt()

	# A reach level with no monsters runs the TUTORIAL loop: the real planning
	# menu, the real resolver, real costs -- just nobody hitting back.
	if bool(LevelBook.level(level_num).get("objective", {}).get("reach", false)) and mobs.is_empty():
		_phase = Phase.COMBAT          # roam (free WASD walking) stays off: turns only
		_tutorial_loop()
	elif not mobs.is_empty():
		# ROUND 27 (Fra bug): combat starts INSTANTLY -- previously the first
		# roam tick gave every mob a free approach step before turn one (the
		# "bat starts adjacent" report). Mobs now fight from their authored
		# tiles, plans and all.
		_phase = Phase.COMBAT
		_combat_loop()

# Levels have no roaming and therefore no wander steps -- ever (round 27).
func _mob_roam(_delta: float) -> void:
	pass

# ── the foe-less turn loop (round 22): plan -> resolve -> check ─────────────
func _tutorial_loop() -> void:
	var def: Dictionary = LevelBook.level(level_num)
	var clock := int(def.get("objective", {}).get("clock", 0))
	var clock_left := clock
	if clock > 0:
		combat_log.add_note("CLOCK: %d actions." % clock_left, ViewConfig.COL_GOLD)
	var dummy := Combatant.new("B", DUMMY_POCKET, Config.Facing.SOUTH)
	dummy.equip([])
	# THE VANISHING-SPRITE BUG (Fra, round 25): EventPlayer's "B" slot still
	# pointed at the PLAYER'S sprite (the _ready default), so finishing a turn
	# snapped the player's own sprite onto the dummy's off-board tile. B now
	# owns an invisible stand-in that absorbs every dummy-side write.
	var dummy_uv := UnitView.new()
	board.add_child(dummy_uv)
	dummy_uv.init_state(dummy)
	dummy_uv.visible = false
	play.units["B"] = dummy_uv
	while not _completed and not _fallen:
		selection.begin_turn(player, dummy)
		var seq: Array = await selection.player_sequence_ready
		var r: Dictionary = Resolver.resolve(grid, player.clone(), dummy.clone(),
				seq, [{"id": "wait"}, {"id": "wait"}], 0)
		var a_events: Array = []
		for ev in r["events"]:
			if String(ev.get("owner", "")) in ["A", player.id]:
				a_events.append(ev)          # the dummy's waits never reach the screen
		await play.play(a_events, r["a"], r["b"])
		player = r["a"]
		dummy = r["b"]
		player_uv.set_display_hp(player.hp)
		res_hud.refresh(player)
		turn_num += 1
		combat_log.add_turn(turn_num, a_events)
		if clock > 0:
			clock_left -= seq.size()
			combat_log.add_note("CLOCK: %d left." % maxi(0, clock_left), ViewConfig.COL_GOLD)
			board.spawn_number(player_uv.position + Vector2(0, -20), "%d" % maxi(0, clock_left),
				ViewConfig.COL_GOLD if clock_left > 4 else ViewConfig.COL_DMG)
		if player.pos == _target:
			# ROUND 27: CONFIRM needs both actions again, so a turn may ARRIVE on
			# slot 1 and spend slot 2 standing on the mark (a pivot, a fizzle).
			# The walk's rule judges the energy AT ARRIVAL: if anything executed
			# AFTER the arriving step, arrival energy was > 0 by construction.
			var arrive_seen := false
			var exec_after := false
			for ev in a_events:
				var ty := String(ev.get("type", ""))
				if ty == ResolverEvents.MOVE and Vector2i(ev.get("to", Vector2i(-9, -9))) == _target:
					arrive_seen = true
					exec_after = false
				elif arrive_seen and (ty == ResolverEvents.MOVE or ty == ResolverEvents.PIVOT):
					exec_after = true
			if player.energy > 0 or exec_after:
				_reached = true
				_check_complete()            # -> victory banner + reward + menu
			else:
				_fail_tutorial("Arrived EMPTY -- reach it with energy to spare.")
		elif clock > 0 and clock_left <= 0:
			_fail_tutorial("THE CLOCK HIT ZERO -- fewer detours, sharper breaths.")
		elif player.energy < Config.COST_MOVE_FWD and not Array(def.get("actions", [])).has("wait"):
			# No WAIT button and no affordable move = truly stuck (L1). With WAIT
			# offered, the engine's +5 always recovers you -- the clock judges.
			_fail_tutorial("OUT OF ENERGY -- find a cheaper walk.")

func _fail_tutorial(msg: String) -> void:
	if _fallen or _completed:
		return
	_fallen = true
	board.spawn_number(player_uv.position, msg, ViewConfig.COL_DMG)
	combat_log.add_note(msg, ViewConfig.COL_DMG)
	await get_tree().create_timer(1.8).timeout
	get_tree().change_scene_to_file(LEVELS_SCENE)   # same level, fresh tank

# ── the play board has no camera: everyone is always visible ────────────────
func _init_window() -> void:
	_apply_window()

func _follow_window() -> void:
	_apply_window()

func _apply_window() -> void:
	if player_uv != null:
		player_uv.visible = true
	for m in mobs:
		m["uv"].visible = true

func _mob_visible(_e: Dictionary) -> bool:
	return true

# ── story systems that a room retires ───────────────────────────────────────
func _nightfall() -> void:
	pass                          # no day/night: walls never reshuffle mid-level

func _dawn() -> void:
	pass

func _seal_cavern(_closed: bool) -> void:
	pass                          # rooms have no cavern door; the ring IS the cage

func _spawn_npcs() -> void:
	pass

func _pause_save() -> void:
	# Levels save themselves on victory (LevelProgress); the story SAVE button
	# would write a STORY save from level state -- refuse, kindly.
	board.spawn_number(player_uv.position, "Levels save automatically", ViewConfig.COL_TEXT_OFF)

# ── the foe HUD (round 24) ──────────────────────────────────────────────────
func _on_inspect_click(tile: Vector2i) -> void:
	for m in mobs:
		if m["combatant"].pos == tile:
			_inspect = m
			_refresh_foe_hud()
			return

func _refresh_foe_hud() -> void:
	if foe_hud == null:
		return
	if mobs.is_empty():
		foe_hud.visible = false
		return
	if _inspect.is_empty() or not mobs.has(_inspect):
		_inspect = mobs[0]             # the watched mob died -> watch the nearest survivor
	foe_hud.visible = true
	foe_hud.refresh(_inspect["combatant"])

# ── engagement (round 24): no aggro radius -- every mob fights from turn one ──
func _engaged() -> Array:
	var out: Array = []
	for m in mobs:
		out.append(m)
	out.sort_custom(func(x, y):
		return _cheb(x["combatant"].pos) < _cheb(y["combatant"].pos))
	return out

# ── objective / victory / defeat ────────────────────────────────────────────
func _clear_dead() -> void:
	super._clear_dead()
	_refresh_foe_hud()
	_check_complete()

func _on_gather_done(quality: float, kind: String, tile: Vector2i, mg: Control) -> void:
	super._on_gather_done(quality, kind, tile, mg)
	# Success removed the node from the map -- that's the tally signal.
	if kind == "gemstone" and not omap.is_gem(tile):
		_gems_got += 1
	elif kind == "mushroom" and not omap.is_mushroom(tile):
		_mushrooms_got += 1
	_check_complete()

func _objective_met() -> bool:
	var o: Dictionary = LevelBook.level(level_num).get("objective", {})
	if bool(o.get("reach", false)) and not _reached:
		return false
	if int(o.get("gems", 0)) > _gems_got:
		return false
	if int(o.get("mushrooms", 0)) > _mushrooms_got:
		return false
	if bool(o.get("kills", false)) and not mobs.is_empty():
		return false
	return true

func _check_complete() -> void:
	if _completed or _fallen or not _objective_met():
		return
	_completed = true
	_finish_level()

func _finish_level() -> void:
	var def: Dictionary = LevelBook.level(level_num)
	var r: Dictionary = def.get("reward", {})
	board.spawn_number(player_uv.position + Vector2(0, -30), "LEVEL CLEAR", ViewConfig.COL_GOLD)
	combat_log.add_note("LEVEL %d CLEAR" % level_num, ViewConfig.COL_GOLD)
	var yoff := -48.0
	if r.has("gear"):
		var gid := String(r["gear"])
		if not PlayerProfile.is_owned(gid):
			PlayerProfile.grant(gid)   # owned AND equipped: the next level already casts it
			board.spawn_number(player_uv.position + Vector2(0, yoff),
				"EARNED: %s" % String(GearBook.gear_def(gid).get("name", gid)), ViewConfig.COL_HEAL)
		else:
			PlayerProfile.add_gold(LevelBook.CONSOLATION_GOLD)   # gold buyers aren't shortchanged
			board.spawn_number(player_uv.position + Vector2(0, yoff),
				"+%d gold (already owned)" % LevelBook.CONSOLATION_GOLD, ViewConfig.COL_GOLD)
		yoff -= 16.0
	if r.has("grenade"):
		board.spawn_number(player_uv.position + Vector2(0, yoff), "THE GRENADE IS YOURS", ViewConfig.COL_HEAL)
		yoff -= 16.0                   # unlock itself = LevelProgress.grenade_unlocked() (beat 8)
	if int(r.get("gold", 0)) > 0:
		PlayerProfile.add_gold(int(r["gold"]))
		board.spawn_number(player_uv.position + Vector2(0, yoff), "+%d gold" % int(r["gold"]), ViewConfig.COL_GOLD)
	LevelProgress.mark_beaten(level_num)
	await get_tree().create_timer(2.4).timeout
	get_tree().change_scene_to_file(MENU_SCENE)

# Death: no gold penalty, no lost ladder -- the room resets and you go again.
func _die() -> void:
	if _fallen or _completed:
		return
	_fallen = true
	board.spawn_number(player_uv.position, "FALLEN -- again!", ViewConfig.COL_DMG)
	combat_log.add_note("Fallen. The room resets.", ViewConfig.COL_DMG)
	await get_tree().create_timer(1.6).timeout
	get_tree().change_scene_to_file(LEVELS_SCENE)   # LevelBook.current unchanged -> same level, fresh
