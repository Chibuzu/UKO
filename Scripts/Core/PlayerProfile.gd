# PlayerProfile.gd
# The player's PERSISTENT account: gold, owned gear, and the equipped loadout.
# Saved to user://profile.cfg so it survives between sessions. Kept as a static
# carrier (like AI.selected_difficulty) rather than an autoload — any script
# reads it via PlayerProfile.gold() / .loadout() and the file loads itself
# lazily on first touch.
#
# Gear drives spells: the equipped piece in each slot grants its spell (see
# GearBook), so the loadout the shop builds here IS the player's spell kit.
class_name PlayerProfile
extends RefCounted

const SAVE_PATH := "user://profile.cfg"

static var _gold: int = 0
static var _owned: Dictionary = {}      # gear_id -> true
static var _equipped: Dictionary = {}   # slot -> gear_id
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		_gold = int(cf.get_value("wallet", "gold", 0))
		_owned = {}
		for id in cf.get_value("gear", "owned", []):
			_owned[String(id)] = true
		_equipped = cf.get_value("gear", "equipped", {}).duplicate()

static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("wallet", "gold", _gold)
	cf.set_value("gear", "owned", _owned.keys())
	cf.set_value("gear", "equipped", _equipped)
	cf.save(SAVE_PATH)

# ── Gold ────────────────────────────────────────────────────────────────
static func gold() -> int:
	_ensure_loaded()
	return _gold

# Add winnings; returns the new balance. Clamped at 0 so nothing goes negative.
static func add_gold(amount: int) -> int:
	_ensure_loaded()
	_gold = maxi(0, _gold + amount)
	_save()
	return _gold

# Try to spend; deducts only if affordable (kept for non-gear sinks).
static func spend_gold(amount: int) -> bool:
	_ensure_loaded()
	if _gold < amount:
		return false
	_gold -= amount
	_save()
	return true

# ── Gear ownership / loadout ────────────────────────────────────────────
static func is_owned(gear_id: String) -> bool:
	_ensure_loaded()
	return _owned.has(gear_id)

# The gear filling a slot ("" = empty / white block).
static func equipped_in(slot: String) -> String:
	_ensure_loaded()
	return String(_equipped.get(slot, ""))

static func is_equipped(gear_id: String) -> bool:
	var slot := String(GearBook.gear_def(gear_id).get("slot", ""))
	return slot != "" and equipped_in(slot) == gear_id

# The four slots in canonical order, ready for Combatant.equip(). Empty slots
# come through as "" so an ungeared fighter is white with no spells.
static func loadout() -> Array:
	_ensure_loaded()
	var out: Array = []
	for slot in GearBook.SLOT_ORDER:
		out.append(equipped_in(slot))
	return out

# Equip an owned piece into its slot (no-op if not owned).
static func equip(gear_id: String) -> bool:
	_ensure_loaded()
	if not _owned.has(gear_id):
		return false
	var slot := String(GearBook.gear_def(gear_id).get("slot", ""))
	if slot == "":
		return false
	_equipped[slot] = gear_id
	_save()
	return true

# Take a slot back to the empty/white block.
static func unequip(slot: String) -> void:
	_ensure_loaded()
	_equipped.erase(slot)
	_save()

# Buy a piece: if affordable and not already owned, deduct, own, and equip it.
# Returns true on success.
static func buy(gear_id: String) -> bool:
	_ensure_loaded()
	if _owned.has(gear_id):
		return false
	var cost := GearBook.cost_of(gear_id)
	if _gold < cost:
		return false
	_gold -= cost
	_owned[gear_id] = true
	var slot := String(GearBook.gear_def(gear_id).get("slot", ""))
	if slot != "":
		_equipped[slot] = gear_id
	_save()
	return true

# Wipe everything (handy for a reset button / testing).
static func reset() -> void:
	_gold = 0
	_owned = {}
	_equipped = {}
	_loaded = true
	_save()
