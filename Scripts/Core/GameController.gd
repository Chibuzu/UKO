# GameController.gd
# The playable game. Builds the board, pieces, menu, and playback, then runs
# the turn loop. Selection is two steps for targeted actions:
#   1. Click an action/spell button.
#   2. For MOVE/ATTACK/PIVOT and line spells, click a highlighted tile.
#      Right-click cancels. Self/AoE/GUARD/REST fire immediately.
extends Node

signal player_sequence_ready(seq: Array)

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

# Loadouts are GEAR now, not spells. Each slot (1-4) holds a GearBook id
# ("" = empty/white block); the spell it grants is derived from the gear, so
# swapping a slot swaps that block's spell. Slots map 1:1 to the four blocks
# and to number keys 1-4. Slot 4 is empty until there's a fourth gear piece.
const PLAYER_GEAR := ["discount_charm", "burst_node", "dark_focus", ""]
const AI_GEAR := ["discount_charm", "burst_node", "dark_focus", ""]

const MENU_SCENE := "res://MainMenu.tscn"   # adjust if your menu scene lives elsewhere

# Which brain player B uses. Wire this to the main menu later; for now flip it
# here. EASY = StubOpponent ladder; CHALLENGING = the look-ahead search brain.
var difficulty: int = AI.Difficulty.CHALLENGING

var grid: Grid
var board: BoardView
var ua: UnitView
var ub: UnitView
var play: EventPlayer
var fx: Fx
var menu: ActionMenu
var combat_log: CombatLog
var a: Combatant
var b: Combatant

var turn_num := 0
var phase := "idle"          # "choosing" | "targeting" | "confirm" | "idle"
var pending: String = ""     # id being targeted
var seq: Array = []          # the 1-2 actions chosen this turn
var plan_c: Combatant        # A projected through the chosen actions (for targeting)
var preview: Dictionary = {} # keyboard: action aimed but not yet confirmed

# ── Replay ──
var match_record := MatchRecord.new()   # every resolved turn, for end-of-match replay
var end_screen: EndScreen                # kept so replay can hide/restore it
var replay_bar: ReplayBar
var replay_idx := 0

func _ready() -> void:
	difficulty = AI.selected_difficulty   # whatever the menu's difficulty page picked
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	grid = Grid.new()
	grid.generate(rng)

	board = BoardView.new()
	add_child(board)
	board.setup(grid)
	board.tile_clicked.connect(_on_tile_clicked)
	board.selection_cancelled.connect(_on_cancel)

	a = Combatant.new("A", grid.spawn_a, Config.Facing.EAST)
	b = Combatant.new("B", grid.spawn_b, Config.Facing.WEST)
	a.equip(PLAYER_GEAR)
	b.equip(AI_GEAR)

	ua = UnitView.new()
	board.add_child(ua)
	ua.init_state(a)
	ub = UnitView.new()
	board.add_child(ub)
	ub.init_state(b)

	fx = Fx.new()
	board.add_child(fx)

	play = EventPlayer.new()
	add_child(play)
	play.setup(board, fx, ua, ub)

	menu = ActionMenu.new()
	add_child(menu)
	menu.action_chosen.connect(_on_action_chosen)

	combat_log = CombatLog.new()
	add_child(combat_log)

	_game_loop()

func _game_loop() -> void:
	var opp_model := OpponentModel.new()   # learns player A's habits across this match
	while true:
		turn_num += 1
		_begin_turn()
		var seq_a: Array = await player_sequence_ready
		phase = "idle"
		menu.set_state(a, b, false, a.spell_ids(), [], false)
		board.clear_highlights()

		var pre_a := a.clone()   # snapshot the turn's START state for the replay
		var pre_b := b.clone()
		var seq_b: Array = AI.choose_sequence(difficulty, b, a, grid, b.spell_ids(), opp_model)
		var out := Resolver.resolve(grid, a, b, seq_a, seq_b, turn_num)
		opp_model.observe(seq_a)   # learn what A actually did, for next turn's prediction
		match_record.add(turn_num, pre_a, pre_b, out["a"], out["b"], out["events"])
		await play.play(out["events"], out["a"], out["b"])
		a = out["a"]
		b = out["b"]
		menu.set_state(a, b, false, a.spell_ids(), [], false)
		combat_log.add_turn(turn_num, out["events"])

		if out["result"] != "ongoing":
			_show_result(out["result"])
			return

