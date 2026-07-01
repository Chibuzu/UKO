# FindTilesQuest.gd
# "Find X of the golden highlight tiles" (sanctuary shrines). Tracks a SET of discovered
# tiles (keyed "x,y") so revisiting one never double-counts. The controller reports a
# discovery via on_rest_found whenever you step onto a shrine.
class_name FindTilesQuest
extends QuestKind

var _found: Dictionary = {}     # "x,y" -> true

func on_rest_found(tile: Vector2i) -> void:
	_found["%d,%d" % [tile.x, tile.y]] = true

func progress() -> int:
	return _found.size()

func save_state() -> Dictionary:
	return {"found": _found.keys()}

func load_state(state: Dictionary) -> void:
	_found = {}
	for k in state.get("found", []):
		_found[String(k)] = true
