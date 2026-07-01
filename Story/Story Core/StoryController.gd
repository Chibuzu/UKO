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
const MOB_COUNT := 60
const TYPE_WEIGHTS := [["bat", 50], ["slime", 38], ["serpent", 12]]

# Mobs wander the world while you roam. They step on this cadence (slower than you, so
# you can outrun them), beeline toward you within MOB_AGGRO tiles, else drift randomly.
const MOB_ROAM_CD := 0.55
const MOB_AGGRO := 9

# Passive recovery: every REGEN_EVERY actions YOU take (roam steps + combat actions), only
# ENERGY comes back -- moving never heals. HP/MP are recovered by resting or a sanctuary tile.
const REGEN_EVERY := 6
const REGEN_EP := 10
const REST_SAFE := 5             # a sanctuary tile only rests you if no mob is within this many tiles

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
var pause_menu: StoryPauseMenu        # ESC overlay (gear / inventory / exit)
var quest_dialog: QuestDialog         # NPC quest overlay (accept / turn in)
var npcs: Array = []                  # [{id, uv, tile}] -- village quest-givers (visual discs)
var _quests: Array = []               # live QuestKind objects for currently-active quests
var _talk_npc: String = ""            # id of the NPC whose dialog is open (for re-refresh)
var _paused: bool = false
var _mob_cd: float = 0.0              # countdown to the next world-wander step for all mobs
var _actions: int = 0                 # your actions since the last passive-regen tick

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
	board.rest_set = omap.rest_set                 # golden sanctuary tiles drawn on the board
	if resuming and save.has("gems"):
		omap.set_gems(save["gems"])                # gathered gemstone nodes stay gone across a save
	board.gem_set = omap.gem_set                   # purple gemstone nodes drawn on the board

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
	menu.action_chosen.connect(_on_menu_action)

	_init_window()                                 # center the window on the player to start
	menu.set_state(player, player, false, player.spell_ids(), [], false)

	# Pause overlay on its own CanvasLayer so it always draws above the board/menu/log.
	var pause_layer := CanvasLayer.new()
	pause_layer.layer = 20
	add_child(pause_layer)
	pause_menu = StoryPauseMenu.new()
	pause_layer.add_child(pause_menu)
	pause_menu.visible = false
	pause_menu.resume.connect(_close_pause)
	pause_menu.save.connect(_pause_save)
	pause_menu.exit_to_menu.connect(_exit_to_menu)

	_spawn_npcs()                                  # village quest-givers (colored discs)
	_load_quests()                                 # rebuild live quest objects from PlayerQuests

	# Quest dialog on its own CanvasLayer, above the board, like the pause overlay.
	var dlg_layer := CanvasLayer.new()
	dlg_layer.layer = 21
	add_child(dlg_layer)
	quest_dialog = QuestDialog.new()
	dlg_layer.add_child(quest_dialog)
	quest_dialog.visible = false
	quest_dialog.quest_action.connect(_on_quest_action)
	quest_dialog.closed.connect(_close_dialog)

	_refresh_rest_prompt()                         # you may start on the village sanctuary tile

# Build one mob of `type` at `tile` and register it. Shared by procedural spawn and
# save-restore, so both paths stay in lockstep.
func _add_mob(type: String, tile: Vector2i) -> Dictionary:
	var prof: Dictionary = MobBrain.PROFILES[type]
	var c := Combatant.new("B", tile, Config.Facing.SOUTH)
	c.equip([])                                    # NO gear -> no spells, ever
	c.hp = int(prof.get("hp", 100))
	c.mp = 0                                        # mobs have only HP...
	c.energy = Config.MAX_ENERGY                    # ...and a full energy pool so moving never locks
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
		c.mp = 0                                       # HP-only mobs
		c.energy = Config.MAX_ENERGY
		c.statuses = _int_dict(md.get("statuses", {}))
		e["uv"].init_state(c)
		e["uv"].set_facing(c.facing)

