# MatchRecord.gd
# A turn-by-turn recording of a match, used by the end-of-match replay viewer.
# Pure data with no view or rules knowledge: GameController records each resolved
# turn (a snapshot before and after, plus that turn's event list), and the replay
# reads it back. Snapshots are clones, so later play never mutates the record.
class_name MatchRecord
extends RefCounted

# Each entry: { turn:int, pre_a, pre_b, post_a, post_b: Combatant, events: Array }
var turns: Array = []

func add(turn_num: int, pre_a: Combatant, pre_b: Combatant,
		post_a: Combatant, post_b: Combatant, events: Array) -> void:
	turns.append({
		"turn": turn_num,
		"pre_a": pre_a.clone(), "pre_b": pre_b.clone(),
		"post_a": post_a.clone(), "post_b": post_b.clone(),
		"events": events.duplicate(true),
	})

func size() -> int:
	return turns.size()

func get_turn(i: int) -> Dictionary:
	return turns[clampi(i, 0, turns.size() - 1)]
