# PlayerProfile.gd
# The player's PERSISTENT account: gold today, unlocked gear later. Saved to
# user://profile.cfg so it survives between sessions. Kept as a static carrier
# (like AI.selected_difficulty) rather than an autoload — any script reads it
# via PlayerProfile.gold() and the file loads itself lazily on first touch.
#
# Spending is here too (spend_gold) so a future GEAR shop has one wallet to call.
class_name PlayerProfile
extends RefCounted

const SAVE_PATH := "user://profile.cfg"

static var _gold: int = 0
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		_gold = int(cf.get_value("wallet", "gold", 0))

static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("wallet", "gold", _gold)
	cf.save(SAVE_PATH)

# Current balance (loads the save file on first call).
static func gold() -> int:
	_ensure_loaded()
	return _gold

# Add winnings; returns the new balance. Clamped at 0 so nothing can go negative.
static func add_gold(amount: int) -> int:
	_ensure_loaded()
	_gold = maxi(0, _gold + amount)
	_save()
	return _gold

# Try to spend; returns true and deducts only if affordable (for the gear shop).
static func spend_gold(amount: int) -> bool:
	_ensure_loaded()
	if _gold < amount:
		return false
	_gold -= amount
	_save()
	return true

# Wipe the wallet (handy for a "reset progress" button or testing).
static func reset() -> void:
	_gold = 0
	_loaded = true
	_save()
