# MatchRecord.gd
# A turn-by-turn recording of a match, used by the end-of-match replay viewer.
# Pure data with no view or rules knowledge: GameController records each resolved
# turn (a snapshot before and after, plus that turn's event list), and the replay
# reads it back. Snapshots are clones, so later play never mutates the record.
class_name MatchRecord
extends RefCounted

# Each entry: { turn:int, pre_a, pre_b, post_a, post_b: Combatant, events: Array,
#              layout: Array (wall snapshot), notes: Array of {text,color} (shift log) }
var turns: Array = []

func add(turn_num: int, pre_a: Combatant, pre_b: Combatant,
		post_a: Combatant, post_b: Combatant, events: Array,
		layout: Array = [], notes: Array = [], seq_a: Array = [], seq_b: Array = []) -> void:
	turns.append({
		"turn": turn_num,
		"pre_a": pre_a.clone(), "pre_b": pre_b.clone(),
		"post_a": post_a.clone(), "post_b": post_b.clone(),
		"events": events.duplicate(true),
		"layout": layout, "notes": notes,
		"seq_a": seq_a.duplicate(true), "seq_b": seq_b.duplicate(true),
	})

# ── Analyst dump: the whole match as compact text (user://last_match.txt), so a
# finished game can be pasted to Claude for turn-by-turn strategic review. ──
func write_dump(result: String) -> void:
	var f := FileAccess.open("user://last_match.txt", FileAccess.WRITE)
	if f == null:
		return
	f.store_line("UKO MATCH DUMP  result=%s  turns=%d" % [result, turns.size()])
	f.store_line("format: T# | A(x,y)facing hp/mp/ep | B(...) | A: seq | B: seq | dmg dealt A->B, B->A")
	for t in turns:
		var pa: Combatant = t["pre_a"]
		var pb: Combatant = t["pre_b"]
		var qa: Combatant = t["post_a"]
		var qb: Combatant = t["post_b"]
		f.store_line("T%02d | A(%d,%d)%s %d/%d/%d | B(%d,%d)%s %d/%d/%d | A: %s | B: %s | A->B %d, B->A %d" % [
			int(t["turn"]),
			pa.pos.x, pa.pos.y, _fc(pa.facing), pa.hp, pa.mp, pa.energy,
			pb.pos.x, pb.pos.y, _fc(pb.facing), pb.hp, pb.mp, pb.energy,
			_seq_str(t.get("seq_a", [])), _seq_str(t.get("seq_b", [])),
			pb.hp - qb.hp, pa.hp - qa.hp])
	f.close()
	print("[dump] match -> ", ProjectSettings.globalize_path("user://last_match.txt"))

func _seq_str(seq: Array) -> String:
	var parts: Array = []
	for a in seq:
		var s := String(a.get("id", "?"))
		if a.has("tile"):
			var tl: Vector2i = a["tile"]
			s += "@%d.%d" % [tl.x, tl.y]
		if a.has("facing"):
			s += "^" + _fc(int(a["facing"]))
		parts.append(s)
	return "+".join(parts) if not parts.is_empty() else "(none)"

func _fc(f: int) -> String:
	return ["N", "E", "S", "W"][clampi(f, 0, 3)]

func size() -> int:
	return turns.size()

func get_turn(i: int) -> Dictionary:
	return turns[clampi(i, 0, turns.size() - 1)]
