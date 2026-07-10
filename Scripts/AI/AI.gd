# AI.gd
# Difficulty dispatcher. The game asks AI.choose_sequence(difficulty, ...) and
# this routes to the right "brain". Each brain has the SAME signature as the
# player's input would produce: it returns a 1-2 action sequence.
#
# Tiers (this is a simultaneous-move game, so the ladder is really HOW MUCH the
# AI reasons about the hidden enemy move):
#   EASY        - StubOpponent: a fixed reaction ladder, no look-ahead.
#   CHALLENGING - ChallengingAI: scores its own candidate sequences by playing
#                 them through the real resolver against one assumed enemy move.
#   HARD        - HardAI: scores richer situations (via Eval) and makes a robust
#                 maximin-with-light-mixing choice over its candidate sequences.
#   EXTREME     - ExtremeAI: builds the move matrix, solves it for a
#                 least-exploitable mixed strategy (NashSolver), then samples.
class_name AI
extends RefCounted

enum Difficulty { EASY, CHALLENGING, HARD, EXTREME }

# ── C# EXTREME brain (the verified port: 673/673 engine parity + 880/880 brain
# agreement). true -> EXTREME runs the C# ExtremeAI via BrainBridge (one marshal
# per decision, whole search in C#). false -> the previous GDScript path
# (EconomyAI experiment) exactly as before. Flip this line to roll back.
const USE_CSHARP_EXTREME := true
static var _bridge = null          # lazy BrainBridge instance
static var _bridge_failed := false # C# unavailable (not built) -> silent fallback

static func _get_bridge():
	if _bridge != null or _bridge_failed:
		return _bridge
	var script = load("res://Scripts/Port/CSharp/BrainBridge.cs")
	if script == null:
		_bridge_failed = true
		push_warning("[AI] BrainBridge.cs unavailable -- EXTREME falls back to GDScript.")
		return null
	_bridge = script.new()
	_bridge.SetProfile("extreme")
	_bridge.LoadCalibration()   # sets the C# Eval.CAL_A from user://calibration.cfg
	_bridge.LoadModel()         # warm-start from what past matches learned (same cfg the GD model writes)
	return _bridge

# GameController forwards each observed local-player move here so the C# brain's
# opponent model learns live (the GDScript model remains the one that SAVES).
static func forward_observation(seq: Array, sit: String) -> void:
	if not USE_CSHARP_EXTREME:
		return
	var b = _get_bridge()
	if b != null:
		b.ObserveFoe(seq, sit)

static func _csharp_choose(me: Combatant, foe: Combatant, grid: Grid, opp_model) -> Array:
	var b = _get_bridge()
	if b == null:
		ExtremeAI.set_profile("extreme")
		return EconomyAI.choose_sequence(me, foe, grid, [], opp_model)
	var rows := _grid_rows(grid.blocked)
	var brows := _grid_rows(grid.base_blocked)
	var seq: Array = Array(b.ChooseSequence(rows, brows, grid.rot_step, grid.shrink_level,
			_combatant_dict(me), _combatant_dict(foe), true))
	if seq.is_empty():
		return [{"id": "wait"}]
	return seq

static func _grid_rows(blocked: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in range(Grid.SIZE):
		var line := ""
		for x in range(Grid.SIZE):
			line += "#" if blocked[y][x] else "."
		rows.append(line)
	return rows

static func _combatant_dict(c: Combatant) -> Dictionary:
	return {"id": c.id, "x": c.pos.x, "y": c.pos.y, "facing": c.facing,
		"hp": c.hp, "mp": c.mp, "energy": c.energy,
		"action_count": c.action_count, "rest_ready": c.rest_ready, "speed_boost": c.speed_boost,
		"cooldowns": c.cooldowns.duplicate(), "statuses": c.statuses.duplicate(),
		"spent_once": c.spent_once.duplicate(), "gear": c.gear.duplicate()}

# Chosen on the main menu's difficulty page; read by GameController at startup.
# A static var carries it across the menu->game scene change (no autoload needed;
# requires Godot 4.1+ — on 4.0 use a small autoload singleton instead).
static var selected_difficulty: int = Difficulty.CHALLENGING

static func choose_sequence(difficulty: int, me: Combatant, foe: Combatant,
		grid: Grid, spells: Array, opp_model = null) -> Array:
	match difficulty:
		Difficulty.EASY:
			return StubOpponent.choose_sequence(me, foe, grid, spells)
		Difficulty.CHALLENGING:
			# The frozen matrix-Nash brain at today's settings, no opponent model:
			# a fair, non-adapting equilibrium wall (the tier the design approved).
			ExtremeAI.set_profile("challenging")
			return ExtremeAI.choose_sequence(me, foe, grid, spells)
		Difficulty.HARD:
			return HardAI.choose_sequence(me, foe, grid, spells, opp_model)
		Difficulty.EXTREME:
			if USE_CSHARP_EXTREME:
				return _csharp_choose(me, foe, grid, opp_model)   # verified C# ExtremeAI (Nash + depth)
			ExtremeAI.set_profile("extreme")   # full budget, wider search, adaptive model
			return EconomyAI.choose_sequence(me, foe, grid, spells, opp_model)  # economy + intent + Nash (remodelled)
		_:
			return StubOpponent.choose_sequence(me, foe, grid, spells)

static func name_of(difficulty: int) -> String:
	match difficulty:
		Difficulty.EASY: return "Easy"
		Difficulty.CHALLENGING: return "Challenging"
		Difficulty.HARD: return "Hard"
		Difficulty.EXTREME: return "Extreme"
		_: return "?"
