# MobSpec.gd -- THE species table (one row = one creature, all its truth in one place).
#
# This is the new mob architecture's data layer: every difference between creatures
# lives HERE as data, never as if-chains in code. A row gives:
#   look    -- name / art set / tint / scale
#   stats   -- hp (energy is always a full pool; the story refills it each turn)
#   body    -- footprint offsets for Combatant.body ([] = one tile; the serpent will
#              be Resolver.shape_line(2); a big boss Resolver.shape_rect(4, 4))
#   loadout -- the BASE SPELLS this creature has equipped, with per-spell tuning.
#              A creature can ONLY ever use what is equipped -- the loadout IS the
#              personality (a bat cannot guard because it does not own guard).
#   brain   -- which Brain class drives it (one small file per species)
#   loot    -- drop table
#
# MIGRATION STATUS: species move here one at a time as they are ported to the
# true-action system. Ported: bat. Pending (still on MobBrain.PROFILES + the old
# budget-strike path): slime, serpent.
class_name MobSpec
extends RefCounted

const TABLE := {
	"bat": {
		"name": "Bat", "art": "bat", "tint": Color(0.62, 0.80, 1.00), "scale": 0.72,
		"hp": 45,
		"body": [],                                  # single tile
		"loadout": {
			"move":   {},                            # engine defaults
			"attack": { "range": 2 },                # ranged poke down a cardinal line
			"wait":   {},                            # the always-act-twice filler (0 EP)
		},
		"brain": "CharacterBat",
		"loot": [ { "item": "bat_wing", "chance": 0.55 } ],
	},
}

static func row(type: String) -> Dictionary:
	return TABLE.get(type, {})

# Is this species on the new true-action system yet?
static func is_character(type: String) -> bool:
	return TABLE.has(type)

# Copy the loadout's engine-visible tunings onto the Combatant the resolver reads.
# (Without this, loadout numbers are decoration: the resolver checks fields like
# `attack_range` ON THE UNIT. Call it right after building a character's combatant.)
static func apply_loadout(c: Combatant, prof: Dictionary) -> void:
	var lo: Dictionary = prof.get("loadout", {})
	if lo.has("attack"):
		c.attack_range = int(lo["attack"].get("range", 1))
		c.attack_all_adjacent = bool(lo["attack"].get("all_adjacent", false))