func _begin_turn() -> void:
	seq = []
	pending = ""
	preview = {}
	phase = "choosing"
	_rebuild_plan()
	_refresh_menu()

# ── Selection (two actions, then confirm) ───────────────────
func _on_action_chosen(id: String) -> void:
	preview = {}
	if id == "confirm":
		if phase == "confirm":
			phase = "idle"
			player_sequence_ready.emit(seq.duplicate())
		return
	if phase != "choosing":
		return
	if Config.is_spell(id):
		var d := Config.def(id)
		if d.get("needs_tile", false):
			pending = id
			phase = "targeting"
			board.set_highlights(_line_targets(int(d.get("range", 1))), ViewConfig.COL_HL_ATTACK)
		else:
			_add_action({"id": id})
		return
	match id:
		"guard", "wait":
			_add_action({"id": id})
		"rest":
			if seq.is_empty():            # Rest is the whole turn; only as the first pick
				_add_action({"id": "rest"})
		"move":
			pending = "move"
			phase = "targeting"
			board.set_highlights(_legal_moves(), ViewConfig.COL_HL_MOVE)
		"attack":
			pending = "attack"
			phase = "targeting"
			board.set_highlights(_adjacent_tiles(), ViewConfig.COL_HL_ATTACK)
		"pivot":
			pending = "pivot"
			phase = "targeting"
			board.set_highlights(_adjacent_tiles(), ViewConfig.COL_HL_PIVOT)

func _on_tile_clicked(pos: Vector2i) -> void:
	if phase != "targeting":
		return
	if Config.is_spell(pending):
		var d := Config.def(pending)
		if d.get("shape") == "line" and pos in _line_targets(int(d.get("range", 1))):
			_add_action({"id": pending, "tile": pos})
		return
	match pending:
		"move":
			if pos in _legal_moves():
				_add_action({"id": "move", "tile": pos})
		"attack":
			if pos in _adjacent_tiles():
				_add_action({"id": "attack", "tile": pos})
		"pivot":
			if pos in _adjacent_tiles():
				_add_action({"id": "pivot", "facing": _facing_to(pos)})

# Right-click: cancel a pending target, otherwise undo the last chosen action.
func _on_cancel() -> void:
	if phase == "targeting":
		pending = ""
		phase = "choosing"
		_refresh_menu()
	elif (phase == "choosing" or phase == "confirm") and not seq.is_empty():
		seq.pop_back()
		pending = ""
		phase = "choosing"
		_rebuild_plan()
		_refresh_menu()

# ── Keyboard controls ───────────────────────────────────────
# WASD = move, arrows = pivot, Z = attack, X = guard, C = wait, R = rest,
# 1/2/3 = buff / AoE / special, Enter or Space = confirm, Backspace = undo.
# Every key feeds the same _add_action path the mouse uses; directional and
# targeted actions compute against the projection (plan_c), and the single
# enemy is auto-targeted for attack and the special.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not preview.is_empty():
				_confirm_preview()
			elif phase == "confirm":
				_on_action_chosen("confirm")
			return
		KEY_BACKSPACE:
			if not preview.is_empty():
				_clear_preview()
			else:
				_on_cancel()
			return
	if phase != "choosing":
		return
	match event.keycode:
		KEY_W: _key_move(Vector2i(0, -1))
		KEY_S: _key_move(Vector2i(0, 1))
		KEY_A: _key_move(Vector2i(-1, 0))
		KEY_D: _key_move(Vector2i(1, 0))
		KEY_UP: _key_pivot(Vector2i(0, -1))
		KEY_DOWN: _key_pivot(Vector2i(0, 1))
		KEY_LEFT: _key_pivot(Vector2i(-1, 0))
		KEY_RIGHT: _key_pivot(Vector2i(1, 0))
		KEY_Z: _key_attack()
		KEY_X: _key_basic("guard")
		KEY_C: _key_basic("wait")
		KEY_R: _key_rest()
		KEY_1: _key_spell_slot(0)
		KEY_2: _key_spell_slot(1)
		KEY_3: _key_spell_slot(2)
		KEY_4: _key_spell_slot(3)