# ── roam (real-time WASD) until a monster is in view, then the loop flips to COMBAT ─
func _process(delta: float) -> void:
	if menu != null:
		menu.player = player           # HUD always reflects your live resources, every frame
		menu.queue_redraw()
	if _phase == Phase.ROAM and not _paused:
		_roam(delta)
	if _phase == Phase.ROAM and not _paused:        # _roam may have flipped us into combat
		_mob_roam(delta)

# ESC opens the pause overlay; R rests on a golden sanctuary tile. Only while roaming and
# not paused. (Saving is deliberate now -- only the pause menu's SAVE button writes a save.)
func _unhandled_input(event: InputEvent) -> void:
	if _phase != Phase.ROAM or _paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_open_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_try_rest_tile()
			get_viewport().set_input_as_handled()

func _open_pause() -> void:
	_paused = true
	pause_menu.open()

func _close_pause() -> void:
	_paused = false
	pause_menu.close()

# Menu clicks route through here. In combat they drive the turn's selection; while roaming,
# only the contextual buttons are live: REST (golden tile), GATHER (gemstone), TALK (NPC).
func _on_menu_action(id: String) -> void:
	if _phase == Phase.ROAM:
		match id:
			"rest":   _try_rest_tile()
			"gather": _gather_nearby()
			"talk":   _talk_nearby()
		return
	selection._on_action_chosen(id)

# Light up the roam contextual buttons for whatever you're standing next to: REST on a safe
# sanctuary tile, GATHER by a gemstone, TALK by an NPC.
func _refresh_rest_prompt() -> void:
	var roam := _phase == Phase.ROAM and not _paused
	var ok := roam and omap.is_rest(player.pos) and not _mob_near(player.pos, REST_SAFE)
	menu.set_rest_prompt(ok)
	var extras: Array = []
	if roam:
		if _nearest_gem(1) != Vector2i(-1, -1):
			extras.append({"id": "gather", "label": "GATHER"})
		if _npc_near(1) != "":
			extras.append({"id": "talk", "label": "TALK"})
	menu.set_roam_extras(extras)

func _pause_save() -> void:
	StorySave.write(_gather_save())    # SAVE button: write, then let the overlay confirm
	pause_menu.note_saved()

func _exit_to_menu() -> void:
	# Save is deliberate now: leaving does NOT write. You resume from your last manual save.
	get_tree().change_scene_to_file(MENU_SCENE)

func _roam(delta: float) -> void:
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
	_bump_actions(1)                   # a step is an action -> feeds the every-6 regen
	_follow_window()                   # scroll only near the window edge -> you visibly walk
	if omap.is_rest(player.pos):
		_quest_event("rest_found", player.pos)   # discovering a shrine can advance a find quest
	_refresh_rest_prompt()             # light up REST if you just stepped onto a sanctuary tile
	_roam_cd = ViewConfig.MOVE_DUR
	if not _engaged().is_empty():
		_phase = Phase.COMBAT
		_combat_loop()                 # async; flips back to ROAM when the area is clear

# ── combat: turn after turn while any mob is in your 12x12 ───────────────────
func _combat_loop() -> void:
	menu.set_rest_prompt(false)        # combat owns the menu now
	while true:
		var engaged := _engaged()
		if engaged.is_empty():
			break
		await _combat_turn(engaged)
		if player.is_dead():
			_die()
			return
	_phase = Phase.ROAM
	_refresh_rest_prompt()             # back to roam: re-light REST if you ended on a sanctuary

