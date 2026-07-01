# SelectionController.gd
# The player's turn-input SYSTEM: the choosing -> targeting -> confirm state
# machine, the keyboard/mouse handlers, the projection used to position targets,
# and the per-action geometry. Owns NO game rules and NO scene lifecycle -- it
# reads the live board + the projected player, drives the board highlights + the
# action menu, and emits `player_sequence_ready` when the player commits a turn.
# GameController instantiates it, wires the board/menu signals to it, and awaits
# that signal. Feature work on input/targeting lives here, not in GameController.
class_name SelectionController
extends Node

signal player_sequence_ready(seq: Array)

var grid: Grid
var board: BoardView
var menu: ActionMenu
var a: Combatant              # the player (start-of-turn state)
var b: Combatant              # the enemy

var phase := "idle"          # "choosing" | "targeting" | "blink_face" | "confirm" | "idle"
var pending: String = ""     # id being targeted
var blink_land := Vector2i.ZERO   # blink: landing chosen, awaiting the reface pick
var seq: Array = []          # the 1-2 actions chosen this turn
var plan_c: Combatant        # the player projected through the chosen actions (for targeting)
var preview: Dictionary = {} # keyboard: action aimed but not yet confirmed

# Wire the system to the live scene objects (called once by GameController).
func setup(p_grid: Grid, p_board: BoardView, p_menu: ActionMenu) -> void:
	grid = p_grid
	board = p_board
	menu = p_menu

# Start a fresh turn from the current combatant state.
func begin_turn(p_a: Combatant, p_b: Combatant) -> void:
	a = p_a
	b = p_b
	seq = []
	pending = ""
	preview = {}
	blink_land = Vector2i.ZERO
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
		if Config.is_blink(id):
			pending = id
			phase = "targeting"
			board.set_highlights(_blink_targets(), ViewConfig.COL_HL_MOVE)
		elif d.get("needs_tile", false):
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
			if seq.is_empty() and a.rest_ready:   # whole-turn action; only as first pick, and only when safe
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
	# Blink step 2: a landing is chosen; this click picks the post-blink facing.
	if phase == "blink_face":
		if pos in _blink_face_tiles(blink_land):
			_add_action({"id": pending, "tile": blink_land, "facing": _facing_from(blink_land, pos)})
		return
	if phase != "targeting":
		return
	if Config.is_spell(pending):
		var d := Config.def(pending)
		if Config.is_blink(pending):
			# Blink step 1: pick a landing, then move to the reface sub-phase.
			if pos in _blink_targets():
				blink_land = pos
				phase = "blink_face"
				board.set_highlights(_blink_face_tiles(pos), ViewConfig.COL_HL_PIVOT)
			return
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
	if phase == "blink_face":
		phase = "targeting"                       # back to picking a landing
		board.set_highlights(_blink_targets(), ViewConfig.COL_HL_MOVE)
		return
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
	if seq.is_empty() and a.rest_ready:
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
	if Config.is_blink(id):
		pending = id                              # mouse finishes the direction + reface
		phase = "targeting"
		board.set_highlights(_blink_targets(), ViewConfig.COL_HL_MOVE)
	elif Config.def(id).get("needs_tile", false):
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
	# Same projection the AI uses -- handles move / pivot / BLINK-relocate / spell
	# cost + cooldown -- so targeting plans the next action from the real (post-blink)
	# tile. One source of truth; then the self-buff discount so menu affordability matches.
	AIToolkit.apply_projection(c, action)
	Config.apply_planned_self_buff(c.statuses, action.get("id", ""))

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
	for dv in Grid.DIRS:
		var p: Vector2i = plan_c.pos + dv
		if grid.in_bounds(p):
			out.append(p)
	return out

func _legal_moves() -> Array:
	var out := []
	for dv in Grid.DIRS:
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
	for dv in Grid.DIRS:
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

# Valid blink landing tiles (one per cardinal with a clear landing) from the
# projection -- the first targeting step. Reuses the one Config blink rule.
func _blink_targets() -> Array:
	var out := []
	if not Config.is_blink(pending):
		return out
	var rng := int(Config.def(pending).get("range", 2))
	for dv in Grid.DIRS:
		# A direction is castable if its line has any landable tile. Aim at the FULL-RANGE
		# tile so you can target an enemy or blocker sitting there -- the resolver settles the
		# real landing at arrival (the full jump if the tile clears, one tile if it stays).
		var bl := Config.blink_landing(grid, plan_c.pos, dv, rng, b.pos)
		if bl.is_empty():
			continue
		var aim: Vector2i = plan_c.pos + dv * rng
		out.append(aim if grid.in_bounds(aim) else bl["tile"])
	return out

# In-bounds orthogonal neighbours of the landing -- click one to face that way.
func _blink_face_tiles(land: Vector2i) -> Array:
	var out := []
	for dv in Grid.DIRS:
		var p: Vector2i = land + dv
		if grid.in_bounds(p):
			out.append(p)
	return out

# Facing from `origin` toward an adjacent tile `pos`.
func _facing_from(origin: Vector2i, pos: Vector2i) -> int:
	var dv: Vector2i = pos - origin
	if dv == Vector2i(0, -1): return Config.Facing.NORTH
	if dv == Vector2i(1, 0): return Config.Facing.EAST
	if dv == Vector2i(0, 1): return Config.Facing.SOUTH
	return Config.Facing.WEST
