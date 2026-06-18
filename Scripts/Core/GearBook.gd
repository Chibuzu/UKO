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
		"name": "Discount Charm",
		"block_color": Color("4caf7d"),   # [PH] block tint, used once art is layered
		"spell": "energy_buff",
		# "stats": { ... },   # future: ap/def/hp/mp modifiers
		# "set": "...",       # future: set-bonus tag
	},
	"burst_node": {
		"name": "Burst Node",
		"block_color": Color("e0683c"),
		"spell": "aoe_burst",
	},
	"dark_focus": {
		"name": "Dark Focus",
		"block_color": Color("7a4fd0"),
		"spell": "dark_bolt",
	},
}

static func gear_def(gear_id: String) -> Dictionary:
	return GEAR.get(gear_id, {})

# The spell granted by a gear piece ("" if the slot is empty / gear unknown).
static func spell_of(gear_id: String) -> String:
	return String(GEAR.get(gear_id, {}).get("spell", ""))

static func block_color(gear_id: String) -> Color:
	return GEAR.get(gear_id, {}).get("block_color", Color(1, 1, 1, 1))
