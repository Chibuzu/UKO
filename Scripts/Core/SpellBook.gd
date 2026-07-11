# SpellBook.gd
# ALL spell and status CONTENT lives here, on its own, away from the engine's
# core numbers in Config.gd. This is the file you open to add or tweak spells
# and buffs — you should rarely need to touch anything else.
#
# A spell is data: a SHAPE (which tiles it touches) + an EFFECT (what it does).
#   shape  : "self" | "around" | "line"   (+ "range" for line)
#   effect : { "type": "damage", "amount": N }
#            { "type": "apply_status", "status": "<id>", "to": "self" }
#   needs_tile : true if the player aims it (line spells)
#
# To add a spell: copy an entry, change the numbers, give it a new id, set its
# "ai_role" (how the AI uses it) and "vfx" (how the view shows it), then point a
# GearBook piece's "spell" at it and equip that gear. A fighter only ever casts
# spells granted by its equipped gear.
# New buffs go in STATUSES and are applied via an "apply_status" effect.
class_name SpellBook
extends RefCounted

const SPELLS := {
	"energy_buff": {
		"name": "DISCOUNT", "category": "spell",
		"band": Config.Band.BUFF, "base_tick": 20,
		"energy_cost": 0, "mp_cost": 10, "cooldown": 3,
		"needs_tile": false,
		"shape": "self",
		"effect": { "type": "apply_status", "status": "energy_discount", "to": "self" },
		"ai_role": "buff",                                   # how the AI uses it
		"vfx": { "style": "self_buff", "cast_anim": "buff" },# how the view shows it
	},
	"aoe_burst": {
		"name": "BURST", "category": "spell",
		"band": Config.Band.AOE, "base_tick": 40,
		"energy_cost": 0, "mp_cost": 30, "cooldown": 2,
		"needs_tile": false,
		"shape": "around",
		"effect": { "type": "damage", "amount": 15 },   # [PH] less than a basic attack
		"ai_role": "aoe",
		"vfx": { "style": "aoe", "cast_anim": "" },
	},
	"dark_bolt": {
		"name": "DARK BOLT", "category": "spell",
		"band": Config.Band.ATTACK, "base_tick": 50,   # LAUNCH tick (~350, point-blank); travels out from there
		"energy_cost": 0, "mp_cost": 40, "cooldown": 4,
		"needs_tile": true,
		"shape": "line", "range": 3,
		"projectile": true, "tick_per_tile": 200, "pierce": false,  # flies tile-by-tile; dodge by leaving the line
		"effect": { "type": "damage", "amount": 25 },   # [PH] see balance note
		"no_guard_combo": true,                          # cannot share a turn with Guard
		"ai_role": "poke",
		"vfx": { "style": "projectile", "cast_anim": "bolt", "projectile": "bolt_proj" },
	},
	"grenade": {
		"name": "GRENADE", "category": "spell",
		"band": Config.Band.ATTACK, "base_tick": 0,     # launches at the very start of the ATTACK band
		"energy_cost": 0, "mp_cost": 0, "cooldown": 0,
		"once_per_match": true,                          # a single use for the whole match (see _legalize)
		"needs_tile": true,
		"shape": "throw", "range": 3, "diag_range": 1,   # 3 tiles orthogonally, 1 tile diagonally
		"projectile": true, "tick_per_tile": 180, "pierce": false,   # flies tile-by-tile; each tile a tick tax
		# Disrupt, not damage: drains 20 energy and ROOTS the target (its next move is cancelled).
		"effect": { "type": "disrupt", "energy_drain": 20, "status": "rooted", "amount": 1 },   # 1 dmg: interrupts a rest AND blocks next turn's (damaged_tick path)
		"no_guard_combo": true,
		"ai_role": "item",
		"vfx": { "style": "projectile", "cast_anim": "bolt", "projectile": "bolt_proj" },
	},
	"blink_step": {
		"name": "BLINK", "category": "spell",
		"band": Config.Band.PIVOT, "base_tick": 0,   # fast: resolves before the ATTACK band
		"energy_cost": 0, "mp_cost": 40, "cooldown": 4,
		"needs_tile": true,                          # player aims a direction
		"shape": "blink", "range": 2,                # fixed 2-tile jump, phases through tile 1
		"tick_per_tile": 300,                        # teleport travel/tile: arrives depart + range*this
		"effect": { "type": "blink" },               # relocate the caster (+ free reface)
		"ai_role": "blink",
		"vfx": { "style": "blink", "cast_anim": "" },
	},
}

# Timed statuses (buffs/debuffs). duration = how many of the owner's turns it
# lasts after the turn it is applied.
const STATUSES := {
	"energy_discount": { "duration": 3, "energy_cost_reduction": 5 },   # lasts 3 full turns after cast (=6 actions @ 2/turn)
	# ROOTED: the target's next MOVE is cancelled. duration 2 so it survives end-of-turn ageing
	# and still blocks the FIRST move next turn if the grenade landed too late this turn. It is
	# consumed the instant it blocks a move (erased in the resolver), so it never lingers.
	"rooted": { "duration": 2, "blocks_move": true },
}