func _key_move(dir: Vector2i) -> void:
	var tile: Vector2i = plan_c.pos + dir
	if tile in _legal_moves():
		_aim({"id": "move", "tile": tile}, tile, ViewConfig.COL_HL_MOVE)

func _key_pivot(dir: Vector2i) -> void:
	var tile: Vector2i = plan_c.pos + dir
	_aim({"id": "pivot", "facing": _facing_to(tile)}, tile, ViewConfig.COL_HL_PIVOT)

func _key_attack() -> void:
	if b.pos in _adjacent_tiles() and Config.can_afford(plan_c.energy, plan_c.mp, plan_c.statuses, "attack"):
		_aim({"id": "attack", "tile": b.pos}, b.pos, ViewConfig.COL_HL_ATTACK)

# ── Keyboard aiming: first press highlights the target tile; a second press of
#    the same key (or Enter) confirms it. ────────────────────────────────────
func _aim(action: Dictionary, tile: Vector2i, color: Color) -> void:
	if _same_action(preview, action):
		_confirm_preview()                  # re-press the same aim = commit
	else:
		preview = action
		board.set_highlights([tile], color)

func _confirm_preview() -> void:
	if preview.is_empty():
		return
	var act := preview
	preview = {}
	_add_action(act)

func _clear_preview() -> void:
	preview = {}
	board.clear_highlights()

func _same_action(x: Dictionary, y: Dictionary) -> bool:
	if x.is_empty() or y.is_empty():
		return false
	if x.get("id", "") != y.get("id", ""):
		return false
	if x.get("tile", Vector2i(-99, -99)) != y.get("tile", Vector2i(-99, -99)):
		return false
	return x.get("facing", -1) == y.get("facing", -1)

func _key_basic(id: String) -> void:
	if id == "wait" or Config.can_afford(plan_c.energy, plan_c.mp, plan_c.statuses, id):
		_add_action({"id": id})

func _key_rest() -> void:
	if seq.is_empty():
		_add_action({"id": "rest"})

func _key_spell_slot(slot: int) -> void:
	var id := a.spell_in_slot(slot)   # whatever gear is equipped in this block
	if id != "":
		_key_spell(id)

func _key_spell(id: String) -> void:
	if not (id in a.spell_ids()):
		return
	if int(plan_c.cooldowns.get(id, 0)) > 0:
		return
	if not Config.can_afford(plan_c.energy, plan_c.mp, plan_c.statuses, id):
		return
	if Config.def(id).get("needs_tile", false):
		# Line spell: auto-aim at the enemy if they're on a clear line in range.
		var rng: int = int(Config.def(id).get("range", 1))
		if b.pos in _line_targets(rng):
			_aim({"id": id, "tile": b.pos}, b.pos, ViewConfig.COL_HL_ATTACK)
	else:
		_add_action({"id": id})

