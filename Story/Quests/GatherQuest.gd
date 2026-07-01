# GatherQuest.gd
# "Gather X materials from the map." Counts gather events the controller reports via
# on_gather (e.g. mining gemstone nodes). Distinct from FetchQuest: this counts the ACT of
# gathering (not a bag total) and does not consume anything on hand-in.
class_name GatherQuest
extends QuestKind

var _count := 0

func on_gather(material_id: String) -> void:
	var want := String(def.get("material", "gemstone"))
	if material_id == want:
		_count += 1

func progress() -> int:
	return _count

func save_state() -> Dictionary:
	return {"count": _count}

func load_state(state: Dictionary) -> void:
	_count = int(state.get("count", 0))
