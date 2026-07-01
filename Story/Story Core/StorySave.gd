# StorySave.gd
# Save/quit persistence for story mode. One slot, written as JSON to user:// so it
# survives closing the game. The snapshot is small and complete enough to rebuild the
# session exactly: the world SEED (the map is regenerated deterministically from it),
# the player's tile + resources, and every LIVING mob's type/tile/state. Gear and gold
# are NOT stored here -- they live in PlayerProfile, which is already persistent and
# shared with PLAY.
class_name StorySave
extends RefCounted

const PATH := "user://story_save.json"

static func has_save() -> bool:
	return FileAccess.file_exists(PATH)

static func write(data: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()

static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