# True if adding `action` would put Guard and a no-guard-combo spell (DARK BOLT)
# in the same turn. The resolver forbids that pairing, so we block it at pick
# time too rather than let the player queue an action that gets voided.
func _conflicts_with_plan(action: Dictionary) -> bool:
	var id: String = action.get("id", "")
	var adding_guard: bool = Config.def(id).get("category", "") == "guard"
	var adding_ng := Config.is_spell(id) and bool(Config.def(id).get("no_guard_combo", false))
	if not adding_guard and not adding_ng:
		return false
	for prev in seq:
		var pid: String = prev.get("id", "")
		var prev_guard: bool = Config.def(pid).get("category", "") == "guard"
		var prev_ng := Config.is_spell(pid) and bool(Config.def(pid).get("no_guard_combo", false))
		if (adding_guard and prev_ng) or (adding_ng and prev_guard):
			return true
	return false

func _add_action(action: Dictionary) -> void:
	if _conflicts_with_plan(action):
		# Guard and DARK BOLT can't share a turn; drop the conflicting pick.
		pending = ""
		preview = {}
		board.clear_highlights()
		_refresh_menu()
		return
	seq.append(action)
	pending = ""
	preview = {}
	board.clear_highlights()
	_rebuild_plan()
	var cat: String = Config.def(action.get("id", "")).get("category", "")
	if cat == "rest" or seq.size() >= 2:
		phase = "confirm"
	else:
		phase = "choosing"
	_refresh_menu()

# Rebuild the projection (A advanced through the chosen actions) for targeting.
func _rebuild_plan() -> void:
	plan_c = a.clone()
	for action in seq:
		_simulate(plan_c, action)

func _simulate(c: Combatant, action: Dictionary) -> void:
	var id: String = action.get("id", "")
	var d := Config.def(id)
	var cat: String = d.get("category", "")
	if cat == "move" and action.has("tile"):
		c.energy = maxi(0, c.energy - Config.effective_move_cost(c.facing, c.pos, action["tile"], c.statuses))
		c.pos = action["tile"]
	elif cat == "pivot" and action.has("facing"):
		c.facing = int(action["facing"])
	else:
		c.energy = maxi(0, c.energy - Config.effective_energy_cost(id, c.statuses))
		c.mp = maxi(0, c.mp - int(d.get("mp_cost", 0)))
		if Config.is_spell(id):
			var cd := Config.cooldown_of(id)
			if cd > 0:
				c.cooldowns[id] = cd
	# A self-buff queued earlier discounts later actions THIS turn -- same shared
	# helper the resolver uses, so the menu's affordability matches resolution.
	Config.apply_planned_self_buff(c.statuses, id)

func _refresh_menu() -> void:
	# Show the PROJECTED self (energy/mp/cooldowns after the actions chosen so
	# far) so action-2 availability matches what the resolver will allow.
	var view_self: Combatant = plan_c if plan_c != null else a
	menu.set_state(view_self, b, phase != "idle", a.spell_ids(), _planned_labels(), phase == "confirm")

func _planned_labels() -> Array:
	var out: Array = []
	for action in seq:
		var id: String = action.get("id", "")
		out.append(Config.def(id).get("name", id.to_upper()) if Config.is_spell(id) else id.to_upper())
	return out

# ── Geometry helpers (use the projection, so slot-2 targets from where the
#    earlier actions leave you) ────────────────────────────────────────────
func _adjacent_tiles() -> Array:
	var out := []
	for dv in DIRS:
		var p: Vector2i = plan_c.pos + dv
		if grid.in_bounds(p):
			out.append(p)
	return out

func _legal_moves() -> Array:
	var out := []
	for dv in DIRS:
		var p: Vector2i = plan_c.pos + dv
		# The foe's tile is now a legal target: if they vacate (or you both move
		# into each other -> swap) you take it, else the move fizzles and is
		# refunded. Walls and out-of-bounds stay illegal.
		if grid.in_bounds(p) and not grid.is_blocked(p):
			if plan_c.energy >= Config.effective_move_cost(plan_c.facing, plan_c.pos, p, plan_c.statuses):
				out.append(p)
	return out

