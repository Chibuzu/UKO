# PlayerInventory.gd
# The player's persistent bag of drop ITEMS (item_id -> count), saved to
# user://inventory.cfg. Same static-carrier pattern as PlayerProfile: it lazy-loads on
# first touch and saves on every change, so any screen can read it without wiring an
# autoload. Deliberately tiny (add / count / all / clear) so future systems -- crafting,
# quests, a viewer panel, using items -- build straight on top of it.
class_name PlayerInventory
extends RefCounted

const SAVE_PATH := "user://inventory.cfg"

static var _counts: Dictionary = {}     # item_id -> int
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		_counts = cf.get_value("items", "counts", {}).duplicate()

static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("items", "counts", _counts)
	cf.save(SAVE_PATH)

# Add n of an item (ignores unknown ids / non-positive n). Returns the new count.
static func add(item_id: String, n: int = 1) -> int:
	_ensure_loaded()
	if not ItemBook.has(item_id) or n <= 0:
		return int(_counts.get(item_id, 0))
	_counts[item_id] = int(_counts.get(item_id, 0)) + n
	_save()
	return int(_counts[item_id])

static func count(item_id: String) -> int:
	_ensure_loaded()
	return int(_counts.get(item_id, 0))

# Everything held, {item_id: count}, positive counts only.
static func all() -> Dictionary:
	_ensure_loaded()
	var out: Dictionary = {}
	for k in _counts:
		if int(_counts[k]) > 0:
			out[k] = int(_counts[k])
	return out

static func clear() -> void:
	_counts = {}
	_loaded = true
	_save()
