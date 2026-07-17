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
# true-action system. Ported: bat, slime (the ooze), serpent.
class_name MobSpec
extends RefCounted

const TABLE := {
	"bat": {
		"name": "Bat", "art": "bat", "tint": Color(0.62, 0.80, 1.00), "scale": 0.72,
		"hp": 45,
		"body": [],                                  # single tile
		"loadout": {
			"move":   {},                            # engine defaults
			"attack": { "range": 2, "power": 10 },   # ranged poke down a cardinal line
			"wait":   {},                            # the always-act-twice filler (0 EP)
		},
		"brain": "CharacterBat",
		"loot": [ { "item": "bat_wing", "chance": 0.55 } ],
	},
	# The ooze. Type id stays "slime" (spawn tables, saves and loot key on it); its art
	# set is "ooze". It owns no ranged option at all -- it can only ever brawl.
	"slime": {
		"name": "Slime", "art": "ooze", "tint": Color(0.55, 1.00, 0.62), "scale": 0.90,
		"hp": 80,
		"body": [],                                  # single tile
		"loadout": {
			"move":   {},
			"attack": { "all_adjacent": true, "power": 10 },   # ONE spit hits all four neighbours
			"wait":   {},
		},
		"brain": "CharacterOoze",
		"loot": [ { "item": "slime_gel", "chance": 0.70 } ],
	},
	# The cave boss (Fra): TWO identical twins, spawned side by side. Each is a plain
	# SINGLE-TILE creature -- no body, no pivot, none of the multi-tile machinery. The
	# boss is a pair, not a shape, and the cage only opens when both are down.
	# Two bodies is itself the mechanic: you cannot face both, so one is always flanking.
	"serpent": {
		"name": "Serpent", "art": "twin", "tint": Color(1.0, 1.0, 1.0), "scale": 1.0,
		"hp": 75,
		"facing_bar": true,                          # it HAS a facing: show it on its head
		"body": [],                                  # ONE tile each
		"loadout": {
			"move":   {},                            # one tile per action
			"attack": { "power": 10 },               # range 1, ONE tile (not the ooze's four)
			"wait":   {},
		},
		"brain": "CharacterTwin",
		"loot": [ { "item": "serpent_scale", "chance": 1.00 }, { "item": "serpent_fang", "chance": 0.20 } ],
	},
}

# The body offsets a row asks for (empty = a normal one-tile creature).
static func body_of(prof: Dictionary) -> Array:
	var n := int(prof.get("body_line", 0))
	return Resolver.shape_line(n) if n >= 2 else []

static func row(type: String) -> Dictionary:
	return TABLE.get(type, {})

# Is this species on the new true-action system yet?
static func is_character(type: String) -> bool:
	return TABLE.has(type)

# Copy a row's engine-visible values onto the Combatant the resolver reads. (Without
# this, the spec is decoration: the engine checks fields like `attack_range` and `body`
# ON THE UNIT.) Call it right after building a character's combatant.
static func apply_spec(c: Combatant, prof: Dictionary) -> void:
	c.body = body_of(prof)
	var lo: Dictionary = prof.get("loadout", {})
	if lo.has("attack"):
		c.attack_power = int(lo["attack"].get("power", 0))          # 0 = the duel default
		c.attack_range = int(lo["attack"].get("range", 1))
		c.attack_all_adjacent = bool(lo["attack"].get("all_adjacent", false))