func _combat_turn(engaged: Array) -> void:
	turn_num += 1
	var nearest: Dictionary = engaged[0]
	player.rest_ready = true           # story: rest is always available -- it heals you mid-fight

	# Your action -- the normal menu/targeting flow (begin_turn activates the menu).
	selection.begin_turn(player, nearest["combatant"])
	var player_seq: Array = await selection.player_sequence_ready

	# If you aimed a single-target ATTACK at a specific mob, resolve THAT mob first. The
	# primary (i==0) pairwise resolve is the one the log + animation come from, so without
	# this a swing at a farther mob would log the NEAREST mob's whiff ("A swing misses") even
	# though your real target was hit. Reorder so your target is primary.
	var atk_tile := _attack_tile(player_seq)
	if atk_tile != Vector2i(-1, -1):
		for i in engaged.size():
			if engaged[i]["combatant"].pos == atk_tile:
				if i != 0:
					var picked: Dictionary = engaged[i]
					engaged.remove_at(i)
					engaged.insert(0, picked)
				break

	play.units["B"] = engaged[0]["uv"]    # animate the mob you actually engaged as B
	menu.set_state(player, engaged[0]["combatant"], false, player.spell_ids(), [], false, true)
	board.clear_highlights()

	# Each mob plans a MOVE-ONLY sequence via its behavior, handed a grid with the others as walls.
	var mob_cs: Array = []
	var mob_kinds: Array = []
	for e in engaged:
		e["combatant"].energy = Config.MAX_ENERGY   # HP-only: refill so planning/moving never stalls
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
	if int(res.get("guard_refund", 0)) > 0:
		board.spawn_number(player_uv.position, "+%d EP" % int(res["guard_refund"]), ViewConfig.COL_HEAL)
	for i in engaged.size():
		engaged[i]["combatant"] = res["mobs"][i]
	for e in engaged:
		e["kind"].on_committed(e, player, self)
		_face_toward(e["combatant"], e["uv"], player.pos)   # end of turn: mobs turn to face you
	_bump_actions(player_seq.size())   # your actions this turn feed the every-6 regen
	_clear_dead()
	combat_log.add_turn(turn_num, res["primary_events"])
	_follow_window()                   # keep you in view; refresh mob visibility

func _die() -> void:
	# A setback: you forfeit some gold (that lives on your profile, so it persists) and return
	# to the menu. Story progress is NOT auto-written -- you resume from your last manual save.
	PlayerProfile.spend_gold(mini(DEATH_GOLD_PENALTY, PlayerProfile.gold()))
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
			_quest_event("kill", String(m["type"]))   # advance any active kill quests
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

# ── NPCs / quests / gemstones ──────────────────────────────────────────────────
# Spawn a colored disc per village NPC (visual only -- they don't fight or move).
func _spawn_npcs() -> void:
	for id in NPCBook.ids():
		var nd := NPCBook.npc_def(id)
		var tile := NPCBook.tile_of(id)
		var marker := Combatant.new("N", tile, Config.Facing.SOUTH)   # only for positioning
		var uv := UnitView.new()
		board.add_child(uv)
		uv.disc_only = true
		uv.disc_color = nd.get("color", Color.WHITE)
		uv.prop = true                             # no facing/HP bars -- villagers, not fighters
		uv.init_state(marker)
		uv.unit_id = String(nd.get("name", "?"))
		npcs.append({"id": id, "uv": uv, "tile": tile})

# Rebuild live QuestKind objects for every quest that's currently accepted (progress loaded).
func _load_quests() -> void:
	_quests = []
	for qid in PlayerQuests.active_ids():
		var q := QuestBook.make_quest(qid)
		q.load_state(PlayerQuests.state_of(qid))
		_quests.append(q)

func _live_quest(qid: String) -> QuestKind:
	for q in _quests:
		if q.id == qid:
			return q
	return null

# Feed a world event to every active quest, then persist any that advanced.
func _quest_event(kind: String, arg) -> void:
	for q in _quests:
		match kind:
			"kill":       q.on_kill(String(arg))
			"gather":     q.on_gather(String(arg))
			"rest_found": q.on_rest_found(arg)
		PlayerQuests.set_state(q.id, q.save_state())

