# LevelProgress.gd
# The LEVELS campaign save: which level is unlocked, which are beaten, all in
# user://levels.cfg. Deliberately separate from the story save and the profile
# (gold/gear live on PlayerProfile; this file only remembers the ladder).
# Death costs nothing here (Fra: retry-friendly tutorial) -- only victories write.
class_name LevelProgress
extends RefCounted

const SAVE_PATH := "user://levels.cfg"

static var _unlocked: int = 1        # highest level the player may enter (1-based)
static var _beaten: Dictionary = {}  # level number -> true
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		_unlocked = int(cf.get_value("levels", "unlocked", 1))
		_beaten = {}
		for n in cf.get_value("levels", "beaten", []):
			_beaten[int(n)] = true

static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("levels", "unlocked", _unlocked)
	cf.set_value("levels", "beaten", _beaten.keys())
	cf.save(SAVE_PATH)

static func unlocked() -> int:
	_ensure_loaded()
	return _unlocked

static func is_unlocked(n: int) -> bool:
	return n <= unlocked()

static func is_beaten(n: int) -> bool:
	_ensure_loaded()
	return _beaten.has(n)

# Victory: remember the clear and open the next door. Idempotent -- replaying a
# beaten level for fun never regresses anything.
static func mark_beaten(n: int) -> void:
	_ensure_loaded()
	_beaten[n] = true
	_unlocked = maxi(_unlocked, mini(n + 1, LevelBook.count()))
	_save()

# The grenade is EARNED at level 8 (Fra's ladder). Inside levels it stays locked
# until then; duels are untouched (every duelist always carries it there).
static func grenade_unlocked() -> bool:
	return is_beaten(8)

# Fresh ladder (dev/reset button use).
static func reset() -> void:
	_unlocked = 1
	_beaten = {}
	_loaded = true
	_save()