# Tiles a line spell could reach: each orthogonal direction, up to range,
# stopping at the first blocker (matches the resolver's line trace).
func _line_targets(rng: int) -> Array:
	var out := []
	for dv in DIRS:
		var p: Vector2i = plan_c.pos
		for _i in range(rng):
			p += dv
			if not grid.in_bounds(p) or grid.is_blocked(p):
				break
			out.append(p)
	return out

func _facing_to(pos: Vector2i) -> int:
	var dv: Vector2i = pos - plan_c.pos
	if dv == Vector2i(0, -1): return Config.Facing.NORTH
	if dv == Vector2i(1, 0): return Config.Facing.EAST
	if dv == Vector2i(0, 1): return Config.Facing.SOUTH
	return Config.Facing.WEST

# ── End screen ──────────────────────────────────────────────
func _show_result(result: String) -> void:
	var text := "DRAW"
	var color := ViewConfig.COL_DRAW
	if result == "a_wins":
		text = "A WINS"
		color = ViewConfig.COL_WIN_A
	elif result == "b_wins":
		text = "B WINS"
		color = ViewConfig.COL_WIN_B
	var es := EndScreen.new()
	add_child(es)
	es.setup(text, color)
	es.choice.connect(_on_end_choice)
	end_screen = es

func _on_end_choice(which: String) -> void:
	match which:
		"rematch":
			get_tree().reload_current_scene()      # fresh match, same scene
		"menu":
			get_tree().change_scene_to_file(MENU_SCENE)
		"replay":
			_enter_replay()

# ── End-of-match replay ─────────────────────────────────────
# Step the finished match turn by turn. Reuses the live board, unit views,
# EventPlayer and CombatLog; nothing new renders. Stepping snaps to a turn's
# end state; PLAY re-animates that turn from its start.
func _enter_replay() -> void:
	if match_record.size() == 0:
		return
	if end_screen:
		end_screen.visible = false
		end_screen.set_process_input(false)   # hidden screens still eat clicks otherwise
	menu.visible = false
	board.clear_highlights()
	replay_bar = ReplayBar.new()
	add_child(replay_bar)
	replay_bar.replay_action.connect(_on_replay_action)
	_replay_show(0)

func _on_replay_action(which: String) -> void:
	match which:
		"prev":
			_replay_show(replay_idx - 1)
		"next":
			_replay_show(replay_idx + 1)
		"play":
			await _replay_play_current()
		"exit":
			_exit_replay()

# Jump to a turn: snap the board to its END state and show the log through it.
func _replay_show(idx: int) -> void:
	replay_idx = clampi(idx, 0, match_record.size() - 1)
	var t := match_record.get_turn(replay_idx)
	board.clear_highlights()
	ua.set_state(t["post_a"])
	ub.set_state(t["post_b"])
	_rebuild_log_through(replay_idx)
	replay_bar.set_label("TURN %d / %d" % [t["turn"], match_record.size()])

# Re-animate the current turn from its START state, so you watch the actual plays.
func _replay_play_current() -> void:
	var t := match_record.get_turn(replay_idx)
	replay_bar.set_enabled(false)
	board.clear_highlights()
	ua.set_state(t["pre_a"])
	ub.set_state(t["pre_b"])
	await play.play(t["events"], t["post_a"], t["post_b"])
	replay_bar.set_enabled(true)

func _exit_replay() -> void:
	if replay_bar:
		replay_bar.queue_free()
		replay_bar = null
	var last := match_record.get_turn(match_record.size() - 1)
	ua.set_state(last["post_a"])
	ub.set_state(last["post_b"])
	_rebuild_log_through(match_record.size() - 1)
	if end_screen:
		end_screen.visible = true
		end_screen.set_process_input(true)

func _rebuild_log_through(idx: int) -> void:
	combat_log.clear()
	for i in range(idx + 1):
		var t := match_record.get_turn(i)
		combat_log.add_turn(t["turn"], t["events"])