# The closest gemstone within Chebyshev `r` of the player, or (-1,-1) if none.
func _nearest_gem(r: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := r + 1
	for t in omap.gem_tiles:
		var d: int = maxi(absi(t.x - player.pos.x), absi(t.y - player.pos.y))
		if d <= r and d < best_d:
			best = t
			best_d = d
	return best

# The closest NPC id within Chebyshev `r` of the player, or "" if none.
func _npc_near(r: int) -> String:
	var best := ""
	var best_d := r + 1
	for n in npcs:
		var t: Vector2i = n["tile"]
		var d: int = maxi(absi(t.x - player.pos.x), absi(t.y - player.pos.y))
		if d <= r and d < best_d:
			best = String(n["id"])
			best_d = d
	return best

# GATHER button: mine the nearest gemstone -> a material in the bag + a gather quest tick.
func _gather_nearby() -> void:
	var g := _nearest_gem(1)
	if g == Vector2i(-1, -1):
		return
	omap.remove_gem(g)
	board.queue_redraw()
	PlayerInventory.add("gemstone", 1)
	board.spawn_number(player_uv.position, "+" + ItemBook.item_name("gemstone"), ItemBook.item_color("gemstone"))
	_quest_event("gather", "gemstone")
	_refresh_rest_prompt()             # the node is gone -> the GATHER button may drop

# TALK button: open the nearest NPC's quest dialog (pauses roam while it's up).
func _talk_nearby() -> void:
	var npc := _npc_near(1)
	if npc == "":
		return
	_talk_npc = npc
	_paused = true
	quest_dialog.open_for(_npc_dialog_data(npc))

# Snapshot of an NPC's quest for the dialog: which button to show + current progress text.
func _npc_dialog_data(npc_id: String) -> Dictionary:
	var nd := NPCBook.npc_def(npc_id)
	var qid := NPCBook.quest_of(npc_id)
	var qdef := QuestBook.quest_def(qid)
	var mode := "accept"
	var prog := ""
	if PlayerQuests.is_done(qid):
		mode = "done"
	elif PlayerQuests.is_active(qid):
		var q := _live_quest(qid)
		if q != null:
			prog = q.progress_text()
			mode = "turn_in" if q.can_turn_in() else "progress"
	return {
		"npc": nd.get("name", ""), "color": nd.get("color", Color.WHITE),
		"qid": qid, "title": qdef.get("title", ""), "desc": qdef.get("desc", ""),
		"progress": prog, "mode": mode,
	}

# Dialog ACCEPT / TURN IN. After acting, re-open the dialog on its new state.
func _on_quest_action(qid: String, action: String) -> void:
	if action == "accept":
		PlayerQuests.accept(qid)
		var nq := QuestBook.make_quest(qid)
		nq.load_state(PlayerQuests.state_of(qid))
		_quests.append(nq)
	elif action == "turn_in":
		var q := _live_quest(qid)
		if q != null and q.can_turn_in():
			q.grant_reward()
			PlayerQuests.complete(qid)
			_quests.erase(q)
			board.spawn_number(player_uv.position, "Quest complete!", ViewConfig.COL_GOLD)
	if _talk_npc != "":
		quest_dialog.open_for(_npc_dialog_data(_talk_npc))

func _close_dialog() -> void:
	_paused = false
	_talk_npc = ""
	quest_dialog.close()
	_refresh_rest_prompt()

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
	for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
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

# Turn `c` to face `target` along the dominant axis (cardinal only), updating its view.
func _face_toward(c: Combatant, uv: UnitView, target: Vector2i) -> void:
	var dv := target - c.pos
	var dir: Vector2i
	if absi(dv.x) >= absi(dv.y):
		dir = Vector2i(signi(dv.x), 0)
	else:
		dir = Vector2i(0, signi(dv.y))
	if dir != Vector2i.ZERO:
		_face(c, uv, dir)

# ── world behavior: mob wandering, facing, passive regen, sanctuary rest ──────
# Every mob takes a wander step on a shared cadence: beeline toward you within MOB_AGGRO,
# otherwise drift. They never enter the village (your safe zone) and never overlap. A mob
# that steps into your window starts combat, exactly like walking into one yourself.
func _mob_roam(delta: float) -> void:
	if mobs.is_empty():
		return
	_mob_cd -= delta
	if _mob_cd > 0.0:
		return
	_mob_cd = MOB_ROAM_CD
	var occ := _occupied_tiles()
	for m in mobs:
		var c: Combatant = m["combatant"]
		var step := _wander_step(c.pos, occ)
		if step != c.pos:
			occ.erase(c.pos)
			occ[step] = true
			c.pos = step
			m["uv"].tween_to(step)
		_face_toward(c, m["uv"], player.pos)         # always turned to face you
		m["uv"].visible = _in_window(c.pos, _win)
	if not _engaged().is_empty():
		_phase = Phase.COMBAT
		_combat_loop()
	else:
		_refresh_rest_prompt()                       # a mob may have wandered in/out of range

# One wander step: chase you if close, else a random open step. Never a wall, the village,
# an occupied tile, or your own tile.
func _wander_step(pos: Vector2i, occ: Dictionary) -> Vector2i:
	var dirs: Array = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	if Grid.dist(pos, player.pos) <= MOB_AGGRO:
		dirs.sort_custom(func(a, b): return Grid.dist(pos + a, player.pos) < Grid.dist(pos + b, player.pos))
	else:
		dirs.shuffle()
		if randf() < 0.4:
			return pos                               # idle sometimes -> a calmer, natural drift
	for d: Vector2i in dirs:
		var t: Vector2i = pos + d
		if grid.is_blocked(t) or _in_village(t) or occ.has(t) or t == player.pos:
			continue
		return t
	return pos

func _occupied_tiles() -> Dictionary:
	var occ: Dictionary = { player.pos: true }
	for m in mobs:
		occ[m["combatant"].pos] = true
	return occ

# The tile a single-target ATTACK in this sequence aims at (-1,-1 if none).
func _attack_tile(seq: Array) -> Vector2i:
	for a in seq:
		if String(a.get("id", "")) == "attack":
			return a.get("tile", Vector2i(-1, -1))
	return Vector2i(-1, -1)

# Passive recovery: every REGEN_EVERY of YOUR actions, only ENERGY comes back. HP/MP are
# recovered by resting (a sanctuary tile fully restores you) -- moving never heals.
func _bump_actions(n: int) -> void:
	if n <= 0:
		return
	_actions += n
	while _actions >= REGEN_EVERY:
		_actions -= REGEN_EVERY
		_regen_tick()

func _regen_tick() -> void:
	player.energy = mini(Config.MAX_ENERGY, player.energy + REGEN_EP)

# Golden sanctuary tile (press R): if you're standing on one and no mob is within REST_SAFE
# tiles, fully restore HP/MP/EP. Roam-only -- _unhandled_input already gates out combat.
func _try_rest_tile() -> void:
	if not omap.is_rest(player.pos):
		return
	if _mob_near(player.pos, REST_SAFE):
		board.spawn_number(player_uv.position, "not safe", ViewConfig.COL_TEXT_OFF)
		return
	player.hp = Config.MAX_HP
	player.mp = Config.MAX_MP
	player.energy = Config.MAX_ENERGY
	player_uv.set_display_hp(player.hp)
	board.spawn_number(player_uv.position, "Rested!", ViewConfig.COL_GOLD)

func _mob_near(t: Vector2i, r: int) -> bool:
	for m in mobs:
		var p: Vector2i = m["combatant"].pos
		if maxi(absi(p.x - t.x), absi(p.y - t.y)) <= r:
			return true
	return false

# ── save / restore ────────────────────────────────────────────────────────────
func _gather_save() -> Dictionary:
	var mob_data: Array = []
	for m in mobs:
		var c: Combatant = m["combatant"]
		mob_data.append({
			"type": m["type"],
			"pos": [c.pos.x, c.pos.y],
			"facing": c.facing,
			"hp": c.hp,                    # mobs are HP-only: no mp/energy to persist
			"statuses": c.statuses,
		})
	var gem_data: Array = []
	for t in omap.gem_tiles:
		gem_data.append([t.x, t.y])
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
		"gems": gem_data,              # remaining gemstone nodes (gathered ones stay gone)
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
