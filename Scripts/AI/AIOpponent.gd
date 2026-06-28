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

func _init(difficulty: int, tree: SceneTree) -> void:
	_difficulty = difficulty
	_tree = tree

func opponent_sequence(me: Combatant, foe: Combatant, grid: Grid, turn_num: int, local_seq: Array, opp_model) -> Array:
	await _tree.process_frame   # let "Waiting for opponent..." actually paint...
	await _tree.process_frame   # ...before the synchronous search blocks the thread
	return AI.choose_sequence(_difficulty, me, foe, grid, me.spell_ids(), opp_model)
