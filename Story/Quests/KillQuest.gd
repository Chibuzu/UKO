# KillQuest.gd
# "Kill X mobs" (optionally of a specific type). Counts kills the controller reports via
# on_kill; def "target_type" == "" means any creature counts.
class_name KillQuest
extends QuestKind

var _count := 0

func on_kill(mob_type: String) -> void:
	var want := String(def.get("target_type", ""))
	if want == "" or want == mob_type:
		_count += 1

func progress() -> int:
	return _count

func save_state() -> Dictionary:
	return {"count": _count}

func load_state(state: Dictionary) -> void:
	_count = int(state.get("count", 0))
