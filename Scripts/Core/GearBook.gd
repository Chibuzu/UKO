# GearBook.gd
# Gear CONTENT, separate from spells (SpellBook) and engine numbers (Config).
#
# A fighter does NOT own spells directly. A fighter owns a LOADOUT: up to four
# gear pieces, one per block on the sprite. Each gear piece carries a block
# COLOR (the square that represents it) and grants exactly one SPELL. Swap the
# gear in a slot and you swap both the block and the spell it casts. An empty
# slot ("") is the neutral/white block and grants nothing.
#
# This is the seam where per-gear stat modifiers and set bonuses will plug in
# later (add "stats" / "set" keys here; the resolver and stat math read them).
# Right now each gear just wraps one of the three starter spells.
class_name GearBook
extends RefCounted

const GEAR := {
	"discount_charm": {
		"name": "Sage Helm",
		"slot": "helmet",
		"block_color": Color("4caf7d"),   # [PH] block tint, used once art is layered
		"spell": "energy_buff",
		"overlay": "hat",                 # gear-overlay sprite prefix (hat_1..4)
		"cost": 500,
		# "stats": { ... },   # future: ap/def/hp/mp modifiers
		# "set": "...",       # future: set-bonus tag
	},
	"burst_node": {
		"name": "Burst Plate",
		"slot": "chest",
		"block_color": Color("e0683c"),
		"spell": "aoe_burst",
		"overlay": "chest",
		"cost": 500,
	},
	"blink_boots": {
		"name": "Blink Greaves",
		"slot": "legs",
		"block_color": Color("3cc8e0"),
		"spell": "blink_step",
		"overlay": "legs",
		"cost": 500,
	},
	"dark_focus": {
		"name": "Bolt Amulet",
		"slot": "jewellery",
		"block_color": Color("7a4fd0"),
		"spell": "dark_bolt",
		"overlay": "jewelry",
		"cost": 500,
	},
}

static func gear_def(gear_id: String) -> Dictionary:
	return GEAR.get(gear_id, {})

# The spell granted by a gear piece ("" if the slot is empty / gear unknown).
static func spell_of(gear_id: String) -> String:
	return String(GEAR.get(gear_id, {}).get("spell", ""))

static func block_color(gear_id: String) -> Color:
	return GEAR.get(gear_id, {}).get("block_color", Color(1, 1, 1, 1))

# Gear-overlay sprite prefix (e.g. "hat" -> hat_1..4.png) and shop price.
static func overlay_of(gear_id: String) -> String:
	return String(GEAR.get(gear_id, {}).get("overlay", ""))

static func cost_of(gear_id: String) -> int:
	return int(GEAR.get(gear_id, {}).get("cost", 0))

# ── Slots (one gear piece per slot) ─────────────────────────────────────
# The four blocks on a fighter, shown top-to-bottom on the gear screen.
const SLOT_ORDER := ["helmet", "chest", "legs", "jewellery"]
const SLOT_LABEL := {
	"helmet": "HELMET", "chest": "CHEST", "legs": "LEGS", "jewellery": "JEWELLERY",
}

# The gear currently filling a slot ("" if none). Starter loadout has one per slot.
static func gear_in_slot(slot: String) -> String:
	for id in GEAR:
		if String(GEAR[id].get("slot", "")) == slot:
			return id
	return ""

# Spell stats for a gear piece, as ready-to-print strings for the gear screen.
# Pure presentation — reads SpellBook through Config.def.
static func spell_summary(gear_id: String) -> Dictionary:
	var sid := spell_of(gear_id)
	if sid == "":
		return {"spell": "(none)", "tiles": "-", "damage": "-", "cooldown": "-", "mp": "-"}
	var s: Dictionary = Config.def(sid)
	var shape := String(s.get("shape", ""))
	var coverage := shape
	match shape:
		"self":   coverage = "Self"
		"around": coverage = "%dx%d (%d tiles)" % [
			Config.AROUND_RADIUS * 2 + 1, Config.AROUND_RADIUS * 2 + 1,
			(Config.AROUND_RADIUS * 2 + 1) * (Config.AROUND_RADIUS * 2 + 1)]
		"line":   coverage = "Line, range %d" % int(s.get("range", 0))
		"blink":  coverage = "Teleport %d tiles" % int(s.get("range", 0))
	var eff: Dictionary = s.get("effect", {})
	var dmg := "-"
	if String(eff.get("type", "")) == "damage":
		dmg = str(int(eff.get("amount", 0)))
	return {
		"spell": String(s.get("name", sid)),
		"tiles": coverage,
		"damage": dmg,
		"cooldown": "%d" % int(s.get("cooldown", 0)),
		"mp": "%d" % int(s.get("mp_cost", 0)),
	}
