# AIOpponent.gd
# Offline opponent: the existing AI brain behind the OpponentSource seam. Behaviour
# is byte-for-byte the old inline call -- including the two-frame yield that lets the
# menu paint "Waiting for opponent..." before the synchronous search hogs the main
# thread. Moving that yield in here keeps the turn loop agnostic about how long the
# opponent takes to "think".
class_name AIOpponent
extends OpponentSource

var _difficulty: int
var _tree: SceneTree
var _mob := ""   # "bat"/"ooze" -> toolkit-restricted MobAI instead of the duel brain

func _init(difficulty: int, tree: SceneTree, mob: String = "") -> void:
	_difficulty = difficulty
	_tree = tree
	_mob = mob

func opponent_sequence(me: Combatant, foe: Combatant, grid: Grid, turn_num: int, local_seq: Array, opp_model) -> Array:
	await _tree.process_frame   # let "Waiting for opponent..." actually paint...
	await _tree.process_frame   # ...before the synchronous search blocks the thread
	# ANY mob tag except the (undesigned) boss uses the toolkit-restricted brain --
	# robust to whatever the overworld names its creatures.
	if _mob != "" and _mob != "boss":
		print("[mob] '%s' -> MobAI (toolkit: attack/pivot/move)" % _mob)
		return MobAI.choose_sequence(_mob, me, foe, grid)
	if _mob == "":
		print("[mob] NO TAG -> duel brain (overworld did not set pending_b_mob!)")
	return AI.choose_sequence(_difficulty, me, foe, grid, me.spell_ids(), opp_model)
