# AI.gd
# Difficulty dispatcher. The game asks AI.choose_sequence(difficulty, ...) and
# this routes to the right "brain". Each brain has the SAME signature as the
# player's input would produce: it returns a 1-2 action sequence.
#
# Tiers (this is a simultaneous-move game, so the ladder is really HOW MUCH the
# AI reasons about the hidden enemy move):
#   EASY        - StubOpponent: a fixed reaction ladder, no look-ahead.
#   CHALLENGING - ExtremeAI under the frozen "challenging" profile: the matrix-
#                 Nash brain throttled to the approved feel, no opponent model.
#   HARD        - HardAI: scores richer situations (via Eval) and makes a robust
#                 maximin-with-light-mixing choice over its candidate sequences
#                 (ChallengingAI survives only as its greedy sanity floor).
#   EXTREME     - the C# ExtremeAI via BrainBridge (verified port: 673/673
#                 engine parity + 880/880 brain agreement). If the C# assembly
#                 is unavailable, falls back to the GDScript ExtremeAI under the
#                 same "extreme" profile -- the same brain, slower; NEVER a
#                 different one.
class_name AI
extends RefCounted

enum Difficulty { EASY, CHALLENGING, HARD, EXTREME }

# ── C# EXTREME brain. true -> EXTREME runs the C# ExtremeAI via BrainBridge
# (one marshal per decision, whole search in C#). false -> the GDScript
# ExtremeAI (numeric twin, slower). Flip this line to roll back.
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
	# A broken export (missing .NET assemblies) can boot GDScript-only: load() then
	# "succeeds" but the C# instance is dead. Verify before touching it -- fall back
	# instead of crashing the match (this was the friend-build turn-1 crash).
	if _bridge == null or not _bridge.has_method("ChooseSequence"):
		_bridge = null
		_bridge_failed = true
		push_warning("[AI] BrainBridge could not instantiate (no .NET runtime?) -- EXTREME falls back to GDScript.")
		return null
	_bridge.SetProfile("extreme")
	_bridge.LoadCalibration()   # sets the C# Eval.CAL_A from user://calibration.cfg
	_bridge.LoadModel()         # warm-start from what past matches learned (same cfg the GD model writes)
	_bridge.SetDepth(3)         # sweep-validated (2 nights, ~54% + positive margins at EQUAL time):
	                            # depth 3 @ the same 700ms budget -- free strength, zero added latency
	# LEARNED VALUE JUDGE (adopted 2026-07-19: 64.6% over 450 arena matches, then
	# all six behavior gates green with it armed). Reads user://value_fn.cfg; if
	# the file is missing/invalid this is a no-op and EXTREME plays the hand eval
	# exactly as before. The cfg IS the switch -- delete it to roll back, refit
	# (run_fit_value.bat) to update. The bridge serves ONLY the EXTREME tier.
	_bridge.SetValueEnabled(_bridge.LoadValueFn())
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
		# Same brain, GDScript body: the numeric twin the agreement harness
		# verified. EXTREME must never silently become a different fighter --
		# including its judge: arm the learned value here too (same cfg).
		ExtremeAI.set_profile("extreme")
		Eval.VALUE_ON = _value_loaded()
		return ExtremeAI.choose_sequence(me, foe, grid, me.spell_ids(), opp_model)
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
	return c.to_bridge_dict()   # the ONE marshal contract lives on Combatant

# (The menu's picked difficulty now travels through MatchBootstrap.difficulty —
# the one cross-scene handoff channel — not a static here.)

# One-time load of the learned value cfg for the GDSCRIPT extreme fallback
# (-1 unknown / 0 absent / 1 loaded). The C# path arms itself in _get_bridge().
static var _value_ok := -1
static func _value_loaded() -> bool:
	if _value_ok < 0:
		_value_ok = 1 if Eval.load_value_fn() else 0
	return _value_ok == 1

static func choose_sequence(difficulty: int, me: Combatant, foe: Combatant,
		grid: Grid, spells: Array, opp_model = null) -> Array:
	# TIER HYGIENE: Eval.VALUE_ON is a global static, so it must be re-asserted
	# per decision or an EXTREME duel would leak the learned judge into a later
	# CHALLENGING/HARD duel in the same session. EXTREME re-arms below; every
	# other tier plays the frozen hand eval, always.
	Eval.VALUE_ON = false
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
			Eval.VALUE_ON = _value_loaded()    # the adopted judge rides with the tier
			return ExtremeAI.choose_sequence(me, foe, grid, spells, opp_model)
		_:
			return StubOpponent.choose_sequence(me, foe, grid, spells)

static func name_of(difficulty: int) -> String:
	match difficulty:
		Difficulty.EASY: return "Easy"
		Difficulty.CHALLENGING: return "Challenging"
		Difficulty.HARD: return "Hard"
		Difficulty.EXTREME: return "Extreme"
		_: return "?"
